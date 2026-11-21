import SwiftUI
import ServiceManagement
import CoreGraphics

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
    @State private var selectedItem: ToolbarItem = .select
    @State private var dropTarget: ToolbarItem?
    @State private var shortcutRestoreError: String?

    private static let dragPrefix = "LibreShot.toolbarItem."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolbarOptions

                VStack(alignment: .leading, spacing: 7) {
                    Text("工具顺序")
                        .font(.headline)
                    Text("按从左到右、从上到下排列。拖动排序，点击工具可设置显隐和快捷键。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(settings.toolbarConfiguration.orderedItems) { item in
                            toolbarTile(item)
                        }
                    }
                }

                toolDetails

                if let shortcutRestoreError {
                    Text(shortcutRestoreError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Text("已显示 \(settings.toolbarConfiguration.visibleItems.count) 个按钮")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复快捷键") {
                        settings.restoreDefaultEditorShortcuts()
                        shortcutRestoreError = settings.editorShortcuts.count == EditorShortcut.defaults.count
                            ? nil : "与全局截图冲突的默认快捷键未恢复，请单独设置。"
                    }
                    .help("恢复编辑快捷键")
                    Button("恢复默认") { settings.restoreDefaultToolbar() }
                        .help("恢复工具栏默认配置")
                }
            }
            .padding(16)
        }
    }

    private var toolbarOptions: some View {
        VStack(spacing: 0) {
            optionRow("浮动工具栏位置") {
                Picker("浮动工具栏位置", selection: $settings.toolbarAlignment) {
                    ForEach(ToolbarAlignment.allCases, id: \.self) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
            }
            Divider()
            optionRow("截图后的默认工具") {
                Picker("截图后的默认工具", selection: Binding(
                    get: { settings.defaultEditorTool },
                    set: { settings.setDefaultEditorTool($0) }
                )) {
                    Text(ToolbarItem.select.title).tag(ToolbarItem.select)
                    ForEach(settings.toolbarConfiguration.visibleItems.filter { $0.annotationType != nil }) { item in
                        Text(item.title).tag(item)
                    }
                }
                .help("隐藏默认工具时回到选择／移动")
            }
        }
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
                .labelsHidden()
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var toolDetails: some View {
        let item = selectedItem
        let order = settings.toolbarConfiguration.orderedItems
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Toggle("在工具栏显示", isOn: Binding(
                    get: { settings.toolbarConfiguration.isVisible(item) },
                    set: { settings.setToolbarItem(item, visible: $0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(item.isRequired)
                .help(item.isRequired ? "完成和取消始终显示" : "从下一次截图开始生效")
            }
            HStack {
                Text("快捷键")
                    .foregroundStyle(.secondary)
                if item == .cancel {
                    Text("Esc")
                        .font(.system(.body, design: .monospaced))
                        .help("取消截图使用 Esc")
                } else {
                    ToolbarShortcutRecorder(settings: settings, item: item)
                        .id(item)
                }
                Spacer()
                Button { move(item, towardsStart: true) } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(item == order.first)
                .accessibilityLabel("前移\(item.title)")
                .help("前移")
                Button { move(item, towardsStart: false) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(item == order.last)
                .accessibilityLabel("后移\(item.title)")
                .help("后移")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func toolbarTile(_ item: ToolbarItem) -> some View {
        let visible = settings.toolbarConfiguration.isVisible(item)
        let selected = selectedItem == item
        let targeted = dropTarget == item
        return Button { selectedItem = item } label: {
            VStack(spacing: 3) {
                Group {
                    if item == .mosaic || item == .blur {
                        EffectToolIcon(tool: item).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: item.iconName).font(.system(size: 15))
                    }
                }
                .frame(height: 18)
                Text(item.title)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 26, alignment: .top)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(visible ? Color.primary : Color.secondary)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(selected || targeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected || targeted ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: targeted ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if !visible {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .help("\(item.title) · \(visible ? "已显示" : "已隐藏")")
        .draggable(Self.dragPrefix + item.rawValue)
        .dropDestination(for: String.self) { values, _ in
            guard values.count == 1, let value = values.first, value.hasPrefix(Self.dragPrefix),
                  let source = ToolbarItem(rawValue: String(value.dropFirst(Self.dragPrefix.count))),
                  source != item else { return false }
            let order = settings.toolbarConfiguration.orderedItems
            guard let from = order.firstIndex(of: source), let to = order.firstIndex(of: item) else { return false }
            settings.moveToolbarItems(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            selectedItem = source
            dropTarget = nil
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTarget = item
            } else if dropTarget == item {
                dropTarget = nil
            }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(visible ? "已显示" : "已隐藏")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: Text("前移")) { move(item, towardsStart: true) }
        .accessibilityAction(named: Text("后移")) { move(item, towardsStart: false) }
    }

    private func move(_ item: ToolbarItem, towardsStart: Bool) {
        guard let index = settings.toolbarConfiguration.orderedItems.firstIndex(of: item) else { return }
        settings.moveToolbarItems(fromOffsets: IndexSet(integer: index), toOffset: towardsStart ? index - 1 : index + 2)
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

                        SettingsRow("程序坞:") {
                            Toggle("在程序坞中显示图标", isOn: $settings.showInDock)
                        }
                        Text("关闭后只在菜单栏显示。开启后可用 ⌘Tab 切换，也可在程序坞右键退出。")
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

                        SettingsRow("双击贴图") {
                            Picker("双击贴图时", selection: $settings.pinDoubleClickAction) {
                                ForEach(PinDoubleClickAction.allCases) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
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
                    Text("标注工具和保存等编辑快捷键，可在“工具栏”页点选工具设置。选中标注后按 Delete 删除，⌘Z 撤销。")
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
                recordingWidth: 116
            )
            .accessibilityLabel("\(item.title)快捷键")
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .onChange(of: settings.editorShortcuts) { _ in error = nil }
    }
}
