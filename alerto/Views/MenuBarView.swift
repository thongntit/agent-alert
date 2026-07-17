import SwiftUI
import Combine

struct MenuBarView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var serverManager = HTTPServerManager.shared
    @StateObject private var cliProxyService = CLIProxyUsageService.shared

    @State private var isClearAllHovered = false
    @State private var isSettingsHovered = false
    @State private var isQuitHovered = false
    @State private var cliProxyMenuLineIndex = 0

    private let cliProxyRotationTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            serverStatusView

            Divider()

            cliProxyStatusView

            Divider()

            if notificationManager.notifications.isEmpty {
                emptyStateView
            } else {
                notificationsListView
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 320)
        .frame(maxHeight: 450)
        .onReceive(cliProxyRotationTimer) { _ in
            advanceCLIProxyMenuLine()
        }
        .onChange(of: cliProxyMenuLines) { _, _ in
            resetCLIProxyMenuLineRotation()
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Alerto")
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var serverStatusView: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(serverManager.status.displayText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(serverManager.status == .stopped ? "Start" : "Stop") {
                Task {
                    if serverManager.status == .stopped {
                        await serverManager.start()
                    } else {
                        await serverManager.stop()
                    }
                }
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundColor(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var cliProxyStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(cliProxyStatusColor)
                    .frame(width: 8, height: 8)

                Text(cliProxyService.status.displayText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                if cliProxyService.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if let currentCLIProxyMenuLine {
                Text(currentCLIProxyMenuLine)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if !cliProxyService.discoveredAccounts.isEmpty {
                Text("\(cliProxyService.supportedAccountCount) supported account(s) discovered")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var statusColor: Color {
        switch serverManager.status {
        case .running:
            return .green
        case .stopped:
            return .gray
        case .error:
            return .red
        }
    }

    private var cliProxyStatusColor: Color {
        switch cliProxyService.status {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    private var cliProxyMenuLines: [String] {
        cliProxyService.snapshot?.menuLines ?? []
    }

    private var currentCLIProxyMenuLine: String? {
        guard !cliProxyMenuLines.isEmpty else { return nil }
        let index = min(cliProxyMenuLineIndex, cliProxyMenuLines.count - 1)
        return cliProxyMenuLines[index]
    }

    private func advanceCLIProxyMenuLine() {
        guard cliProxyMenuLines.count > 1 else { return }
        cliProxyMenuLineIndex = (cliProxyMenuLineIndex + 1) % cliProxyMenuLines.count
    }

    private func resetCLIProxyMenuLineRotation() {
        if cliProxyMenuLines.isEmpty {
            cliProxyMenuLineIndex = 0
        } else if cliProxyMenuLineIndex >= cliProxyMenuLines.count {
            cliProxyMenuLineIndex = 0
        } else {
            cliProxyMenuLineIndex = 0
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No notifications")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }
    
    private var notificationsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(notificationManager.notifications) { notification in
                    NotificationRowView(notification: notification) {
                        notificationManager.markAsRead(notification)
                    }
                }
            }
            .padding()
        }
    }
    
    private var footerView: some View {
        HStack {
            Button("Clear All") {
                notificationManager.clearAll()
            }
            .buttonStyle(.plain)
            .foregroundColor(isClearAllHovered ? .primary : .secondary)
            .onHover { hovering in
                isClearAllHovered = hovering
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button {
                    SettingsWindowManager.shared.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(isSettingsHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isSettingsHovered = hovering
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(isQuitHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isQuitHovered = hovering
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct NotificationRowView: View {
    let notification: AgenticNotification
    let onMarkAsRead: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notification.source.icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: notification.type.color))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.source.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Spacer()
                    
                    Text(timeAgo(notification.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Text(notification.message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Image(systemName: notification.type.icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: notification.type.color))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .onTapGesture {
            onMarkAsRead()
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}
