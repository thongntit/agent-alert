import Foundation
import Combine
import AppKit

class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()
    
    @Published var isTyping = false
    @Published var activeApplication: String?
    
    private var lastKeyEventTime: Date?
    private var typingTimer: Timer?
    private var eventMonitor: Any?
    private let typingThreshold: TimeInterval = 1.5
    
    private init() {
        setupEventMonitoring()
    }
    
    private func setupEventMonitoring() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationChanged),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        lastKeyEventTime = Date()
        
        if !isTyping {
            DispatchQueue.main.async { [weak self] in
                self?.isTyping = true
            }
        }
        
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: typingThreshold, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isTyping = false
            }
        }
    }
    
    @objc private func applicationChanged(_ notification: Notification) {
        if let app = NSWorkspace.shared.frontmostApplication {
            activeApplication = app.localizedName
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        typingTimer?.invalidate()
    }
}
