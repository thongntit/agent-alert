import SwiftUI

struct MenuBarView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var serverManager = HTTPServerManager.shared
    @StateObject private var usageManager = UsageManager.shared
    
    @State private var isClearAllHovered = false
    @State private var isSettingsHovered = false
    @State private var isQuitHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()

            usageSummaryView

            Divider()
            
            serverStatusView
            
            Divider()
            
            if notificationManager.notifications.isEmpty {
                emptyStateView
            } else {
                notificationsListView
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 360)
        .frame(maxHeight: 700)
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

    private var usageSummaryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Remaining Usage")
                    .font(.system(size: 13, weight: .semibold))

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(nextUsageUpdateText(now: context.date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Button {
                    Task {
                        await usageManager.refresh(manual: true)
                    }
                } label: {
                    if usageManager.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(usageManager.isRefreshing)
                .help("Refresh remaining usage")
            }

            if let snapshot = usageManager.snapshot {
                ForEach(UsageProvider.allCases) { provider in
                    if let providerUsage = snapshot.usage(for: provider) {
                        ProviderUsageCard(providerUsage: providerUsage)
                    } else {
                        ProviderUsageUnavailableCard(
                            provider: provider,
                            message: usageManager.providerErrors[provider] ?? "No live limits reported"
                        )
                    }
                }
            } else if usageManager.providerErrors.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking remaining usage…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(UsageProvider.allCases) { provider in
                    ProviderUsageUnavailableCard(
                        provider: provider,
                        message: usageManager.providerErrors[provider] ?? "No live limits reported"
                    )
                }
            }
        }
        .padding(12)
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
        .frame(height: 200)
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

    private func nextUsageUpdateText(now: Date) -> String {
        if usageManager.isRefreshing {
            return "Updating…"
        }

        let base = usageManager.lastRefreshAt ?? now
        let seconds = max(0, Int(ceil(base.addingTimeInterval(5 * 60).timeIntervalSince(now))))
        if seconds >= 60 {
            return "Next update in \(Int(ceil(Double(seconds) / 60)))m"
        }
        return "Next update in \(seconds)s"
    }
}

private struct ProviderUsageUnavailableCard: View {
    let provider: UsageProvider
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: provider.icon)
                .font(.system(size: 12))
                .foregroundColor(provider == .claude ? .purple : .blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }
}

private struct ProviderUsageCard: View {
    let providerUsage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: providerUsage.provider.icon)
                    .font(.system(size: 12))
                    .foregroundColor(tint)

                Text(providerUsage.provider.displayName)
                    .font(.system(size: 12, weight: .medium))

                if let plan = providerUsage.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                if providerUsage.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .help("The latest refresh failed; this is the last successful value")
                }
            }

            if providerUsage.limits.isEmpty {
                Text("No live limits reported")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(providerUsage.limits) { limit in
                    UsageLimitRow(limit: limit, tint: tint)
                }
            }
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }

    private var tint: Color {
        providerUsage.provider == .claude ? .purple : .blue
    }
}

private struct UsageLimitRow: View {
    let limit: UsageLimit
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(limit.label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(limit.formattedRemaining)
                    .font(.system(size: 11, weight: .medium))
            }

            ProgressView(value: limit.remainingPercent, total: 100)
                .tint(tint)

            if let resetsAt = limit.resetsAt {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
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
