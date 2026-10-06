# 工具栏与截图完成流程回归检查

`bash tests/run-overlay-permission-checks.sh`：用真实遮罩窗口和可控预览失败复现 Issue #7 的“授权弹窗被灰色遮罩盖住”问题，检查失败后的遮罩关闭、错误回传，以及重复触发时过期预览不会重新显示遮罩。

## 原位翻译与紧凑编辑器

- `bash tests/run-visual-checks.sh`：验证宽屏单排与窄窗口均衡换行、长图适宽/全图布局、译文主色、原选区会话及 Retina 导出坐标。
- `bash tests/build-visual-qa.sh`：生成 `/tmp/LibreShot-Visual-QA/LibreShotVisualQA.app`。打开后有原选区翻译与长图编辑两个合成样例，使用生产视图、独立设置域及剪贴板，不需要录屏权限。选区窗口使用生产截图的 `screenSaver` 层级，校正弹窗也需在这一层级下检查。
- 给验收应用设置 `LIBRESHOT_QA_CUSTOM_TOOLBAR=1` 可查看自定义顺序在宽屏和窄窗口中完整展示，并直接打开“颜色与字号”。
- 应用菜单可切换样例或退出；翻译调用系统模型，缺少语言包时不要在无人值守测试中批准下载。导出只写入 `/tmp/LibreShot-Visual-QA`，不会修改系统剪贴板。

验收结果与局限见 [原位翻译与编辑器布局](../docs/qa/visual-workflow.md)。

## Issues #4–#6 开发版

`bash tests/run-toolbar-checks.sh` 还验证原图翻译的坐标、实际 Vision 读回、浅/深背景、分栏、溢出处理、过期会话隔离、语言切换与导出状态；已安装语言包时验证系统批量翻译的区域 ID，未安装则跳过而不下载。`bash tests/run-issue4-checks.sh` 增加工具快捷键、空格动作、双击 Option 手势判定和马赛克位图延迟分配/释放检查。

生产源码的命令行编译列表集中在 `tests/compile-checks.sh`，可传入输出路径和独立检查入口。设置 `LIBRESHOT_OPTIMIZE=1` 可使用优化构建。

二次审查增加：全局/编辑快捷键双向冲突及旧配置迁移；录制窗口关闭、失焦、异窗口输入；CoreText 窄字形裁切；相邻表格行分隔线保留；取消任务传递到 `VNRequest.cancel()`。记录见 [二次审查](../docs/qa/issues-4-6-review.md)。

- `bash tests/run-roadmap-ui.sh`：先运行工具栏回归生成样例，再打开独立的快捷键和原图翻译验收窗口。使用独立设置域和剪贴板；导出仅写入 `/tmp/libreshot-roadmap-qa`，通过应用菜单 Quit 退出。默认实际调用已安装的翻译模型，缺少语言包时不要在无人值守验收中确认下载。
- `bash tests/run-memory-checks.sh`：优化构建，20 次编辑器/复制和 5 次 OCR，分别等待 1/5/15/60 秒记录 physical footprint。约需 2–3 分钟，使用独立设置和剪贴板，不是完整应用内存。
- `bash tests/run-capture-memory-optimization-checks.sh`：用真实屏幕像素尺寸的可追踪图像验证小选区不保留整屏缓冲，比较 sRGB/Display P3 的颜色与透明像素，并检查自动保存及显式“保存并复制”都只编码一次 PNG、磁盘与剪贴板数据一致。只使用命名剪贴板和临时目录。
- `bash tests/profile-idle-app.sh /absolute/path/LibreShot.app`：完整应用启动后 1/5/15/60 秒采样 `vmmap` 与 CPU，应用结束后退出测试进程。运行前须退出已运行的 LibreShot；沿用其设置，不发起截图或修改设置。

原生窗口截图、测试输出和临时文件不能替代 Finder 真实录屏、多显示器、权限授权/撤销、最低系统版本验收。当前结果见 [开发版验收](../docs/qa/issues-4-6-development.md)。

截图内存优化的功能与生命周期回归使用 `tests/run-issue4-checks.sh`：验证 PNG/TIFF 单条目、透明圆角、Retina 尺寸、跨进程及写入进程退出后的剪贴板读回；追踪历史完整帧像素缓冲释放，并对照固定底栏、小幅滚动、sRGB/Display P3 彩色图片的最终像素。内存数值对照见 [内存分析](../docs/qa/memory-analysis.md)。

在装有 Xcode 的 macOS 上，从仓库根目录运行：

```bash
tests/run-toolbar-checks.sh
```

脚本直接编译生产代码和检查程序，无需添加 Xcode 测试目标。使用独立的 UserDefaults 域、临时保存目录和独立剪贴板，不修改应用设置或用户剪贴板。临时文件在退出时清理。

覆盖：

- 原生截图窗口按一次 Esc 即调用取消，文字编辑器获得焦点时也同样生效。
- 普通截图采集配置关闭鼠标合成，覆盖区域截图冻结预览与全屏截图共用的入口，保持物理分辨率。
- 默认配置、隐藏全部可选按钮、完成与取消始终保留。
- 设置重新读取、未知配置值、恢复默认。
- 上移、下移、多行移动及重启后读取顺序；隐藏工具保留位置，完成与取消可移动但不可隐藏。
- 旧配置、重复/未知工具 ID、损坏的顺序配置及新工具追加；恢复默认同时重置显示与顺序。
- 当前截图配置保持不变，下一次截图应用新配置。
- 所有标注工具及选择模式下的八向选区缩放（72 组）、拖动优先级、未提交文字保留、最小尺寸与屏幕边界。
- 自动选中已有标注（8 种工具 × 8 种标注，共 64 组）、点击与拖动区分、离开后返回的拖动、笔画命中、重叠优先级、文字双击编辑。
- 选中矩形/椭圆的内部移动和八向缩放（16 组）、首次回调已移动、绝对位移、最小尺寸、其他标注命中及截图范围控制点优先级。
- 隐藏矩形后回到选择模式，长截图模式不显示长截图启动按钮。
- 完成、保存、另存为、贴图、OCR 都包含尚未提交的文字。
- 完整、精简与自定义顺序工具栏的屏幕边缘位置、均衡换行和提示边界（144 种配置）。
- 名称提示位于屏幕范围内，且不覆盖工具栏按钮。
- 当前 macOS 上所有按钮的系统图标可用。
- 权限错误包含中文操作指引；首次授权成功后继续查询屏幕内容。
- 非权限类系统错误保留原始错误对象、错误域和错误码，不误报成权限拒绝。
- 自动保存开启/关闭、生成可读取 PNG、真实保存失败后剪贴板仍有截图。

可选的原生 SwiftUI 预览（渲染时短暂显示测试窗口）：

```bash
LIBRESHOT_QA_OUTPUT=/tmp/LibreShot-toolbar-qa tests/run-toolbar-checks.sh
```

系统 Vision OCR 和同语言翻译路径会实际运行；跨语言翻译只在语言模型已安装时执行，否则输出 `NOT RUN`。测试不会为此自动下载模型。

翻译还覆盖按需启动、取消和失败后重试、相同语言配置更新、过期结果隔离及关闭 OCR 窗口时释放视图。系统下载弹窗的独立 UI 入口为 `TranslationUITestApp.swift`，验收步骤见 [1.1.1 翻译验收](../docs/qa/1.1.1.md)。

选区控制点原生渲染检查：

```bash
LIBRESHOT_CHECK_SELECTION=/tmp/LibreShot-selection-qa tests/run-toolbar-checks.sh
```

它对比框选结束、矩形工具启用的状态与选择模式，确认不按 Esc 也显示控制点。

可选性能测量：

```bash
LIBRESHOT_CHECK_PERFORMANCE=1 tests/run-toolbar-checks.sh
```

只测配置体积、可见性过滤和布局计算，不代表进程内存峰值或相对旧版的净增开销。

长截图人工测试页面：

```bash
python3 -m http.server 8768 --bind 127.0.0.1 --directory tests/fixtures
```

打开 `http://127.0.0.1:8768/capture-check.html`，框选内容区域，小幅向下滚动并留出重叠内容，完成后检查编号连续、文字无重复接缝，再保存 PNG 检查尺寸。

实际截图验收使用正常签名构建，不传 `CODE_SIGNING_ALLOWED=NO`，以免改变应用身份、干扰已有录屏授权。自动检查不能替代屏幕录制、滚动拼接和跨 macOS 版本测试。当前结果和未验证项目见 [1.1.0 验收记录](../docs/qa/1.1.0.md)。

标注选择原生 UI 入口为 `AnnotationSelectionUITestApp.swift`：将回归脚本中的生产 Swift 源文件与此入口一起编译为独立 App（不包含 `ToolbarRegressionChecks.swift`）。它使用生产 `OverlayView`、合成矩形和文字及独立设置域，无需录屏权限。操作步骤和实测结果见 [1.2.0 标注验收](../docs/qa/1.2.0.md)。


## Issue #4 回归

```bash
bash tests/run-issue4-checks.sh
```

覆盖圆角透明度、Retina 尺寸、重复列表与固定栏匹配、奇数/小幅滚动、固定底栏、逐像素接缝、反向/无重叠/歧义帧拒绝、连续滚动、失败重试和未完整拼接时阻止静默出图、保存快捷键提交文字、回车的文字编辑边界、复制译文、长图底部标注导出。

可选原生渲染：

```bash
LIBRESHOT_ISSUE4_QA=/tmp/LibreShot-issue4-qa bash tests/run-issue4-checks.sh
```

`Issue4UITestApp.swift` 是独立交互验收入口。使用 `run-issue4-checks.sh` 中的生产源文件，将 `Issue4RegressionChecks.swift` 替换为该入口编译运行。它显示生产长图编辑器，使用合成的 60 行图片与独立设置域；保存、另存为、完成只将 PNG 写入 `/tmp/LibreShot-Issue4-UI`，不改用户剪贴板。按 Esc 退出。步骤及实测结果见 [Issue #4 验收](../docs/qa/issue-4.md)。

可选传入本机图文图片，检查连续滚动分帧重建是否与原图逐像素一致：

```bash
LIBRESHOT_CAPTURE_FIXTURE=/absolute/path/image.png bash tests/run-issue4-checks.sh
```

Issue #4 补充覆盖多种截图宽高、小幅位移以及 20/32/64 px 固定底栏。仅横向采样，保留原始像素行以防重复周期误判。

## Issue #9 编辑体验回归

`bash tests/run-issue9-checks.sh` 使用生产视图和会话模型，覆盖首次授权请求返回后的状态重查、圆角/直角预览像素、无效点击和抖动、拖动起点、完成后选中、保留绘图工具、指定删除与撤销、箭头端点及零长度保护、光标方向、文字缩放，以及关闭后控制器仍被持有时的图片释放。仅使用独立设置域，不修改录屏权限或系统剪贴板。

设置 `LIBRESHOT_ISSUE9_QA=/tmp/libreshot-issue9-qa` 可输出原生工具栏设置和标注控制点截图。测试会短暂显示合成窗口。权限注入检查不能替代首次安装/升级的系统授权验收；独立内存样例不能代表完整应用的 350 MB 场景。

### OCR 辅助进程

`bash tests/run-ocr-worker-checks.sh` 对照真实 Vision 与生产辅助进程，检查中英文、原始文字框、P3/透明像素、缺失组件、异常退出、响应校验、超时、执行中/排队取消、串行执行和父进程退出清理。

`bash tests/run-ocr-sandbox-isolation-profile.sh production` 在签名沙盒应用中调用生产 OCR 接口，连续识别 5 次并空闲 15 秒，保留增量预算 32 MiB。该预算是诊断门槛，不是 10 MiB 的产品承诺。原始 `worker-parent` 模式保留为 PNG 隔离原型对照；`in-process` 仍用于重现旧识别路径的高驻留。

## 1.3.5 默认工具与序号编辑

`bash tests/run-number-tool-checks.sh` 使用生产设置、标注模型、窗口与导出代码，覆盖默认工具持久化和回退、普通截图与图片编辑入口一致、双击改号、数字快捷键隔离、无效输入阻止导出、删除与撤销后的计数、中心缩放及后续大小/颜色继承，并读取实际导出像素。使用独立设置域。

本次新增检查 7 组、Issue #9 回归 92 项、工具栏回归 26 组通过。程序化检查与已安装发行包的真实截图验收分别记录，见 [实现记录](../docs/qa/default-tool-number-editing-20261005.md) 和 [build 24 安装验收](../docs/qa/1.3.5-24-package-20261005.md)。

## 马赛克与模糊共享渲染

`bash tests/run-effect-checks.sh` 检查连续拖动时松手前多次刷新、马赛克/模糊涂抹与框选四种组合的选中/移动/撤销及最终预览与导出一致性、真实效果预览/导出、块平均与网格稳定、笔刷宽度/半径、重叠、Retina 与裁剪偏移、透明度、长图局部输出、参数撤销以及异步渲染关闭隔离。使用独立设置域，样例 PNG 输出至 `/tmp/libreshot-effects-qa`。见 [优化与验证记录](../docs/qa/mosaic-blur-quality-20261005.md)。

## Issue #16 原位编辑

`bash tests/run-inline-editing-checks.sh` 使用生产 TextKit 排版、NSTextView 和成图接口，检查文字显示/编辑的字号、字重、中文回退字体、单行/多行字形坐标、导出基线，以及序号编辑圆圈中心、扩展、颜色、取消/提交/撤销。样例输出至 `/tmp/libreshot-inline-qa`，使用独立设置域。实现与验证边界见 [Issue #16 验证记录](../docs/qa/inline-editing-issue16-20261006.md)。
