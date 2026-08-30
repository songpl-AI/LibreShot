# Issue #1 许愿功能实现方案

> 来源：https://github.com/songpl-AI/LibreShot/issues/1
> 作者：dingyanshan（2026-08-18）
> 状态：本方案已与维护者逐条对齐（grilling 设计树），覆盖 1 个 bug + 4 个许愿功能。

## 1. 范围总览

| # | 类型 | 内容 | 结论 |
|---|---|---|---|
| — | Bug | 文字标注只能出现灰色框，无法输入 | 修（方案 A） |
| 1 | 许愿 | 默认选中矩形框标注 | 采纳（默认矩形 + 选择模式 + Esc 分层） |
| 2 | 许愿 | 序号标注（1、2、3…） | 采纳（新增 `AnnotationType.number`，描边圆 + 同色数字，字号 16） |
| 3 | 许愿 | OCR + 系统翻译联动 | 采纳（OCR 结果窗口内加翻译按钮，`Translation` 框架离线，中/英/日/韩，默认中文） |
| 4 | 许愿 | 自动保存、去掉保存按钮 | 采纳为「设置开关」：默认开启自动保存，保留「另存为」入口，不彻底移除保存按钮 |

**明确不在本次范围**：已有文字标注的「内容编辑」（连带 bug 2，涉及编辑态交互，列为后续独立项）。

## 2. 关键源码路径（已核实）

```
LibreShot/Editor/Annotation.swift                    # Annotation 模型 + AnnotationType 枚举
LibreShot/Editor/EditorToolbarView.swift             # 标注工具栏
LibreShot/Features/Overlay/OverlayView.swift         # 遮罩层视图（Canvas 绘制 + 文字输入 + DragGesture）
LibreShot/Features/Overlay/OverlayViewModel.swift    # 遮罩层状态机（selectedTool / 文字输入 / hitTest）
LibreShot/Features/Overlay/OverlayWindowController.swift  # 遮罩窗口 + Esc/Enter 键盘
LibreShot/LibreShot/CaptureService.swift             # 截图核心 + 保存（saveImageWithFallback / pngData）
LibreShot/LibreShot/CaptureService+Annotation.swift  # 标注合成到最终图片（compositeCropped）
LibreShot/LibreShot/Core/Storage/SettingsService.swift   # 设置持久化
LibreShot/LibreShot/Core/OCR/OCRService.swift        # Vision OCR
LibreShot/LibreShot/Core/OCR/OCRResultWindowController.swift # OCR 结果窗口（翻译加在这里）
LibreShot/LibreShot/Core/OCR/TranslationService.swift # 新增：Translation 框架封装
LibreShot/LibreShot/Features/Settings/SettingsView.swift  # 设置面板（加自动保存开关）
LibreShot/LibreShot/LibreShotApp.swift               # 应用入口（保存/OCR/长截图分派）
LibreShot/Core/PinnedImageWindowController.swift     # 贴图/长截图预览窗口（另存为按钮）
```

## 3. 已拍板的设计决策

| 决策点 | 结论 |
|---|---|
| 交付形式 | 先出实现方案，确认后再写码 |
| 文字输入修复 | 保留 SwiftUI `TextField`，修焦点 + 视觉提示，统一字号 |
| 默认矩形 | 进入编辑态默认选中 `.rectangle`，新增「选择/移动」工具按钮 + Esc 分层 |
| 序号标注 | 新 `AnnotationType.number`，按创建顺序自动递增，描边圆 + 同色数字，字号 16 |
| 翻译位置 | OCR 结果窗口内，目标语言下拉（中/英/日/韩，默认中文） |
| 翻译语言包缺失 | 检测 `.notInstalled`，弹提示引导下载，不静默失败 |
| 自动保存 | 设置开关默认开；三个入口（区域/全屏/长截图）统一遵循；重名加后缀 |
| 另存为 | 区域工具栏 + 长截图预览窗口保留「另存为」手动入口 |

## 4. 分功能实现方案

### 4.1 Bug：文字标注无法输入

**根因**（`OverlayView.swift` + `OverlayViewModel.swift`）
1. 父级 `DragGesture(minimumDistance: 0)` 绑定在整个 ZStack 上（`OverlayView.swift:127`），`minimumDistance: 0` 使鼠标按下即触发 `.onChanged`，即使 `isEditingText` 分支提前 `return`，手势仍消费了点击事件，底层 `NSTextField` 拿不到 first responder。
2. `@FocusState` + `.onAppear` 立即设焦（`OverlayView.swift:110-114`）在窗口尚未成为 key 时不可靠。
3. `.textFieldStyle(.plain)` 无边框、placeholder 不可见，用户看到的是「深灰框」而非「输入框」，无从下手。

**改动**
- `OverlayView.swift` 文字输入块（约 97-118 行）：
  - `.textFieldStyle(.plain)` → `.textFieldStyle(.roundedBorder)`，并保留深色/浅色可辨的 placeholder；给输入框加明显的焦点边框（选中态描边高亮）。
  - 焦点改为「延迟设焦」：`.onAppear` 中用 `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` 设焦，等待窗口 `makeKeyAndOrderFront` 完成；并补 `.onTapGesture { isTextFieldFocused = true }` 兜底。
- `OverlayViewModel.swift`：
  - 统一字号：`Annotation.fontSize` 默认值与输入阶段一致（统一为 24，或抽成常量 `TextAnnotation.fontSize = 24`）。
  - **连带 bug 1**：新增 `func selectTool(_ tool: AnnotationType?)`，内部在切换到非 `.text` 工具时调用 `cancelTextInput()`；工具栏改调此方法。

**涉及文件**：`OverlayView.swift`、`OverlayViewModel.swift`、`EditorToolbarView.swift`、`Annotation.swift`

### 4.2 默认矩形框 + 选择模式

**改动**
- `OverlayViewModel.endSelection()`：进入 `.editing` 时设置 `selectedTool = .rectangle`（`reset()` 保持 `nil`）。
- `EditorToolbarView.swift`：工具栏最前新增「选择/移动」按钮（`cursorarrow` 图标），点击调 `viewModel.selectTool(nil)`，在 `selectedTool == nil` 时显示选中态。
- Esc 分层（`OverlayWindowController.show()` 中 `overlayWindow.onEscapeKey` 接线处）：
  ```swift
  overlayWindow.onEscapeKey = { [weak self] in
      guard let self else { return }
      if self.viewModel.isEditingText { self.viewModel.cancelTextInput() }
      else if self.viewModel.selectedTool != nil { self.viewModel.selectTool(nil) }
      else { cancelAction() }  // 已是选择模式 → 取消截图（保持原行为）
  }
  ```

**涉及文件**：`OverlayViewModel.swift`、`EditorToolbarView.swift`、`OverlayWindowController.swift`

### 4.3 序号标注（新增 `AnnotationType.number`）

**模型**（`Annotation.swift`）
- 枚举加 `case number`，`iconName = "number.circle"`。
- 序号内容复用 `Annotation.text` 存数字字符串（如 `"1"`），不新增字段；`fontSize = 16`，`startPoint` 为圆心。

**状态机**（`OverlayViewModel.swift`）
- 新增 `private var nextNumber = 1`，在 `reset()` 中重置为 1。
- 新增 `func placeNumber(at point: CGPoint)`：`guard selectionRect.contains(point)`，创建 `Annotation(type: .number, color: selectedColor)`，`startPoint = point`、`text = String(nextNumber)`、`fontSize = 16`，`nextNumber += 1`，追加到 `annotations`。
- `isPoint` 加 `.number` 分支（按圆半径 `fontSize/2 + 4` 判命中）。
- `AnnotationType` 每处 `switch` 都需补 `.number`（编译器会提示：`annotationIntersectsCrop`、`isPoint`、`drawAnnotation`、`drawVectorAnnotations`、`drawTextAnnotations`、`moveSelectedAnnotation` 的 points 分支等）。

**渲染（两处都要改）**
- `OverlayView.drawAnnotation`（实时预览 Canvas）：画一个描边圆 + 居中的数字文本。
- `CaptureService+Annotation.swift`：
  - `drawVectorAnnotations` 加 `.number`：`path.addEllipse` 以 `startPoint` 为圆心、半径 `fontSize/2 + 4` 描边。
  - `drawTextAnnotations` 扩展为处理 `.text` 与 `.number`，`.number` 的文本按圆中心对齐绘制。
  - `annotationIntersectsCrop` 加 `.number`（圆包围盒）。

**交互**（`OverlayView.swift` 的 `.onEnded`）
- 增加 `else if viewModel.selectedTool == .number` 分支：判定为点击（位移 < 5px）时调 `placeNumber(at:)`。

**涉及文件**：`Annotation.swift`、`OverlayViewModel.swift`、`OverlayView.swift`、`CaptureService+Annotation.swift`

### 4.4 OCR + 系统翻译

**新增 `TranslationService.swift`**（`LibreShot/LibreShot/Core/OCR/`）
- 封装 macOS `Translation` 框架（macOS 13+，离线）。
- `func translate(_ text: String, to language: Locale.Language) async throws -> String`
- 处理 `LanguageAvailability.status`：`.notInstalled` 时抛特定错误，由 UI 弹提示引导下载。

**`OCRResultWindowController.swift`（`OCRResultView`）**
- 新增 `@State targetLanguage`（默认 `.init(identifier: "zh-Hans")`）、`@State translatedText`、`@State isTranslating`。
- 顶部 HStack 增加：目标语言 `Picker`（简体中文/English/日本語/한국어）+「翻译」按钮。
- 原文 `TextEditor` 下方增加 `Divider` + 译文 `TextEditor`（只读）+「复制译文」按钮。
- 翻译失败/语言包未安装时弹提示。

**涉及文件**：新增 `TranslationService.swift`；改 `OCRResultWindowController.swift`

### 4.5 自动保存

**`SettingsService.swift`**
- 新增 `@Published var autoSaveEnabled: Bool`（默认 `true`），UserDefaults 持久化 `"autoSaveEnabled"`。

**`CaptureService.swift`**
- 新增 `func saveImageDirectly(_ image: NSImage) async throws -> URL`：
  - 目录：`SettingsService.shared.saveDirectory`（已有的「保存位置」bookmark，若未设置回退 `~/Pictures`）。
  - 文件名：`Screenshot <日期 时间>.png`；重名追加 ` (2)`、` (3)`…
  - 复用 `pngData(from:)` 写盘；走 `withSaveDirectory` 处理安全作用域。

**`LibreShotApp.swift`**（三处入口统一分流）
- `captureFullScreen()`：`autoSaveEnabled ? saveImageDirectly : saveImageWithFallback`。
- `performAreaCapture()` `.save` 分支：同上。
- `handleLongCaptureResult()` 的 `onSaveAction`：同上。

**「另存为」入口（保留手动指定位置）**
- `CaptureAction` 加 `case saveAs`；`OverlayViewModel` 加 `confirmSaveAs()`；`EditorToolbarView` 加「另存为」按钮（`square.and.arrow.down.on.square`），始终走 `saveImageWithFallback`。
- `PinnedImageWindowController`（`.longCapturePreview` 模式）加「另存为」按钮，`onSaveAction` 同样分流。

**设置面板**（`SettingsView.swift` 的 `GeneralSettingsView`）
- 「存储」GroupBox 内加 `Toggle("截图后自动保存", isOn: $settings.autoSaveEnabled)`。

**涉及文件**：`SettingsService.swift`、`CaptureService.swift`、`LibreShotApp.swift`、`OverlayViewModel.swift`、`EditorToolbarView.swift`、`PinnedImageWindowController.swift`、`SettingsView.swift`

## 5. 我在此方案中替你做的 3 个细化决定（请确认）

1. **Esc 分层**：你已经选了「Esc 切回选择模式」，但现有 Esc 是「取消截图」。我按分层实现：编辑态下 Esc 先退工具→再退文字输入→无工具时 Esc 才取消截图。这样保留截图工具的取消习惯。
2. **自动保存目录**：你没有硬性指定目录，且项目里已有一个目前**未被 `saveImageWithFallback` 使用的**「保存位置」设置（`SettingsService.saveDirectory`）。我让自动保存复用该设置，未设置时才回退 `~/Pictures`——避免再引入一个死设置。
3. **序号存哪**：序号数字复用 `Annotation.text` 字段（值为 `"1"` 等），不新增字段，减少模型和合成链路的改动面。

## 6. 建议改动顺序（里程碑）

1. **M1（bug 修复）**：文字输入 + 字号统一 + 连带 bug 1（工具切换取消文字输入）。
2. **M2（默认矩形）**：默认 `.rectangle` + 选择模式按钮 + Esc 分层。
3. **M3（序号标注）**：模型 + 状态机 + 两处渲染。
4. **M4（自动保存）**：设置 + `saveImageDirectly` + 三入口分流 + 另存为。
5. **M5（翻译）**：`TranslationService` + OCR 结果窗口 UI。

M1/M2/M4 相互独立、可并行；M3 依赖 M2 的选择模式；M5 独立。

## 7. 后续独立项（本次不纳入）

- 已有文字标注的内容编辑（连带 bug 2）。
- 文字标注的 hitTest 精度（中英文混排宽度估算）。
- 自动保存成功后的通知/toast（可选，轻量）。
