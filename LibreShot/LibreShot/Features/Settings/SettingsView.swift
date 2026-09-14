import SwiftUI
import ServiceManagement

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自定义截图工具栏")
                .font(.headline)
            Text("拖动工具行或点击箭头调整顺序，勾选要显示的工具。")
                .font(.callout)
                .foregroundColor(.secondary)

            List {
                ForEach(settings.toolbarConfiguration.orderedItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Toggle(isOn: Binding(
                            get: { settings.toolbarConfiguration.isVisible(item) },
                            set: { settings.setToolbarItem(item, visible: $0) }
                        )) {
                            Label {
                                Text(item.title)
                            } icon: {
                                if item == .style {
                                    ToolbarColorIcon().frame(width: 20)
                                } else {
                                    Image(systemName: item.iconName).frame(width: 20)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(item.isRequired)
                        .help(item.isRequired ? "始终显示，确保可以完成或取消截图" : item.title)
                        Spacer()
                        if item.isRequired {
                            Text("始终显示").font(.caption).foregroundColor(.secondary)
                        }
                        Button { move(item, upwards: true) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(item == settings.toolbarConfiguration.orderedItems.first)
                        .accessibilityLabel("上移\(item.title)")
                        .help("上移\(item.title)")
                        Button { move(item, upwards: false) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(item == settings.toolbarConfiguration.orderedItems.last)
                        .accessibilityLabel("下移\(item.title)")
                        .help("下移\(item.title)")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(named: Text("上移")) { move(item, upwards: true) }
                    .accessibilityAction(named: Text("下移")) { move(item, upwards: false) }
                }
                .onMove(perform: settings.moveToolbarItems)
            }
            .listStyle(.bordered)

            Text("从下一次截图开始生效。按 Esc 直接取消截图。\n隐藏选择按钮后，可再次点击当前工具，切回选择模式。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("已显示 \(settings.toolbarConfiguration.visibleItems.count) 个按钮")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("恢复默认") { settings.restoreDefaultToolbar() }
                    .help("恢复全部工具的显示和默认顺序")
            }
        }
        .padding()
    }

    private func move(_ item: ToolbarItem, upwards: Bool) {
        guard let index = settings.toolbarConfiguration.orderedItems.firstIndex(of: item) else { return }
        settings.moveToolbarItems(fromOffsets: IndexSet(integer: index), toOffset: upwards ? index - 1 : index + 2)
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
                        Toggle("截图后自动保存", isOn: $settings.autoSaveEnabled)
                            .help("区域截图点击完成时，复制并保存到指定目录；关闭后完成仅复制。全屏截图及长截图的保存按钮也遵循此设置。")
                    }
                    .padding(8)
                }
            } label: {
                Text("存储")
                    .font(.headline)
            }
            
            Spacer()
        }
        .padding()
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
                        description: "立即捕捉当前整个屏幕的内容。",
                        keyCode: $settings.fullScreenShortcutKey,
                        modifiers: $settings.fullScreenShortcutModifiers,
                        onSave: { k, m in saveFullScreenShortcut(keyCode: k, modifiers: m) },
                        onClear: { saveFullScreenShortcut(keyCode: -1, modifiers: 0) }
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    ShortcutRow(
                        title: "长截图",
                        description: "框选滚动区域后开始长截图，完成后自动复制并可继续保存。",
                        keyCode: $settings.longScreenshotShortcutKey,
                        modifiers: $settings.longScreenshotShortcutModifiers,
                        onSave: { k, m in saveLongScreenshotShortcut(keyCode: k, modifiers: m) },
                        onClear: { saveLongScreenshotShortcut(keyCode: -1, modifiers: 0) }
                    )
                    
                    if registerError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("快捷键注册失败，可能已被其他应用占用")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                    }
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
                Text("LibreShot")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2")")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Spacer()
            
            Text("© 2026 Allen. All rights reserved.")
                .font(.footnote)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.bottom)
        }
        .padding()
    }
}
