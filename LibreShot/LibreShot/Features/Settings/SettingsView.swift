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
            
            AboutSettingsView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 520, height: 360)
        .padding()
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
                                Text(settings.saveDirectory?.path ?? "桌面 (默认)")
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
