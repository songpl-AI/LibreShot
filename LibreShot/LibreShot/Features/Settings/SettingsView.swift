import SwiftUI
import ServiceManagement
import CoreGraphics
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = SettingsService.shared
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
                .tag(0)
            
            ShortcutSettingsView(settings: settings)
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }
                .tag(1)
            
            ToolbarSettingsView(settings: settings)
                .tabItem {
                    Label("工具栏", systemImage: "slider.horizontal.3")
                }
                .tag(2)

            AboutSettingsView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(3)
        }
        .frame(width: 560, height: 430)
        .padding()
    }
}

struct ToolbarSettingsView: View {
    @ObservedObject var settings: SettingsService
    @State private var shortcutRestoreError: String?
    @State private var draggedToolbarItem: ToolbarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自定义截图工具栏")
                .font(.headline)
            Text("从左到右就是截图工具栏的顺序。左右拖动排序，在每张卡片上勾选和设置快捷键。")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("新用户默认按 ⌘P 贴图；已有快捷键配置保留，可在“贴图到屏幕”一行设置。")
                .font(.caption).foregroundColor(.secondary)

            Picker("浮动工具栏位置", selection: $settings.toolbarAlignment) {
                ForEach(ToolbarAlignment.allCases, id: \.self) { alignment in
                    Text(alignment.title).tag(alignment)
                }
            }
            Picker("截图后的默认工具", selection: Binding(
                get: { settings.defaultEditorTool },
                set: { settings.setDefaultEditorTool($0) }
            )) {
                Text(ToolbarItem.select.title).tag(ToolbarItem.select)
                ForEach(settings.toolbarConfiguration.visibleItems.filter { $0.annotationType != nil }) { item in
                    Text(item.title).tag(item)
                }
            }
            Text("每次新截图使用此工具；隐藏默认工具时回到选择/移动。")
                .font(.caption).foregroundColor(.secondary)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(settings.toolbarConfiguration.orderedItems) { item in
                        toolbarCard(item)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 140)

            Text("从下一次截图开始生效。按 Esc 直接取消截图。\n再次点击当前工具可切回选择模式；拖动选区边框移动截图。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let shortcutRestoreError {
                Text(shortcutRestoreError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text("已显示 \(settings.toolbarConfiguration.visibleItems.count) 个按钮")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("恢复快捷键") {
                    settings.restoreDefaultEditorShortcuts()
                    shortcutRestoreError = settings.editorShortcuts.count == EditorShortcut.defaults.count ? nil : "与全局截图冲突的默认快捷键未恢复，请逐行设置。"
                }
                    .help("恢复编辑快捷键；与全局快捷键冲突的项需另行设置")
                Button("恢复默认") { settings.restoreDefaultToolbar() }
                    .help("恢复全部工具的显示和默认顺序")
            }
        }
        .padding()
    }

    private func toolbarCard(_ item: ToolbarItem) -> some View {
        let visible = settings.toolbarConfiguration.isVisible(item)
        return VStack(spacing: 5) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Spacer()
                Toggle(isOn: Binding(
                    get: { visible },
                    set: { settings.setToolbarItem(item, visible: $0) }
                )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.isRequired)
                .help(item.isRequired ? "始终显示，确保可以完成或取消截图" : "显示\(item.title)")
            }
            Group {
                if item == .style {
                    ToolbarColorIcon().frame(width: 16, height: 16)
                } else if item == .mosaic || item == .blur {
                    EffectToolIcon(tool: item).frame(width: 16, height: 16)
                } else {
                    Image(systemName: item.iconName).font(.system(size: 15))
                }
            }
            .frame(height: 18)
            Text(item.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if item == .cancel {
                Text("Esc")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 88, height: 22)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            } else {
                ToolbarShortcutRecorder(settings: settings, item: item, recordingWidth: 88)
            }
            HStack(spacing: 0) {
                Button { move(item, towardsStart: true) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 18)
                }
                .disabled(item == settings.toolbarConfiguration.orderedItems.first)
                .accessibilityLabel("左移\(item.title)")
                .help("左移\(item.title)")
                Divider().frame(height: 12)
                Button { move(item, towardsStart: false) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 18)
                }
                .disabled(item == settings.toolbarConfiguration.orderedItems.last)
                .accessibilityLabel("右移\(item.title)")
                .help("右移\(item.title)")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        }
        .padding(6)
        .frame(width: 104)
        .opacity(visible ? 1 : 0.45)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.18)))
        .onDrag {
            draggedToolbarItem = item
            return NSItemProvider(object: item.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: ToolbarCardDropDelegate(target: item, settings: settings, dragged: $draggedToolbarItem))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("左移")) { move(item, towardsStart: true) }
        .accessibilityAction(named: Text("右移")) { move(item, towardsStart: false) }
    }

    private func move(_ item: ToolbarItem, towardsStart: Bool) {
        guard let index = settings.toolbarConfiguration.orderedItems.firstIndex(of: item) else { return }
        settings.moveToolbarItems(fromOffsets: IndexSet(integer: index), toOffset: towardsStart ? index - 1 : index + 2)
    }
}

private struct ToolbarCardDropDelegate: DropDelegate {
    let target: ToolbarItem
    let settings: SettingsService
    @Binding var dragged: ToolbarItem?

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let from = settings.toolbarConfiguration.orderedItems.firstIndex(of: dragged),
              let to = settings.toolbarConfiguration.orderedItems.firstIndex(of: target) else { return }
        settings.moveToolbarItems(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

// MARK: - Helper Components

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content
    
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            content
        }
        .padding(.vertical, 4)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // 1. Launch at Login
                        SettingsRow("启动:") {
                            Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
                                .onChange(of: settings.launchAtLogin) { newValue in
                                    toggleLaunchAtLogin(newValue)
                                }
                        }

                        Divider()

                        SettingsRow("菜单栏左键:") {
                            Picker("菜单栏左键", selection: $settings.menuBarLeftClickAction) {
                                ForEach(MenuBarLeftClickAction.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                        }
                        Text("右键始终显示截图菜单。")
                            .font(.caption).foregroundStyle(.secondary).padding(.leading, 88)
                        Divider()
                        SettingsRow("框选辅助:") {
                            Toggle("显示十字辅助线", isOn: $settings.showSelectionGuides)
                        }
                        Divider()

                        SettingsRow("截图音效:") {
                            Toggle("完成截图时播放音效", isOn: $settings.playSound)
                        }
                        Divider()

                        SettingsRow("长截图:") {
                            Toggle("完成后进入标注编辑", isOn: $settings.editLongCaptureAfterFinish)
                        }
                        Divider()

                        // 2. Corner Radius
                        SettingsRow("截图样式:") {
                            Picker("", selection: $settings.useRoundedCorners) {
                                Text("圆角").tag(true)
                                Text("直角").tag(false)
                            }
                            .pickerStyle(.radioGroup)
                            .horizontalRadioGroupLayout()
                            .help("圆角输出为透明 PNG；在白色背景上查看白色截图时可能不明显。")
                        }
                    }
                    .padding(8)
                } label: {
                    Text("基本设置")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // 3. Save Location
                        HStack(alignment: .top) {
                            Text("保存位置:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                    Text(settings.saveDirectory?.path ?? "图片 (默认)")
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundColor(settings.saveDirectory == nil ? .secondary : .primary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )

                                Button("更改保存位置...") {
                                    selectFolder()
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(8)

                        Divider()

                        SettingsRow("自动保存:") {
                            Toggle("完成截图时自动保存", isOn: $settings.autoSaveEnabled)
                                .help("开启后，双击、Enter 或完成按钮复制并保存到指定目录；关闭后仅复制。手动保存始终写入指定目录，另存为可选择位置。")
                        }
                        .padding(8)
                    }
                } label: {
                    Text("存储")
                        .font(.headline)
                }

            }
            .padding()
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                settings.saveSaveDirectory(url)
            }
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        } else {
            print("Launch at login requires macOS 13+")
        }
    }
}

// MARK: - Shortcut Settings

struct ShortcutSettingsView: View {
    @ObservedObject var settings: SettingsService
    @State private var registerError: Bool = false
    @State private var optionPermissionMissing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷键")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("自定义全局快捷键，随时随地唤起截图。")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                    .opacity(0.8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            if registerError || settings.hotkeyRegistrationError != nil {
                Label((registerError ? settings.shortcutError : nil) ?? settings.hotkeyRegistrationError ?? "快捷键注册失败，可能已被其他应用占用", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Selection Capture
                    ShortcutRow(
                        title: "区域截图",
                        description: "选择屏幕区域进行截图、标注或贴图。",
                        keyCode: $settings.shortcutKey,
                        modifiers: $settings.shortcutModifiers,
                        onSave: { k, m in saveShortcut(keyCode: k, modifiers: m) },
                        onClear: { saveShortcut(keyCode: -1, modifiers: 0) }
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Full Screen Capture
                    ShortcutRow(
                        title: "全屏截图",
                        description: "捕捉鼠标所在屏幕的全屏内容并进入标注编辑，确认后复制或保存。",
                        keyCode: $settings.fullScreenShortcutKey,
                        modifiers: $settings.fullScreenShortcutModifiers,
                        onSave: { k, m in saveFullScreenShortcut(keyCode: k, modifiers: m) },
                        onClear: { saveFullScreenShortcut(keyCode: -1, modifiers: 0) }
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    ShortcutRow(
                        title: "长截图",
                        description: "框选滚动区域，完成后进入标注或预览。",
                        keyCode: $settings.longScreenshotShortcutKey,
                        modifiers: $settings.longScreenshotShortcutModifiers,
                        onSave: { k, m in saveLongScreenshotShortcut(keyCode: k, modifiers: m) },
                        onClear: { saveLongScreenshotShortcut(keyCode: -1, modifiers: 0) }
                    )

                    Toggle("双击 Option 启动区域截图", isOn: $settings.doubleOptionEnabled)
                        .onChange(of: settings.doubleOptionEnabled) { enabled in
                            let active = HotkeyService.shared.enableDoubleOption(enabled, requestPermission: enabled)
                            optionPermissionMissing = enabled && !active
                        }
                    if optionPermissionMissing || (settings.doubleOptionEnabled && !CGPreflightListenEventAccess()) {
                        Text("需要在系统设置的“隐私与安全性 → 输入监控”中允许 LibreShot，授权后重新启动应用。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Toggle("双击选区空白处完成截图", isOn: $settings.doubleClickCompletesCapture)
                    Text("适用于所有标注工具，遵循自动保存设置；双击已有文字或序号仍可编辑，编辑输入框及标注控制点不会触发完成。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("编辑时空格", selection: $settings.editorSpaceAction) {
                        ForEach(EditorSpaceAction.allCases, id: \.self) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    Text("标注工具和保存等编辑快捷键，可在“工具栏”页按排序逐行设置。选中标注后按 Delete 删除，⌘Z 撤销。")
                        .font(.caption).foregroundStyle(.secondary)

                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func saveShortcut(keyCode: Int, modifiers: Int) {
        if keyCode != -1 {
            let success = settings.saveShortcut(keyCode: keyCode, modifiers: modifiers)
            registerError = !success
            return
        }
        registerError = false
        _ = settings.saveShortcut(keyCode: -1, modifiers: 0)
    }
    
    private func saveFullScreenShortcut(keyCode: Int, modifiers: Int) {
        if keyCode != -1 {
            let success = settings.saveFullScreenShortcut(keyCode: keyCode, modifiers: modifiers)
            registerError = !success
            return
        }
        registerError = false
        _ = settings.saveFullScreenShortcut(keyCode: -1, modifiers: 0)
    }
    
    private func saveLongScreenshotShortcut(keyCode: Int, modifiers: Int) {
        if keyCode != -1 {
            let success = settings.saveLongScreenshotShortcut(keyCode: keyCode, modifiers: modifiers)
            registerError = !success
            return
        }
        registerError = false
        _ = settings.saveLongScreenshotShortcut(keyCode: -1, modifiers: 0)
    }
}

struct ShortcutRow: View {
    let title: String
    let description: String
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    let onSave: (Int, Int) -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            ShortcutRecorder(
                keyCode: $keyCode,
                modifiers: $modifiers,
                onShortcutRecorded: onSave,
                onClear: onClear
            )
            .frame(width: 140)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "scissors")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
                .shadow(radius: 4)
            
            VStack(spacing: 6) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "LibreShot")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2")")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                if Bundle.main.object(forInfoDictionaryKey: "LibreShotBuildChannel") as? String == "local-preview" {
                    Text("本地试用版 · 未公证")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Link("检查更新…", destination: URL(string: "https://github.com/songpl-AI/LibreShot/releases")!)
                .help("打开 GitHub 发布页面，查看并下载最新版本")

            Text("© 2026 Allen. All rights reserved.")
                .font(.footnote)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.bottom)
        }
        .padding()
    }
}

private struct ToolbarShortcutRecorder: View {
    @ObservedObject var settings: SettingsService
    let item: ToolbarItem
    var recordingWidth: CGFloat = 116
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ShortcutRecorder(
                keyCode: .constant(settings.editorShortcuts[item.rawValue]?.keyCode ?? -1),
                modifiers: .constant(settings.editorShortcuts[item.rawValue]?.modifiers ?? 0),
                onShortcutRecorded: { key, modifiers in
                    error = settings.setEditorShortcut(.init(keyCode: key, modifiers: modifiers), for: item)
                },
                onClear: { error = settings.setEditorShortcut(nil, for: item) },
                allowsUnmodified: true,
                recordingWidth: recordingWidth,
                recordingHeight: recordingWidth < 100 ? 22 : 28,
                textSize: recordingWidth < 100 ? 11 : 13,
                embedsClearButton: recordingWidth < 100
            )
            .accessibilityLabel("\(item.title)快捷键")
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .onChange(of: settings.editorShortcuts) { _ in error = nil }
    }
}
