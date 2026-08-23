import Foundation
import AppKit
import SwiftUI

class NotificationOverlayManager {
    static let shared = NotificationOverlayManager()

    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<NotificationOverlayView>?
    private var hideTimer: DispatchWorkItem?

    private init() {}
    
    func setup() {
        createOverlayWindow()
    }
    
    private func createOverlayWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.hasShadow = true
        window.acceptsMouseMovedEvents = false
        window.ignoresMouseEvents = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        let view = NSHostingView(rootView: NotificationOverlayView())
        hostingView = view
        window.contentView = view
        
        self.overlayWindow = window
    }
    
    func show(notification: AgenticNotification, duration: TimeInterval = 3.0) {
        // Cancel any existing hide timer
        hideTimer?.cancel()

        guard let window = overlayWindow, let view = hostingView else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowWidth: CGFloat = 400
                let windowHeight: CGFloat = 100
                let padding: CGFloat = 20

                let positionRaw = UserDefaults.standard.string(forKey: "overlayPosition") ?? OverlayPosition.topCenter.rawValue
                let position = OverlayPosition(rawValue: positionRaw) ?? .topCenter

                let origin = position.origin(
                    in: screenFrame,
                    size: NSSize(width: windowWidth, height: windowHeight),
                    padding: padding,
                    topInset: 0
                )

                window.setFrame(
                    NSRect(x: origin.x, y: origin.y, width: windowWidth, height: windowHeight),
                    display: true
                )
            }

            view.rootView = NotificationOverlayView(notification: notification)
            window.alphaValue = 0
            window.orderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 1.0
            }

            // Schedule hide with configurable duration
            let workItem = DispatchWorkItem { [weak self] in
                self?.hide()
            }
            self.hideTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }
    
    func hide() {
        guard let window = overlayWindow else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
