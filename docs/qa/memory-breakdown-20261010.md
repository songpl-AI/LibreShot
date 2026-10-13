# LibreShot 内存拆分与验证记录

日期：2026-10-10。本文把 Issue 反馈、`vmmap`/`ps` 采样和源码定位放在同一份记录中。MiB 均按 1,048,576 字节计算。`Physical footprint`、`ps` 的 RSS 和活动监视器的“内存”列分别记录；本轮最终 r4 已完成同 PID、覆盖 UI 观察时刻的对照，活动监视器默认列数值接近 footprint，而不是 RSS，不能用共享 RSS 解释掉用户看到的 100–122 MB。

## 结论先行

**最终 r4 的最新结果：同包重启前后普通截图、标注和保存均成功，30 次普通启动/取消未观察到持续增长。** 重启初始 footprint 36.4 MiB；实际截图/编辑/保存内核峰 131.6 MiB；30 次取消后静置约 48.5 MiB。两轮长图拼接失败并退出、后续又有普通预览操作，最终稳定配对为 55.8 MiB，内核历史峰已到 146.7 MiB；不能把它当纯长图成功后的回落。活动监视器 14:15:41 显示主 PID 74368 为 48.6 MB，同一时刻范围内采样为 footprint 48.6 MiB、RSS 117.1 MiB。另列系统 XPC `ThemeWidgetControlViewService (LibreShot)` 约 9.6 MB，不计入主进程数值。20–30 MB 闲置目标尚未达到，也没有严格 A/B 证据承诺已减少 80 MiB。长截图、OCR、翻译等专项状态见 [r4 包 QA](1.3.10-32-memory-lifecycle-r4-20261010.md)。

下面的早期样本保留作为实验历史，不能替代最终 r4 的数据。

10 月 10 日 07:13 的早期候选在同包重启后的普通区域截图样本中：闲置约 38.3–38.5 MiB，截图/保存采样峰值 82.9 MiB（内核记录 peak 83.0 MiB），1 秒约 40.6 MiB，15 秒约 38.7 MiB，60 秒约 38.5 MiB。峰值后 graphics backing 会回落，现有证据不支持该次操作“截图后几十 MiB 图像一直泄漏”。该样本不是最终 r4，不能替代 r4 验收。

上述早期候选采样的 `ps` RSS 约 106–120 MiB；RSS 可以包含共享驻留页、文件映射页及可回收页，不能全部归为 LibreShot 可独占释放的业务对象。最终 r4 的对照已证明本次活动监视器默认列不是这批 RSS；不能倒推用户最初 100–122 MB 的具体场景或原因。

## 最终 r4 闲置内存清单

证据为 PID 74368 在 30 次取消后 `14:14:21.901` 的稳定 heap/vmmap 配对；原始数据与分析位于 [运行时报告](../../dist/lifecycle-r4-validation-20261010/RUNTIME-ANALYSIS.md)。下表按互斥 vmmap 区域的 **dirty+swap 归属量** 拆分，合计约 48.5 MiB；包含已压缩/换出负担，不等于当前全部驻留 RAM。

| 部分 | 归属量 | 可优化性与边界 |
| --- | ---: | --- |
| `MALLOC_SMALL` | 31.68 MiB | 最大调查目标；混合业务/框架对象、缓存和 allocator arena。需要分配栈，不能全算成 SwiftUI，也不能全部释放 |
| `__DATA` + `__DATA_DIRTY` | 5.21 MiB | 运行时和框架私有数据；减少加载的功能可能间接降低，不能直接清空 |
| shared memory | 1.89 MiB | 进程/系统共享机制；必须查来源后判断 |
| `CoreAnimation` | 1.20 MiB | 窗口合成资源；清窗口可减少部分，回收时机受系统控制 |
| malloc metadata | 1.13 MiB | 分配器管理成本；主要通过减少对象数量间接降低 |
| AttributeGraph old mapping | 1.00 MiB | SwiftUI 图结构的映射；并非全部活跃视图，可探索延迟加载 |
| `IOAccelerator (graphics)` | 0.75 MiB | 剩余 GPU/合成资源；可缩短持有时间，无法保证即时归还 |
| 其余数据段、线程栈、CoreUI、小量图形等 | 5.67 MiB | 多种小项，不能当成一个可删除缓存 |

heap 的 allocated 分类是另一维度，**不能加到上表**：38.58 MiB 中，未知 non-object 19.59 MiB（其中 38×360,448 bytes 共 13.06 MiB 尚无来源），具名 SwiftUI 约 4.07 MiB、Swift metadata 3.16 MiB、CoreFoundation 3.06 MiB、ObjC method cache 1.25 MiB、CoreGraphics 1.13 MiB、AppKit 0.58 MiB，其余较小。没有分配栈之前，13.06 MiB 只能列为重点待查，不能承诺可回收。

该稳定快照未发现 overlay/controller/viewModel、SCStream 或 CaptureRequestState 实例，也没有活跃的大图像 malloc buffer，支持普通取消链路已清理的判断；这不是所有功能无泄漏的证明。普通截图峰值命中的另一个样本有 72.5 MiB `owned unmapped (graphics)`，保存后回落到约 0.45 MiB；峰值缓冲和闲置 31.68 MiB small malloc 是两个不同优化问题。

最终收尾 `14:47:37.916` 的另一份稳定配对为 55.8 MiB，未识别出 overlay、SCStream、LongCaptureSession、FrameAccumulator 或 Stitcher 实例，也没有活跃 MALLOC_LARGE 大块。相对上述 48.5 MiB 快照多约 7.27 MiB，主要是 MALLOC_SMALL +4.52、SMALL(empty) +2.03、其它 MALLOC +0.73 MiB；其余小项增减相抵。这仍需分配栈归因，不能断言全部可优化。heap 总分配容量 43.04 MiB，新增一组 14×368 KiB（约 5.03 MiB）也未查明来源；不得与物理区域表重复加总。

最后额外普通预览命中的 141 MiB 样本，主要为 `CG raster data` 39.5 MiB、全屏 CPU malloc 副本 22.7 MiB、小堆及既有缓存，owned graphics 仅约 0.45 MiB。因此百兆峰既可能来自图形 backing，也可能来自 CPU 光栅化/复制叠加缓存，不能统一归为 GPU。

两轮真实长图均报拼接失败。首轮流释放后 footprint 在约 92 MiB 暂留，约 58 秒后降到 51 MiB，对应已释放图像转为 allocator empty 后才归还物理页。第二轮小步滚动仍失败；独立离屏 fixture 正常帧全部可拼接，另一个探针证明零位移的单像素重绘可使已接好的长图无法导出。该机制已复现，但真实现场根因仍待输入帧证据，不把失败测试写成功。详见 [本包验收](1.3.10-32-memory-lifecycle-r4-20261010.md)。

## 普通截图峰值拆分

证据目录：

`/Users/happyelements/.codex/visualizations/2026/10/09/01a11eca-5de7-7701-82d0-2b4fbdc5d426/candidate-memory-validation/after-restart-sample/`

| 部分 | 闲置 | 峰值 | 判断 |
| --- | ---: | ---: | --- |
| `owned unmapped (graphics)` | 约 48 KiB | 约 40.5 MiB resident/dirty | 主要是 overlay/截图 backing 与裁剪期间的图形缓冲；峰值约一半，随后异步回收 |
| `MALLOC_SMALL` | 约 18.3 MiB | 约 19.6 MiB | Swift/SwiftUI/AppKit 对象、字符串、窗口状态和 allocator arena；有一部分可优化，不能全部立即归还 |
| `IOAccelerator (graphics)` | 约 0.77 MiB | 约 3.12 MiB | GPU/WindowServer 图形资源，结束捕获后可回收，业务代码控制有限 |
| `IOSurface` | 约 0.13 MiB | 约 0.40 MiB | 屏幕采集交换面，场景性开销 |
| `CoreAnimation` | 约 0.02 MiB | 约 0.13 MiB | 窗口合成状态，量小 |
| `__DATA_DIRTY`、metadata、线程等 | 其余 | 约数 MiB | 运行时私有页和元数据，不能按单一功能归属 |

峰值与闲置相差约 44.6 MiB，其中 graphics 约 40.5 MiB，`MALLOC_SMALL` 只增加约 1.3 MiB。1 秒后 graphics resident 仍可能约 32.5 MiB，但 dirty 已降到约 0.46 MiB；随后几秒降到约 0.46 MiB，长期约 48 KiB。这是异步图形回收过程，不是长期图像驻留。

源码上，`OverlayViewModel.imageForExport()` 传出的是整屏预览 `CGImage`；`CaptureService.crop()` 再创建独立选区缓冲。因此源整屏 backing 与裁剪输出短时间重叠，这是普通截图峰值的候选来源。`vmmap` 分类尚未精确定位到每个业务分配栈，表内 resident 分类也不能直接相加当作 footprint。把 `overlayWindowController` 置空可以缩短 controller 生命周期，但不能让回调参数中的整屏 `CGImage` 在裁剪前消失，所以不能承诺单靠这一项再减少 40–80 MiB。

## OCR、翻译和旧编码路径

| 场景 | Physical footprint 观察 | 结论 |
| --- | ---: | --- |
| OCR 前编辑器闲置 | 约 35.8–43.0 MiB | 已包含编辑器/SwiftUI 状态 |
| OCR 操作期间主进程采样峰值 | 约 52.8 MiB | 原 CSV 样本 1736 为主 PID 85733，helper_pids 为空；这是主进程操作采样值，不是 OCR worker 独占峰值 |
| OCR 结果窗口 | 约 51.0 MiB | 结果窗口和共享框架映射增加；关闭后回落 |
| 关闭 OCR 后 | 约 46.6 MiB | owner、delegate、content 清理有效，但 allocator arena 不一定马上归还 |
| 翻译边界 | 约 46.7 MiB | 未发现独立 Translation 子进程，主进程变化不到约 1 MiB，暂无可归属的大块翻译泄漏证据 |
| 旧 Pinned 保存路径 | 约 243–249 MiB 峰值 | 重复未压缩编码造成的瞬时峰值，已改为直接 PNG/无损 TIFF 路径 |
| 新 Pinned 保存/复制 | 保存约 23.5–24.8 MiB；复制约 37.7–50.9 MiB | 回落到约 23.5 MiB，说明旧编码旁路已消除 |

长截图曾有约 88.3 MiB 的不完整采样，但当时输入监控无法完成真实滚动和回车结束，不能把它写成正式长截图峰值；长截图流仍需单独做真实网页、多帧、完成和关闭后的验证。

本表来自早期候选或隔离 fixture，均不能替代 r4 的 OCR、翻译与长截图专项结果。按秒采样还可能漏掉短命 helper 和短时峰值；没有观察到 helper 不等于它没有启动。

## 哪些可以优化

1. **整屏源图与裁剪图重叠**：`sourceRect` r2 实验已完成，但普通/direct 两组仍有约 40.5 MiB graphics resident，没有测出预期的 80 MiB 级收益；两组操作内容不完全相同，不能当作严格统计 A/B。direct 还改变冻结帧语义，因此保持默认路径。一次性静态截图 API 可进一步做相同 PNG 消费实验，不能仅凭未绘制原图的低 footprint 宣称整应用收益。详见 [sourceRect 实测](sourceRect-r2-validation-20261010.md) 和 [独立探针](../../dist/static-capture-probe-20261010/RESULTS.md)。
2. **overlay/host/preview 生命周期**：当前结束会话会取消预览任务、清空 SwiftUI hosting content、preview image、回调和屏幕引用；区域回调先释放 owner，再通过 `Task.yield()` 让出调度后裁剪。让出调度不保证已经完成一轮事件循环或系统 graphics 回收。它能避免窗口和异步任务长期持有资源，但不会消除整屏回调图像本身。
3. **保存与复制编码**：旧的重复编码路径已修复；继续保持“每次动作只编码一次”，避免把整张图转未压缩中间格式。
4. **OCR/结果窗口 owner**：关闭时解除 content、delegate、window 和 AppDelegate owner；这能降低重复打开后的活跃对象，但不能让系统框架共享页全部消失。
5. **截图流生命周期**：r4 普通截图使用每请求状态、局部 stream/output/scale、串行生命周期 gate，先原子领取首帧再复制，等待 startup 返回后统一 stop；长截图也串行 start/stop、清理选区帧和拼接器。确定性回归通过，但仍需要最终安装包连续取消、普通/长截图交替和真实多帧测试确认稳定性与内存上限。

## 哪些只能部分优化或基本不能优化

- 早期 `MALLOC_SMALL` 的约 16–21 MiB 驻留区，最终 r4 稳定样本为约 31.68 MiB dirty+swap 归属量：可以通过按需创建窗口、清 owner、减少缓存降低一部分；其中活跃对象、allocator 空闲缓存和碎片各占多少仍需分配栈证据，不能仅凭 vmmap 分类全称为活跃对象。
- `IOAccelerator`、`IOSurface`、`CoreAnimation`：结束捕获后可回收一部分，具体由 WindowServer/CoreAnimation 调度，业务代码只能减少持有时间。
- `__TEXT`、`__OBJC_RO`、`__AUTH_CONST`、mapped file：主要是系统框架和代码共享映射，不能把它们相加当作 LibreShot 独占内存，也不适合用业务对象清理解决。
- `Memory Tag 22`、`STACK GUARD`：本次样本主要为虚拟地址保留，不能把 virtual 数量当作实际 RAM。
- `MALLOC_LARGE (empty)`：表示没有对应活跃分配，但仍可能保留驻留物理页。独立 stream 探针的约 22.7 MiB 图像已释放后，allocator 缓存约 23 秒才归还；释放对象与立即降低 footprint 是两件事。需要按 resident/dirty 与自然回收时间判断，不把 empty 全部视为零压力，也不把延迟回落直接视为泄漏。

## 当前候选包状态

最终冻结源码候选 r4 已构建并安装到 `/Applications/LibreShot.app`。目录为 `/Users/happyelements/Documents/TestProjects/LibreShot/dist/LibreShot-1.3.10-32-memory-lifecycle-20261010-r4`，版本/build 仍为 1.3.10 (32)，DMG SHA-256 为 `f0a63e25e03a532d9bd0fe825dea108752d877ecae0dc52d19be0af1080fa8f3`，候选 ad-hoc CDHash 为 `7e498375432c0cc64f5839c018152f4da04d3225`。`SOURCE.json` 固定基线 commit `b11231edf316beeec3fb2b738d546222fb3b084c`、dirty/untracked 输入与源码 hashes；`CaptureService.swift` SHA-256 为 `fcc50d62f17019b7642a126c37a639f1c898d3db333fa0e6c9df0916967da683`。Release 构建、请求生命周期、帧与窗口生命周期检查通过，日志在候选目录。最终安装副本已在同包正常重启前后各实际完成公开截图、标注及保存，基础链路通过；实体 Option、剪贴板与专项覆盖边界仍分别记录。

最终 r4 的逐项验收状态和原始截图路径单独记录于 [r4 包 QA](1.3.10-32-memory-lifecycle-r4-20261010.md)，后续以该页证据更新为准。

历史 final2 目录为 `dist/LibreShot-1.3.10-32-memory-fix-20261010-final2`，DMG SHA-256 为 `92d52ffdb2e0b8d75dfff82597a5567bca7e917708d86192f93c51950debcca9`，CDHash 为 `a0c899ac2fadb28636221a419b06490aca4a2ac8`。该包尚未恢复录屏权限、只打开设置时，PID 90355 的一次采样为 footprint 34.6 MiB、RSS 约 105.3 MiB；这是历史设置窗口样本，不是 r4 峰值或验收证据。r3 的 30 次可见取消结果（末值 49.4 MiB、历史 peak 72.6 MiB）同样仅属于 r3。

## 下一步

1. 基础授权、同包重启前后保存、30 次普通取消与活动监视器列对照已完成；输入监控状态和实体双击 Option 仍分开记录。
2. 完成公开页面真实多帧长截图，记录错误、输出和关闭后 1/15/60 秒；随后补普通/长截图交替、OCR、翻译取消/失败与复制专项。
3. 不再默认启用 direct 或更改 queueDepth；已有 [队列实验](queue-depth-validation-20261010.md) 未证明普通截图稳定收益。静态 API 下一项最小实验是同一公开页面、尺寸、PNG消费，并读取内核 peak；只有等价消费收益成立再考虑主应用开关。
4. 如果最终 r4 完成功能后仍不能达到用户关心的 20–30 MB 闲置目标，再用 Instruments Allocations/MallocStackLogging 追踪 `MALLOC_SMALL` 的活跃分配栈，并区分真实对象、allocator 缓存与系统图形页；不能仅靠更换指标宣称目标达到。

### 下一项分配栈实验的具体边界

源码已按需创建设置窗口、截图服务、OCR 任务和翻译功能；设置窗口关闭时也释放 hosting/controller。但入口仍是 `SwiftUI.App` 和 `Settings` scene，不能仅凭窗口 lazy 就认定 SwiftUI runtime 没有启动成本。优先定位未知 38×360,448 bytes 分配，而不是直接重写 UI。

本机 `malloc_history`、xctrace Allocations 模板可用，且最终包 dSYM UUID 与安装副本相符。后续可对同一未改变签名的包做**独立诊断启动**，仅给该启动传入 `MallocStackLogging=lite`，在“冷启动”“打开设置再关闭”“只做截图再取消”三个边界比较存活栈和数量。使用 `-noContent`，避免输出图片或文本内容；logging 自身有开销，诊断进程的 footprint 不能当产品基线。实际执行应保留安装来源和独立采样身份，不把这次带 instrumentation 的启动混入当前 r4 验收数据。

最终包有 hardened runtime 和 sandbox，没有 `get-task-allow`，本机 Developer mode 未启用；附加/记录是否获准尚未实际验证。若工具拒绝，保留原始错误，不重签最终包、不修改系统安全设置或重复刷新录屏权限。

诊断本身不节省内存。未知 13.06 MiB 是分配容量，能回收多少物理负担尚未测出；即使粗略假设全部变成 footprint 收益，从 48.5 MiB 减去仍约 35.5 MiB，高于 20–30 MiB 目标。因此达到目标可能还需要减少 SwiftUI/运行时初始化或其它长期成本，必须先取得栈和等价功能对照再决定。
