import SwiftUI

struct MenuBarView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var isClearAllHovered = false
    @State private var isSettingsHovered = false
    @State private var isQuitHovered = false
    
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
            Text("Agent Alert")
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
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
                SettingsLink {
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
