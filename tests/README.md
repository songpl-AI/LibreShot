# 工具栏与截图完成流程回归检查

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
- 完整、精简与自定义顺序工具栏的屏幕边缘位置、换行和提示边界（144 种配置）。
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
