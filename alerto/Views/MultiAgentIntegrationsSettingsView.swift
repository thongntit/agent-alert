import AppKit
import SwiftUI

struct MultiAgentIntegrationsSettingsView: View {
    @StateObject private var serverManager = HTTPServerManager.shared
    @StateObject private var integrationStore = CodingAgentIntegrationStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coding Agents")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Enable the agents that should send lifecycle notifications to Alerto.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                GroupBox("Alerto Server") {
                    HStack {
                        Circle()
                            .fill(serverStatusColor)
                            .frame(width: 9, height: 9)
                        Text(serverManager.status.displayText)
                            .font(.subheadline)
                        Spacer()
                        Text("Port \(serverManager.port)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                ForEach(CodingAgent.allCases) { agent in
                    AgentIntegrationCard(
                        agent: agent,
                        port: serverManager.port,
                        store: integrationStore
                    )
                }
            }
            .padding()
        }
        .onAppear {
            integrationStore.refresh(port: serverManager.port)
        }
    }

    private var serverStatusColor: Color {
        switch serverManager.status {
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        }
    }
}

private struct AgentIntegrationCard: View {
    let agent: CodingAgent
    let port: Int
    @ObservedObject var store: CodingAgentIntegrationStore

    @State private var eventsExpanded = false

    var body: some View {
        let snapshot = store.snapshot(for: agent, port: port)

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: $eventsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(agent.supportedEvents) { event in
                            Toggle(event.displayName, isOn: eventBinding(event, snapshot: snapshot))
                                .disabled(!snapshot.isEnabled)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Integration directory")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(snapshot.resolvedDirectory.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(snapshot.resolvedDirectory.path)

                            HStack {
                                Button("Choose Folder…") {
                                    chooseDirectory(snapshot: snapshot)
                                }
                                .disabled(snapshot.isEnabled)

                                if store.hasPathOverride(for: agent) {
                                    Button("Use Default") {
                                        store.resetPathOverride(for: agent, port: port)
                                    }
                                    .disabled(snapshot.isEnabled)
                                }

                                Spacer()

                                if snapshot.status == .updateRequired {
                                    Button("Update") {
                                        store.update(agent, port: port)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Events and path")
                        .font(.subheadline)
                }

                if agent == .codex, snapshot.isEnabled {
                    Label("Start a new Codex session, run /hooks, and trust the Alerto hooks.", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if snapshot.status == .conflict {
                    Label("A same-named file not owned by Alerto already exists. Choose another folder or move that file first.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if case .error(let message) = snapshot.status {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                }
            }
        } label: {
            HStack(spacing: 10) {
                NotificationSourceIconView(source: agent.notificationSource, size: 24)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.headline)
                    Text(statusText(snapshot))
                        .font(.caption)
                        .foregroundColor(statusColor(snapshot.status))
                }

                Spacer()

                Toggle("", isOn: enabledBinding(snapshot))
                    .labelsHidden()
                    .disabled(!canToggle(snapshot))
                    .accessibilityLabel("Enable \(agent.displayName)")
            }
        }
    }

    private func enabledBinding(_ snapshot: AgentIntegrationSnapshot) -> Binding<Bool> {
        Binding(
            get: { snapshot.isEnabled },
            set: { store.setEnabled($0, for: agent, port: port) }
        )
    }

    private func eventBinding(
        _ event: IntegrationEvent,
        snapshot: AgentIntegrationSnapshot
    ) -> Binding<Bool> {
        Binding(
            get: { snapshot.enabledEvents.contains(event) },
            set: { store.setEvent(event, enabled: $0, for: agent, port: port) }
        )
    }

    private func canToggle(_ snapshot: AgentIntegrationSnapshot) -> Bool {
        if snapshot.status == .conflict { return false }
        return snapshot.isDetected || snapshot.isEnabled
    }

    private func statusText(_ snapshot: AgentIntegrationSnapshot) -> String {
        if snapshot.isEnabled && !snapshot.isDetected {
            return "Enabled · agent not detected"
        }
        return snapshot.status.displayText
    }

    private func statusColor(_ status: AgentIntegrationStatus) -> Color {
        switch status {
        case .installed: return .green
        case .updateRequired: return .orange
        case .unavailable: return .orange
        case .available: return .secondary
        case .conflict, .error: return .red
        }
    }

    private func chooseDirectory(snapshot: AgentIntegrationSnapshot) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(agent.displayName) configuration directory"
        panel.directoryURL = snapshot.resolvedDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            store.setPathOverride(url, for: agent, port: port)
        }
    }
}
