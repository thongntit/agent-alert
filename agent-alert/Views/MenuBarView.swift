import SwiftUI

struct MenuBarView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
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
    }
    
    private var headerView: some View {
        HStack {
            Text("AgentAlert")
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
            
            Text("\(notificationManager.notifications.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.blue))
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No notifications")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Waiting for Claude Code or OpenCode...")
                .font(.system(size: 12))
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
            .foregroundColor(.red)
            
            Spacer()
            
            SettingsLink {
                Text("Settings")
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
