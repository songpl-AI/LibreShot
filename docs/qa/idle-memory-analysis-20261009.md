# LibreShot 空闲内存拆分与本轮修复

日期：2026-10-09。本文记录源码修复和本机只读诊断，不代表新安装包验收，也不关闭 Issue #20。

## 诊断结论

正式安装版 `1.3.10 (32)` 的长期运行 PID 15719 在 20:36 的 `footprint` 为 100.407 MiB。拆分如下：

| 分类 | MiB | 说明 |
| --- | ---: | --- |
| malloc 与元数据 | 61.563 | 包括 MALLOC_SMALL 59.906 MiB |
| 图像与绘制 VM | 25.281 | CoreAnimation 11.297、CoreImage 7.922 等 |
| 其余 VM | 13.564 | 框架可写数据、线程栈、页表等 |

`heap` 识别到 54.853 MiB 活跃分配，其中 32.974 MiB 是未识别的 non-object；使用字段启发式后仍有 25.504 MiB 无法归属。当前没有 MallocStackLogging，不能把它们指认给某个函数，也不能仅凭 heap 证明泄漏。约 93.4 MiB 属于 compressed/swapped 子集，但仍计入 footprint，不能从进程预算中扣除。

诊断同时发现：关闭设置窗口前的长期进程不能代表冷启动；同一正式安装路径重新启动、未执行截图且未打开设置窗口时，1/5/15/60 秒分别为 13.8/13.7/13.6/13.7 MiB。于是“启动约 20–30 MiB”是可达到的方向；长期 100 MiB 主要是功能和系统图形框架初始化后的平台，不能简单归因于一个 OCR 对象或一个窗口。

翻译任务引用树确实可以在窗口关闭后保留 `LanguageSupportHostModel` 与应用模型，但三个应用模型的可见子树只有 KiB 级；这不是几十 MiB 图像的证据。`CoreAnimation image_cache` 的引用树约 21.6 MiB，也不能直接当作可释放 footprint。

## 本轮代码修复

- `OverlayWindowController` 结束区域/长截图会话时取消预览任务、卸载 SwiftUI hosting content、清空业务回调、loader 和屏幕引用；保留完成回调读取 display ID 的多屏行为。旧版隐藏窗口后，host/content 和 callback token 仍存活；头less 回归已覆盖错误、取消、reset、晚到结果与复用。
- `OCRResultWindowController` 关闭时解除 content、delegate 和 window，并通过一次性 `onClose` 让 `AppDelegate` 清空 owner 引用。
- `PinnedImageWindowController` 的系统关闭按钮现在也执行幂等 teardown；图片、SwiftUI content 和动作回调均释放。复制/保存改走文件编码、PNG 与无损 LZW TIFF 路径，不再把原图转未压缩 TIFF 后再次编码。
- `CaptureService` 和长截图取帧不再为 ScreenCaptureKit 帧长期持有 `CIContext`，改为把 BGRA 像素复制到独立 `CGImage`；长截图直接复制选区。区域截图先在同步 scope 中裁剪/合成，再进入保存、OCR 等异步动作，避免 Task 等待期间捕获整屏原图。

## 可复现证据

公开生成的 2400×1400 随机图，30 次贴图保存的同进程对照：

| 路径 | 每批操作采样（MiB） | 15 秒闲置（MiB） |
| --- | --- | --- |
| 旧保存路径 | 244.8 / 248.8 / 242.6 | 76.9 / 24.3 / 24.6 |
| 新保存路径 | 24.4 / 24.8 / 23.5 | 23.5 / 23.5 / 23.6 |
| 新复制路径 | 50.9 / 38.9 / 37.7 | 37.7 / 23.7 / 23.7 |

这些是隔离的 Pinned fixture 操作采样，说明旧编码旁路会制造很高的瞬时峰值，不能单独证明完整应用的 200 MiB 会永久驻留。旧路径后两批也回落，故不能把该对照写成 Issue #20 已复现或已结案。

公开 3840×2160 BGRA frame 对照中，20 帧 CoreImage 路径约 135.5 MiB，native pixel copy 约 67.8 MiB；两者在闲置后都回落，说明新取帧路径主要降低峰值和图形缓存压力。sRGB 最大通道差为 0，Display P3 在同一渲染消费者下最大差为 3，属于颜色管理舍入范围；新回归检查通过选区尺寸、alpha、stride、多屏坐标和源 buffer 脱离。

## 当前验证状态

- Release `xcodebuild` 构建通过；仅有既有 Swift deprecated、AppIcon 尺寸和 actor warning。
- 窗口生命周期回归、Pinned 内存回归（33 项）和取帧检查通过。
- 未构建/替换 `/Applications/LibreShot.app`，未执行安装授权流程，未声称新包可交付。
- 新代码还没有在正式安装包上完成用户正常网页、长截图、翻译失败和重启前后验收。

## 下一步

1. 用本轮源码构建独立候选包，按 `docs/operations/install-and-permissions.md` 做新包、权限、截图保存和同包重启验收。
2. 在固定公开页面上分别执行普通截图、长截图、OCR、翻译失败，每项重复 5 次；记录操作峰值和关窗后 1/15/60 秒，比较基线是否逐轮抬升。
3. 若新包空闲仍回到 70–100 MiB，再对剩余 25.5 MiB anonymous allocations 启用 MallocStackLogging/Instruments，定位真实分配栈；不要用私有图形缓存清理或 `malloc_zone_pressure_relief` 作为产品修复。
4. 快速连续截图的 `CaptureService.shared` 仍存在 `currentScale/stream` 并发覆盖风险，应另立回归，不能把本轮取帧优化写成并发竞态已解决。

## 2026-10-10 r4 后续说明

以上数值和“当前验证状态”是 10 月 9 日的历史诊断，不是最终 r4 安装包的实测结果。r4 已构建安装，固定产物为 `dist/LibreShot-1.3.10-32-memory-lifecycle-20261010-r4`；版本仍为 1.3.10 (32)，必须通过具体包身份区分。最终安装包的权限和实际验收状态另见 [r4 包 QA](1.3.10-32-memory-lifecycle-r4-20261010.md)，当前真实 QA 仍待验。

r4 普通截图改为每请求 `CaptureRequestState<CGImage>`、局部 stream/output/scale 和串行生命周期 gate；取消可在 continuation 注册之前缓存，首帧必须原子领取后才复制，等待 `startCapture()` 返回后统一停止。长截图也串行 start/stop 并清理帧状态。请求生命周期确定性回归、帧像素/多屏检查和窗口生命周期检查通过，因此上文第 4 项的旧共享状态风险已有源码修复与测试覆盖；最终 r4 的真实连续取消、普通/长截图交替、多帧完成和同包重启验收仍待完成，不能由这些测试宣称现场问题已解决。

`Physical footprint`、`ps` RSS 和活动监视器“内存”列须分开记录。本轮尚未同 PID、同时间核对活动监视器列；不能把用户看到的 100–122 MB 直接称为 RSS，也不能仅凭较低的 footprint 宣称已达到 20–30 MB 闲置目标。后续应先完成 r4 实际验收和指标对照，再判断剩余分配栈实验。
