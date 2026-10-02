# 2026-10-02 内存专项验证

## 结论与范围

本轮在重复编辑/复制的生产服务路径复现了明显驻留增长，并缩小到默认未压缩 TIFF 编码路径。最终改为文件编码、映射读取及无损 LZW TIFF。文字图同工况 30 次编辑/复制、每批闲置 60 秒的结果约 52 MiB；复杂像素素材复制 50 次后约 41 MiB，未见本样例继续累加。PNG/TIFF 仍立即提供，不依赖应用继续存活。

这不是完整应用所有场景的 350 MB 问题已解决，也没有达到 OCR 后约 10 MB 的目标。Issue #5 应继续开放。下文严格区分隔离生产代码测量、完整预览空闲采样和用户长截图反馈。

## 方法

- 环境：Apple Silicon，macOS 26.5.2，Xcode 26.5；修改前源码基于 `f719b23`。
- `tests/MemoryStressProfile.swift` 通过 `tests/compile-checks.sh` 优化编译生产服务和窗口代码。每个场景独立进程，使用固定公开图片、独立 UserDefaults、命名剪贴板，未读取或清空用户剪贴板。
- 文字图为 1200×700 逻辑点，Retina 2400×1400 像素。每批执行 10 次编辑/复制或 5 次实际 Vision OCR，每批按 1/5/15/60 秒采样 TASK_VM_INFO physical footprint。诊断拆分模式可缩短到 15 秒；不将两种闲置时间混作同工况对照。
- 每批结束保留最新剪贴板图片和固定素材。窗口模型的图片、标注和内容视图必须清空；这不等于清空系统框架缓存。
- 程序在末批闲置值比首批相同闲置值高 32 MiB 时返回 2 并提示复查。这只是本次大幅增长的调查阈值，不是通用无泄漏证明或产品内存验收目标。
- 少量独立诊断进程同时运行，核心前后对照使用相同服务、图片、次数和采样间隔；没有人为制造内存压力。运行间仍会有分配器和系统缓存波动。

复现完整对照：

```bash
LIBRESHOT_MEMORY_BATCHES=3 bash tests/run-memory-stress-profile.sh editor-copy
LIBRESHOT_MEMORY_BATCHES=3 bash tests/run-memory-stress-profile.sh ocr
```

默认 5 批（50 次编辑/复制、25 次 OCR），每批含 60 秒闲置。定位模式包括 `copy-only`、`editor-only`、`render-only`、`png-only`、`png-copy`、`tiff-only`、`bitmap-tiff-only`、`lzw-tiff-only`。设 `LIBRESHOT_MEMORY_IDLE=15` 可做短周期定位；`LIBRESHOT_MEMORY_FIXTURE=noise` 使用确定性复杂像素素材（不可用于 OCR 的非空文本检查）。

## 复现与定位

| 隔离场景 | 采样间隔 / 总次数 | 首批闲置 | 第二批闲置 | 最后批闲置 |
| --- | --- | ---: | ---: | ---: |
| 修改前编辑/复制 | 每批 60 秒 / 30 次 | 151.3 | 140.4 | 274.6 |
| 修改前只复制 | 每批 15 秒 / 30 次 | 186.3 | 314.9 | 446.6 |
| 只创建并关闭编辑器 | 每批 15 秒 / 30 次 | 44.7 | 44.9 | 44.9 |
| 编辑器渲染，不复制 | 每批 15 秒 / 30 次 | 45.3 | 45.4 | 45.5 |
| 只 PNG 编码 | 每批 15 秒 / 30 次 | 40.9 | 40.9 | 40.9 |
| PNG 写命名剪贴板，不生成 TIFF | 每批 15 秒 / 30 次 | 41.2 | 41.2 | 41.2 |
| NSImage 默认 TIFF，不写剪贴板 | 每批 15 秒 / 30 次 | 173.2 | 259.2 | 394.4 |
| NSBitmap 默认 TIFF，不写剪贴板 | 每批 15 秒 / 30 次 | 173.1 | 301.6 | 430.1 |
| NSBitmap LZW TIFF，不写剪贴板 | 每批 15 秒 / 30 次 | 41.3 | 41.3 | 41.5 |
| 中间方案：仅 LZW，编辑/复制文字图 | 每批 60 秒 / 30 次 | 53.1 | 53.2 | 53.2 |
| 最终方案：文件映射与 LZW，编辑/复制文字图 | 每批 60 秒 / 30 次 | 51.5 | 51.9 | 52.0 |

单位 MiB。最初 50 次短间隔编辑/复制的探索运行，末尾另闲置 60 秒仍为 648.2 MiB；正式前后对照采用表内统一间隔的 30 次样例。第一轮仅改用 LZW 的文字图只复制 50 次、每批闲置 15 秒的五个值为 42.2、42.3、42.3、42.3、41.2 MiB。

修改前 20 次编辑/复制之后的 `vmmap` 快照，footprint 286.2 MiB，其中 `MALLOC_LARGE (empty)` 的 dirty 为 208.5 MiB，活跃 malloc 分配总计约 22 MiB。这支持不能把整个 footprint 都算作仍被应用对象持有的图片。没有启用 MallocStackLogging，不能据此给所有空闲页建立分配栈归属；实际已确认的是默认 TIFF 路径与大幅驻留增长的关联，以及只改变 TIFF 压缩的对照差异。

仅诊断进程尝试 `malloc_zone_pressure_relief` 返回 0、未改善读数；没有把该调用加入生产代码，也没有将“清缓存”作为修复。

## 复杂图片暴露的边界与最终修复

确定性随机 RGB 素材为 2400×1400 像素、1200×700 逻辑点，避免仅用容易压缩的文字图获得假稳定结论。仅更换 LZW 并不足够：30 次复制、每批闲置 15 秒仍为 319.6、572.8、824.8 MiB；复杂图 PNG 编码单独也从约 151.9 到 283.3 MiB。此失败没有被删去，说明需要同时约束 PNG/TIFF 的大块编码输出缓冲。

将 ImageIO 输出写入文件而不是可增长的内存数据，随后映射读取的独立对照：复杂图 30 次复制三批为 53.6、53.6、53.6 MiB；复杂图 PNG 编码单独也趋稳。最终将这一输出方式应用于生产 `pngData` 和 TIFF 写入，复测生产实现的复杂图 50 次复制（每批 15 秒）为 53.7、53.8、40.6、51.8、40.6 MiB。波动不应按每一 MiB 推导收益，但没有旧路径的逐批显著累加。

## 修复与兼容性

`CaptureService` 使用 ImageIO 文件编码与映射 Data。每次在应用临时目录创建唯一文件（权限 0600），编码完成后读取并立即删除路径；映射数据继续由消费者持有，普通复制不会留下图片文件。PNG 像素保持原有标准化流程，TIFF 使用无损 LZW；两个格式仍属于同一个剪贴板图片条目，生成后立即写入。

该方法增加临时磁盘 I/O，没有降低图片分辨率或改成仅 PNG。临时文件创建或编码失败时沿用原来的失败/回退处理；没有对磁盘不足等场景作实机测试。不存在生产 `malloc_zone_pressure_relief` 调用。

1800×1120 公开测试图的默认 TIFF 为 8,067,910 字节，LZW TIFF 为 79,038 字节；ImageIO 读取标签分别为 Compression 1 / 5，方向和 144 dpi 相同。该压缩比只适用于这幅素材，不是所有截图的承诺。

已通过：

- `tests/run-issue4-checks.sh`：PNG/TIFF 像素一致、圆角透明、Retina 逻辑与物理尺寸、写入进程退出后独立读取、长图和编辑导出。
- `tests/run-capture-memory-optimization-checks.sh`：单条 PNG/TIFF、裁剪缓冲释放、单次 PNG 编码、文件与剪贴板一致；新增 sRGB/Display P3 归一化导出像素和 PNG/TIFF 一致性检查。
- `tests/run-toolbar-checks.sh`：自动保存与失败保留剪贴板、快捷键、标注及现有 OCR/翻译回归。

最终代码回归共 169 项通过（119 + 24 + 26）。源码提交 `72ac5d5` 已构建独立预览 `dist/LibreShot-Issue9-Preview-20261002-memory/LibreShot Preview.app`，版本 1.3.1、build 18、arm64/x86_64；Release 构建、沙盒 entitlement、签名校验和架构检查通过。构建保留既有图标尺寸警告。本包未替换正式应用，也未在完整应用中重做上述重复操作压测。

## OCR 与完整应用观测

独立 OCR 进程实际识别 15 次，每 5 次之后闲置 60 秒，分别为 105.1、89.6、105.5 MiB。首末差约 0.34 MiB，没有本样例的逐批持续增长；这仍明显高于其约 7.2 MiB 的服务基线。支持继续把首次框架加载与复制增长分开调查，不能宣称 Vision 内部缓存已全部归因或达到冷启动目标。

对已授权 r2 完整预览 PID 64213 的间歇外部空闲采样保存在 `preview-idle-processes.csv`。这个运行中的预览仍是修改前构建；它不代表修复后完整应用重复业务验收。新包的版本与源码以 BUILD-INFO 为准。没有替换 `/Applications/LibreShot.app`，没有重置权限、下载语言包或自动关闭 GitHub Issue。

原始本机日志在 `dist/memory-special-20261002/`，包括修改前 `editor-copy-settled.log`、中间方案 `editor-copy-fixed-settled.log`、最终方案 `editor-copy-final-settled.log` 和 `copy-only-final-noise-50.log`、各 codec probe、`ocr-settled.log`、heap/vmmap 快照和回归日志；目录不入 Git。测试程序与本文入 Git，可重跑。
