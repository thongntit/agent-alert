import Foundation
import Combine
import SwiftUI
import AppKit

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [AgenticNotification] = []
    @Published var pendingNotifications: [AgenticNotification] = []
    @Published var showOverlay = false
    @Published var currentNotification: AgenticNotification?
    
    @AppStorage("playSound") private var playSound = true
    @AppStorage("selectedSound") private var selectedSound = "Glass"
    
    private var overlayTimer: Timer?
    private var queueTimer: Timer?
    
    private init() {}
    
    func handleNotification(source: NotificationSource, type: NotificationType, message: String) {
        let notification = AgenticNotification(source: source, type: type, message: message)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if FocusMonitor.shared.isTyping {
                self.pendingNotifications.append(notification)
                self.scheduleQueueProcessing()
            } else {
                self.showNotification(notification)
            }
        }
    }
    
    private func showNotification(_ notification: AgenticNotification) {
        currentNotification = notification
        showOverlay = true
        
        if playSound {
            NSSound(named: NSSound.Name(selectedSound))?.play()
        }
        
        overlayTimer?.invalidate()
        overlayTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismissOverlay()
        }
        
        NotificationOverlayManager.shared.show(notification: notification)
    }
    
    func dismissOverlay() {
        showOverlay = false
        if let notification = currentNotification {
            notifications.insert(notification, at: 0)
        }
        currentNotification = nil
        
        processQueue()
    }
    
    private func scheduleQueueProcessing() {
        queueTimer?.invalidate()
        queueTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.processQueue()
        }
    }
    
    private func processQueue() {
        if !FocusMonitor.shared.isTyping, let notification = pendingNotifications.first {
            pendingNotifications.removeFirst()
            showNotification(notification)
            
            if pendingNotifications.isEmpty {
                queueTimer?.invalidate()
            }
        }
    }
    
    func clearAll() {
        notifications.removeAll()
    }
    
    func markAsRead(_ notification: AgenticNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }
}
