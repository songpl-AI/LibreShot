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
        VStack(spacing: 24) {
            Image(systemName: "command.keyboard")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 20)
            
            VStack(spacing: 8) {
                Text("快捷键设置")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("点击下方录制区域，按下键盘组合键即可设置。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("区域截图:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        
                        ShortcutRecorder(
                            keyCode: $settings.shortcutKey,
                            modifiers: $settings.shortcutModifiers,
                            onShortcutRecorded: { recordedKey, recordedModifiers in
                                saveShortcut(keyCode: recordedKey, modifiers: recordedModifiers)
                            },
                            onClear: {
                                saveShortcut(keyCode: -1, modifiers: 0)
                            }
                        )
                        .frame(width: 140)
                    }
                    
                    if registerError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("快捷键注册失败，可能被占用")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: 360)
            
            Spacer()
        }
        .padding()
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
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)!)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .shadow(radius: 4)
            
            VStack(spacing: 6) {
                Text("MyScreenShots")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
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
