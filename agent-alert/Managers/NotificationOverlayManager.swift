import Foundation
import AppKit
import SwiftUI

class NotificationOverlayManager {
    static let shared = NotificationOverlayManager()
    
    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<NotificationOverlayView>?
    
    private init() {}
    
    func setup() {
        createOverlayWindow()
    }
    
    private func createOverlayWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless],
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
        
        let view = NSHostingView(rootView: NotificationOverlayView())
        hostingView = view
        window.contentView = view
        
        self.overlayWindow = window
    }
    
    func show(notification: AgenticNotification) {
        guard let window = overlayWindow, let view = hostingView else { return }
        
        DispatchQueue.main.async {
            if let screen = NSScreen.main {
                let screenFrame = screen.frame
                let windowWidth: CGFloat = 400
                let windowHeight: CGFloat = 100
                let padding: CGFloat = 20
                
                let xPosition = (screenFrame.width - windowWidth) / 2
                let yPosition = screenFrame.height - windowHeight - padding - 50
                
                window.setFrame(
                    NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight),
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
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.hide()
            }
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
