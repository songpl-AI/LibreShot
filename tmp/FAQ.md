# 开发常见问题 (FAQ) & 故障排除

本文档记录开发过程中遇到的典型错误、原因分析及解决方案。

## 1. 权限与沙盒 (Sandbox & Permissions)

### Q: 无法弹出保存面板 (NSSavePanel)
**错误信息 (Log):**
```text
Unable to display save panel: your app has the User Selected File Read entitlement but it needs User Selected File Read/Write to display save panels.
```

**原因分析:**
MacOS 沙盒机制要求严格的权限控制。虽然在 Xcode 的 "App Sandbox" -> "File Access" 中开启了 "User Selected Files"，但默认可能被设置为 "Read Only"。
而 `NSSavePanel` 本质上是一个写入操作（用户选择一个位置让 App 写入文件），因此必须拥有 "Read/Write" 权限。

**解决方案:**
1.  **检查 Entitlements 文件**:
    确保 `MyScreenShots.entitlements` 中包含以下键值对：
    ```xml
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    ```
2.  **检查 Build Settings**:
    在 `project.pbxproj` 中，确保 `ENABLE_USER_SELECTED_FILES` 被设置为 `readwrite` (通常在 Xcode UI 中修改即可)。

---

## 2. ScreenCaptureKit & CoreMedia

### Q: 控制台出现 "stream output NOT found. Dropping frame" 错误
**错误信息 (Log):**
```text
[ERROR] _SCStream_RemoteVideoQueueOperationHandlerWithError:1459 stream output NOT found. Dropping frame
```

**原因分析:**
这是一个常见的 ScreenCaptureKit 警告，通常出现在截图流（SCStream）启动初期或停止阶段。
*   **启动时**: 系统可能在 Output Handler 完全绑定前就产生了一帧数据。
*   **停止时**: 当我们调用 `stopCapture()` 时，底层流可能还在尝试发送最后一帧，但我们已经移除了 Output，导致丢帧。
对于"单次截图"场景，这个错误是**良性**的，不影响功能。

### Q: 控制台出现 "Unable to obtain a task name port right" 或 "No factory registered"
**错误信息 (Log):**
```text
Unable to obtain a task name port right for pid 417: (os/kern) failure (0x5)
AddInstanceForFactory: No factory registered for id <CFUUID ...>
```

**原因分析:**
*   **Task Name Port**: 通常与 XPC 通信或沙盒限制有关。在调试模式下，Xcode 尝试注入或监控进程时可能会触发此类系统级日志。只要 App 核心功能（截图、保存）正常，通常可忽略。
*   **Factory Registered**: CoreMedia 或 CoreAudio 内部组件加载日志。由于我们禁用了音频捕获 (`configuration.capturesAudio = false`)，相关音频工厂可能未注册，导致此提示。

**结论:**
这些通常是系统框架层的噪音日志 (Log Noise)，若不影响 App 崩溃或功能失效，可安全忽略。

---

## 3. 窗口与布局 (Window & Layout)

### Q: `makeKeyWindow` 警告 (NSWindow returned NO from -[NSWindow canBecomeKeyWindow])
**错误信息 (Log):**
```text
Warning: -[NSWindow makeKeyWindow] called on <NSWindow: ...> which returned NO from -[NSWindow canBecomeKeyWindow].
```

**原因分析:**
默认情况下，无边框 (`.borderless`) 的 `NSWindow` 无法成为 Key Window（无法接收键盘事件）。
当我们调用 `makeKeyAndOrderFront` 试图激活这个窗口时，系统会检查 `canBecomeKeyWindow` 属性。如果它返回 `NO`（默认值），就会报此警告。

**解决方案:**
子类化 `NSWindow` 并重写 `canBecomeKey` 属性：
```swift
class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}
```

### Q: 布局递归警告 (NSDetectedLayoutRecursion)
**错误信息 (Log):**
```text
It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out.
...
Break on void _NSDetectedLayoutRecursion(void) to debug.
```

**原因分析:**
这通常发生在 SwiftUI 视图被嵌入到 AppKit (`NSHostingView`) 中，并且在布局过程中（Layout Pass）又触发了新的状态更新，导致无限循环或冲突。
→在我们的场景中，可能是全屏 Overlay 窗口初始化时的尺寸计算与 SwiftUI 的 GeometryReader 布局发生了某种竞态。

**结论:**
如果界面显示正常且没有卡死，这通常是一个**良性警告**。SwiftUI 内部布局机制在某些边界条件下（如全屏无边框窗口）可能会触发此类检查。
如果频繁出现或导致性能问题，可以尝试将状态更新移出 `body` 计算过程，或使用 `DispatchQueue.main.async` 延迟更新。

### Q: 选区无法拖动或只能单向缩放
**现象:**
选区完成后无法整体拖动，或只有某一个方向的缩放手柄生效，其它方向无反应。

**原因分析:**
1. 选区拖动与缩放手势被局部视图拦截，导致拖拽事件没有传递到正确的处理逻辑。
2. 手势坐标系不一致（局部坐标与全屏坐标混用），拖拽偏移量计算失真。
3. 选区手柄命中区域过小或命中位置与显示位置不一致，导致看得到拖不到。

**解决方案:**
1. 将选区拖动与手柄缩放统一在全屏手势中处理，并使用统一坐标系。
2. 通过“手柄命中测试”来判定缩放方向，否则在选区内部触发整体移动。
3. 让手柄仅作为视觉提示，避免手柄自身拦截事件。

---

## 4. 多屏幕与坐标系 (Multi-Screen & Coordinates)

### Q: 多屏幕截图错位或空白
**现象:**
在副屏进行区域截图时，保存的图片可能是空白的，或者是主屏的内容，或者选区位置完全偏移。

**原因分析:**
*   **默认行为**: `NSScreen.main` 通常指拥有焦点的屏幕，不一定是鼠标所在的屏幕。
*   **坐标系差异**: 不同屏幕有不同的分辨率（Points）和缩放因子（Scale Factor，如 Retina @2x vs 普通 @1x）。
*   **截图源**: 如果代码中硬编码了截取主屏 (`SCShareableContent.current.displays.first`)，那么在副屏操作时就会截错内容。

**解决方案:**
1.  **识别目标屏幕**: 根据鼠标位置 (`NSEvent.mouseLocation`) 动态判断用户在哪一个 `NSScreen` 上操作。
2.  **传递 Display ID**: 将目标屏幕的 `displayID` 传递给截图服务。
3.  **动态计算缩放**: 在合成 (`composite`) 和裁剪 (`crop`) 时，必须使用**目标屏幕**的尺寸和缩放因子，而不是主屏的。

### Q: 标注位置偏移或过小
**现象:**
绘制的红色方框或画笔轨迹，在保存的图片上变得非常小，且位置偏向左上角。

**原因分析:**
*   **单位不一致**: UI 层的坐标是基于 **Points (逻辑点)** 的，而图片文件是基于 **Pixels (物理像素)** 的。
*   **缺少缩放**: 直接将 Point 坐标绘制到 Pixel 图片上，没有乘以屏幕的 Scale Factor (e.g., 2.0)，导致图形缩小。

**解决方案:**
在 `NSImage` 上绘制标注前，应用缩放变换：
```swift
let scaleX = image.width / screen.frame.width
let scaleY = image.height / screen.frame.height
context.scaleBy(x: scaleX, y: scaleY)
```

### Q: 截图内容空白 (NSImage 坐标系翻转)
**现象:**
保存的图片背景是白色的，或者内容被翻转/消失。

**原因分析:**
`NSImage` 的默认坐标系原点在**左下角**，而 SwiftUI 和 `CGContext` (通常) 使用**左上角**。如果不进行坐标系翻转 (`flipped: true` 或手动 `scale(1, -1)` )，绘制内容可能会跑出画布或垂直颠倒。

**解决方案:**
使用 `lockFocus()` 并手动配置坐标系：
```swift
newImage.lockFocus()
// 1. 绘制底图
image.draw(in: rect) 
// 2. 翻转坐标系以匹配 SwiftUI 标注坐标
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1.0, y: -1.0)
// 3. 绘制标注...
newImage.unlockFocus()
```

---

## 4.1 马赛克功能 (重点问题记录)

### Q: 马赛克预览或导出变成全白
**现象:**
马赛克区域显示为纯白块，无法看到像素块效果。

**原因分析:**
1. 预览或导出阶段的采样坐标系与实际屏幕坐标不一致，导致采样落到无效区域。
2. 预览阶段使用截图源为空或被遮挡的画面（例如截到了遮罩层）。

**解决方案:**
1. 统一坐标转换：明确 SwiftUI 坐标（左上原点）到 CoreGraphics/CIImage 坐标（左下原点）的映射规则。
2. 预览截图使用 ScreenCaptureKit 原始屏幕内容，避免截到遮罩层。

### Q: 马赛克预览效果与导出不一致
**现象:**
预览是像素块，导出不是；或块大小/位置不一致。

**原因分析:**
1. 预览与导出使用了不同的块大小或缩放因子。
2. 预览基于缩放后的截图，导出基于原始像素图，未同步缩放规则。

**解决方案:**
1. 以“点坐标 -> 像素坐标”的缩放因子为统一入口，保持 blockSize 与 pixellate 参数一致。
2. 预览截图做下采样时，同步记录缩放比例并参与采样。

### Q: 马赛克导致内存上升明显
**现象:**
进入编辑或马赛克预览时，内存明显增长。

**原因分析:**
预览阶段持有全分辨率截图与位图缓冲，尤其在高分屏上占用很大。

**解决方案:**
1. 预览位图下采样（限制最大边长），降低内存占用。
2. 在退出或重置时及时释放预览位图缓存。

---

## 4.2 OCR (系统原生 Vision)

### Q: 为什么识别结果为空或很少？
**现象:**
OCR 返回空文本，或只有少量字符。

**原因分析:**
1. 截图内容对比度低或过度压缩，导致文本边缘不清晰。
2. 选区太小或包含遮罩层，实际传入的图像不是最终截图。
3. 识别语言未覆盖实际文字语言。

**解决方案:**
1. OCR 输入使用最终合成的 `CGImage`，避免遮罩层干扰。
2. 对图像做轻量预处理（去噪、提升对比度、灰度化）。
3. 设置 `VNRecognizeTextRequest.recognitionLanguages` 覆盖目标语言。

### Q: 识别顺序混乱，文本行错位？
**现象:**
识别结果顺序不一致，复制出来的文本断行严重。

**原因分析:**
Vision OCR 输出是块级结果，默认不保证阅读顺序。

**解决方案:**
1. 按 `boundingBox` 的 Y 从上到下、X 从左到右排序。
2. 设定行内合并阈值，合并同一行的相邻文本块。

### Q: OCR 速度慢或卡顿？
**现象:**
截图后 OCR 需要明显等待，界面出现卡顿。

**原因分析:**
同步执行 OCR 或在主线程处理大图。

**解决方案:**
1. 将 OCR 放在后台队列执行，完成后回主线程更新 UI。
2. 对大图进行下采样，限制最大边长后再识别。

## 5. 交互体验 (UX)

### Q: 为什么复制/保存成功没有弹窗提示？
**现象:**
复制到剪贴板或保存到文件后没有弹窗提示。

**原因分析:**
成功弹窗会打断连续操作，影响效率与流畅度。

**解决方案:**
成功仅播放提示音，不弹窗；失败仍保留弹窗与错误信息。

---

## 6. 快捷键设置问题

### Q: 无法设置全局快捷键
**症状**: 点击快捷键录制区域后，按下组合键无反应，快捷键无法保存。

**根本原因**:
在 SwiftUI 和 AppKit 混合应用中，键盘焦点管理非常复杂：
1. SwiftUI 的布局系统会干扰 AppKit 视图的焦点管理
2. NSViewRepresentable 中的视图无法可靠地获得键盘焦点
3. overlay 方式显示的视图可能无法接收键盘事件

**解决方案**:
使用 `NSEvent.addLocalMonitorForEvents` 进行应用级别的键盘事件监听，而不是依赖视图焦点。

**实现要点**:
```swift
// ✅ 正确方式：使用 Local Event Monitor
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    // 直接在应用级别捕获键盘事件
    let keyCode = event.keyCode
    let modifiers = event.modifierFlags
    // 处理快捷键录制...
    return nil // 消费事件
}

// ❌ 错误方式：依赖 NSView 焦点
class RecorderView: NSView {
    override func keyDown(with event: NSEvent) {
        // 在 SwiftUI 环境中可能无法可靠触发
    }
}
```

**关键优化**:
1. **立即停止监听**: 录制成功后马上移除事件监听器，避免后续按键触发
2. **验证修饰符**: 必须包含至少一个修饰键（⌘/⌃/⌥/⇧），防止纯字母键被注册
3. **Escape 取消**: 监听 Escape 键并立即停止监听

### Q: 需要多次尝试才能成功设置快捷键
**症状**: 按下快捷键后，需要反复按多次才能保存，或者保存后立即被覆盖。

**原因**:
事件监听器没有在第一次成功录制后立即停止，导致：
- 用户释放按键时触发新的录制（无修饰符 → 注册失败）
- 重复按键时不断重新注册相同快捷键
- 状态更新延迟导致监听器未及时移除

**解决方案**:
在 `onKeyRecorded` 回调中**同步停止监听**：

```swift
keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    // ... 验证逻辑 ...
    
    // 关键：立即停止监听，防止后续按键触发
    DispatchQueue.main.async {
        self.stopMonitoring()  // 先停止
        self.onKeyRecorded?(keyCode, modifiers)  // 再回调
    }
    
    return nil
}
```

**调试日志示例**:
```
# 问题：释放按键时又触发录制
📝 Key event received: keyCode=7, char=X
  ✅ Recording: keyCode=7, modifiers=768    # ⌘⇧X
Hotkey registered: code 7, mods 768
🚩 Flags changed: modifiers=0              # 释放按键
📝 Key event received: keyCode=7, char=x   
  ✅ Recording: keyCode=7, modifiers=0    # ❌ 又触发了！
Failed to register hotkey: -9868          # 无修饰符，注册失败

# 修复后
📝 Key event received: keyCode=7, char=X
  ✅ Recording: keyCode=7, modifiers=768
🛑 Key down monitor removed                # ✅ 立即停止
Hotkey registered: code 7, mods 768
```

### Q: 快捷键设置后无法触发截图
**可能原因**:
1. **快捷键冲突**: 系统或其他应用已占用该快捷键
2. **通知未触发**: 设置保存后未通知 AppDelegate 重新注册
3. **注册失败**: 查看日志确认是否成功注册

**解决方案**:

#### 1. 确认快捷键注册成功
查看日志：
```
Hotkey registered: code X, mods Y        # ✅ 成功
Failed to register hotkey: -9868         # ❌ 失败（通常是冲突）
```

#### 2. 添加通知机制
确保设置变更后 AppDelegate 重新注册：
```swift
// SettingsService.swift
extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
}

func saveShortcut(keyCode: Int, modifiers: Int) -> Bool {
    let success = HotkeyService.shared.registerHotkey(...)
    if success {
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }
    return success
}

// AppDelegate.swift
NotificationCenter.default.addObserver(forName: .hotkeyDidChange, ...) {
    self.reregisterHotkey()  // 重新注册
}
```

---

## 7. 截图流程重复触发

### Q: 已经进入截图后再次按快捷键无法再次触发
**现象**:
进入截图（Overlay 已显示）后，再次按快捷键或菜单无法再次进入截图流程，只能结束当前截图才能继续。

**原因分析**:
1. 每次触发都会创建新的 Overlay 实例，旧实例未释放或仍占用输入焦点。
2. 全局状态未复位，导致重复触发被忽略或直接返回。
3. 捕获流程未做幂等处理，进入截图后第二次触发被误判为非法状态。

**解决方案**:
1. **单实例复用**：全局仅保留一个 Overlay 控制器，重复触发时复用并重置状态。
2. **幂等触发**：当截图流程正在进行时，重复触发执行“重置并重新展示”，保证用户意图可达。
3. **统一退出清理**：完成/取消都必须关闭 Overlay 并释放预览缓存，保证下一次触发不受影响。

**验收标准**:
- 截图进行中再次触发，Overlay 能立刻重置并重新开始框选。
- 无论完成或取消，下一次触发都能正常进入截图。

### 快捷键录制最佳实践

| 方法 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **NSEvent Monitor** ✅ | 应用级捕获<br>不依赖焦点<br>实现简单 | 需手动管理生命周期 | **SwiftUI/AppKit 混合应用**<br>全局快捷键录制 |
| NSPanel + NSView | 独立窗口<br>焦点隔离 | 焦点管理复杂<br>在 SwiftUI 中不可靠 | 纯 AppKit 应用 |
| SwiftUI Overlay | 集成简单 | ❌ 无法获得键盘焦点 | 不适合键盘输入 |

**实现清单**:
- [x] 使用 `NSEvent.addLocalMonitorForEvents` 监听键盘
- [x] 录制成功后**立即停止监听**
- [x] 验证快捷键必须包含修饰符
- [x] 支持 Escape 取消录制
- [x] 使用 `NotificationCenter` 通知快捷键变更
- [x] 在 AppDelegate 中监听通知并重新注册
- [x] 添加详细日志（emoji 前缀）便于调试
- [x] 错误处理：显示注册失败提示

**开发经验总结**:
- ✅ **优先查阅成熟方案**: 参考类似应用（Hammerspoon, Karabiner）的实现
- ✅ **尽早添加日志**: 从一开始就用 emoji 前缀区分不同阶段
- ✅ **快速验证假设**: 遇到焦点问题，应立即尝试 Event Monitor 而不是修修补补
- ✅ **文档化决策**: 记录为什么某种方法不可行，避免重复尝试

---

## 7. 文本绘制与坐标系问题

### Q: 截图生成的图片中文本是倒置/翻转的

**现象:**
在 `OverlayView` 中显示的文本是正常的，但保存后的截图中，文本是垂直翻转（镜像）的。

**原因分析:**
Core Graphics 上下文 (`CGContext`) 在处理 `NSImage` 时通常需要进行坐标系翻转（将原点从左下角移到左上角），以便与屏幕坐标系（SwiftUI/Overlay）对齐。
我们使用了 `context.scaleBy(x: 1.0, y: -1.0)` 来实现翻转。
然而，`NSString.draw(at:)` 或 `NSAttributedString.draw(at:)` 在绘制文本时，如果上下文的 Y 轴是翻转的，文本也会被翻转绘制。

**解决方案:**
在绘制文本前，必须**恢复图形上下文状态 (`restoreGState`)** 到未翻转的状态（即标准的 NSImage 左下角原点坐标系）。
同时，需要手动将标注的 Y 坐标（基于左上角）转换为 NSImage 的 Y 坐标（基于左下角）：
`DrawY = ImageHeight - AnnotationY - TextHeight`

这样既能保证位置正确，又能保证文本不被翻转。

---

## 8. 贴图功能 (Pin)

### Q: 如何关闭或保存贴图？
**操作技巧:**
*   **关闭**: 双击贴图窗口，或右键点击选择"关闭"。
*   **保存**: 右键点击选择"保存..."，支持将当前贴图另存为文件。
*   **复制**: 右键点击选择"复制"，可将图片再次复制到剪贴板。

### Q: 贴图窗口如何移动和调整？
**交互设计:**
*   **移动**: 按住贴图任意位置拖拽即可。
*   **透明度**: 右键菜单中提供了 "透明度: 50%" 等选项，方便对比底层内容。
*   **层级**: 贴图窗口默认处于 `.floating` 层级（始终置顶），不会被其他普通窗口遮挡。

---

## 9. 性能与画质 (Performance & Quality)

### Q: 为什么截图后内存占用会短暂升高 (到 100MB)？
**现象:**
打开 App 约 20MB，截图时升至 40MB，使用 OCR 后飙升至 100MB，随后回落但高于初始值。

**原因分析:**
1.  **物理定律**: 视网膜屏幕截图数据量巨大 (23MB+)。
2.  **Vision 框架**: OCR 模型加载需要约 30-50MB 显存/内存，且为了下次快速响应，系统会缓存模型权重。
3.  **峰值叠加**: "截图数据 + 模型权重 + 推理中间量" 会在瞬间叠加。

**解决方案:**
1.  **即用即弃 (Use-and-Dispose)**: 截图窗口关闭后，立即销毁 `OverlayWindowController`，释放 UI 和预览图内存。
2.  **自动释放池**: 使用 `autoreleasepool` 包裹高频大图转换逻辑，防止峰值期间临时对象堆积。
3.  **接受缓存**: OCR 后的 ~75MB 占用是健康的（包含系统缓存），无需过度优化。

### Q: 为什么截取的圆角图片看起来很糊？
**现象:**
保存的图片清晰度不如屏幕显示，尤其是在圆角边缘处明显模糊。

**原因分析:**
**DPI 丢失**: 在创建绘图上下文 (`CGContext`) 时使用了逻辑尺寸 (Points, e.g. 100x100) 而非物理像素尺寸 (Pixels, e.g. 200x200)。
这导致高清截图被强制下采样 (Downsampling) 到低分辨率画布上。

**解决方案:**
始终基于 `CGImage.width` / `CGImage.height` (物理像素) 创建 Context，并根据比例动态计算圆角半径。

---

## 10. 已知限制与待解决问题 (Known Limitations)

### Q: 无法截取展开的 macOS 菜单 (Menu Bar Items)
**现象:**
当点击 macOS 顶部菜单栏图标展开菜单列表后，尝试通过快捷键唤醒截图功能，菜单列表会立即消失，导致无法截取到展开的菜单内容。

**原因分析:**
1.  **窗口激活机制 (Window Activation)**: macOS 的菜单是一个特殊的窗口类型。当截图 App 的 Overlay 窗口被设置为 Key Window (`makeKeyAndOrderFront`) 以接收键盘/鼠标事件时，系统会自动将焦点从菜单转移到截图窗口，导致菜单因失去焦点而自动关闭。
2.  **事件拦截冲突**: 截图需要全屏遮罩来捕获鼠标选区，这本质上是一个新的窗口层级，与 macOS 菜单的“点击外部自动关闭”机制天然冲突。

**当前状态:**
**[UNRESOLVED]** 尚未找到完美的原生解决方案。
尝试过延迟激活窗口 (`orderFront` without key)，但在开始框选时仍需捕获鼠标事件，最终仍会导致菜单关闭。这是一个系统级的交互限制。建议后续通过“延迟截图”模式（倒计时截图）来解决此类瞬态 UI 的捕获需求。

---

*最后更新：2026-02-08*
