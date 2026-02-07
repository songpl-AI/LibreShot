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

*最后更新：2026-02-07*
