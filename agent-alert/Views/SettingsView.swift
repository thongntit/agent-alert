import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            IntegrationsSettingsView()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showOverlay") private var showOverlay = true
    @AppStorage("overlayDuration") private var overlayDuration = 3.0
    @AppStorage("playSound") private var playSound = true
    @AppStorage("selectedSound") private var selectedSound = "Glass"
    
    let availableSounds = ["Glass", "Ping", "Pop", "Purr", "Blow", "Hero", "Submarine"]
    
    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show overlay notification", isOn: $showOverlay)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Overlay duration")
                        Spacer()
                        Text("\(Int(overlayDuration))s")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $overlayDuration, in: 1...10, step: 1)
                }
            }
            
            Section("Sound") {
                Toggle("Play sound", isOn: $playSound)
                
                if playSound {
                    Picker("Notification sound", selection: $selectedSound) {
                        ForEach(availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    HStack {
                        Spacer()
                        Button("Preview Sound") {
                            NSSound(named: NSSound.Name(selectedSound))?.play()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct IntegrationsSettingsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Integrations")
                .font(.title2)
                .fontWeight(.semibold)
            
            Picker("", selection: $selectedTab) {
                Text("Claude Code").tag(0)
                Text("OpenCode").tag(1)
            }
            .pickerStyle(.segmented)
            
            if selectedTab == 0 {
                ClaudeCodeIntegrationView()
            } else {
                OpenCodeIntegrationView()
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ClaudeCodeIntegrationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add this hook to your Claude Code settings (~/.claude/settings.json):")
                .font(.subheadline)
            
            CodeBlockView(code: claudeHookCode)
            
            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(claudeHookCode, forType: .string)
                }
                
                Spacer()
                
                Link("Learn more about hooks", destination: URL(string: "https://code.claude.com/docs/en/hooks-guide")!)
                    .font(.caption)
            }
        }
    }
    
    private var claudeHookCode: String {
        """
        {
          "hooks": {
            "Notification": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "open 'agent-alert://notify?source=claude&type=attention&message=Claude needs your input'"
                  }
                ]
              }
            ]
          }
        }
        """
    }
}

struct OpenCodeIntegrationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create a plugin file at ~/.config/opencode/plugins/agent-alert.js:")
                .font(.subheadline)
            
            CodeBlockView(code: opencodePluginCode)
            
            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(opencodePluginCode, forType: .string)
                }
                
                Spacer()
                
                Link("Learn more about plugins", destination: URL(string: "https://opencode.ai/docs/plugins/")!)
                    .font(.caption)
            }
        }
    }
    
    private var opencodePluginCode: String {
        """
        export const AgentAlertPlugin = async ({ $ }) => {
          return {
            "session.idle": async () => {
              await $`open 'agent-alert://notify?source=opencode&type=idle&message=Session is idle'`
            },
            "message.updated": async ({ message }) => {
              if (message.role === "assistant" && message.content.includes("?")) {
                await $`open 'agent-alert://notify?source=opencode&type=question&message=Assistant asks a question'`
              }
            }
          }
        }
        """
    }
}

struct CodeBlockView: View {
    let code: String
    @State private var codeText: String = ""
    
    var body: some View {
        TextEditor(text: $codeText)
            .font(.system(.caption, design: .monospaced))
            .padding(4)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .frame(height: 150)
            .onAppear {
                codeText = code
            }
    }
}

struct AboutView: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: notificationManager.menubarIcon)
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("AgentAlert")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("A macOS notification app for Claude Code and OpenCode")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
            
            VStack(spacing: 12) {
                Text("Test Notifications")
                    .font(.headline)
                
                Button("Test Notification") {
                    notificationManager.handleNotification(
                        source: .claude,
                        type: .complete,
                        message: "Test notification"
                    )
                }
                .buttonStyle(.borderedProminent)
                
                HStack(spacing: 12) {
                    Button("Mark All Read") {
                        notificationManager.markAllAsRead()
                    }
                    
                    Button("Clear All") {
                        notificationManager.clearAll()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
        }
        .padding()
    }
}
