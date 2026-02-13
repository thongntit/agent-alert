import Foundation
import AppKit

class URLSchemeHandler {
    static let shared = URLSchemeHandler()
    
    private init() {}
    
    func registerHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        handleURL(url)
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "agent-alert" else { return }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.host
        
        switch path {
        case "notify":
            handleNotificationURL(components: components)
        case "test":
            handleTestNotification()
        default:
            break
        }
    }
    
    func handleNotificationURL(components: URLComponents?) {
        guard let queryItems = components?.queryItems else { return }
        
        let sourceString = queryItems.first(where: { $0.name == "source" })?.value ?? "claude"
        let typeString = queryItems.first(where: { $0.name == "type" })?.value ?? "attention"
        let message = queryItems.first(where: { $0.name == "message" })?.value ?? "Notification received"
        
        guard let source = NotificationSource(rawValue: sourceString),
              let type = NotificationType(rawValue: typeString) else {
            return
        }
        
        NotificationManager.shared.handleNotification(source: source, type: type, message: message)
    }
    
    private func handleTestNotification() {
        NotificationManager.shared.handleNotification(
            source: .claude,
            type: .attention,
            message: "Test notification from AgenticNotifier"
        )
    }
}
