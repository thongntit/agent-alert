import Foundation
import Hummingbird
import NIOFoundationCompat
import Logging
import Combine
import ServiceLifecycle

enum HTTPServerStatus: Equatable {
    case stopped
    case running(port: Int)
    case error(message: String)
    
    var displayText: String {
        switch self {
        case .stopped:
            return "HTTP: Stopped"
        case .running(let port):
            return "HTTP: Running on port \(port)"
        case .error(let message):
            return "HTTP: Error - \(message)"
        }
    }
}

@MainActor
class HTTPServerManager: ObservableObject {
    static let shared = HTTPServerManager()
    
    @Published var status: HTTPServerStatus = .stopped
    @Published var port: Int = 7531
    
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private var serviceGroup: ServiceGroup?
    private var serverTask: Task<Void, Never>?
    private var startTime: Date?
    private let logger = Logger(label: "com.alerto.http-server")
    
    private init() {
        if let savedPort = UserDefaults.standard.object(forKey: "httpPort") as? Int {
            self.port = savedPort
        }
    }
    
    var uptime: Int {
        guard let startTime = startTime else { return 0 }
        return Int(Date().timeIntervalSince(startTime))
    }
    
    func start() async {
        guard app == nil else { return }
        
        let router = Router()
        
        router.post("/notify") { request, context in
            return try await self.handleNotify(request: request, context: context)
        }
        
        router.get("/notify") { request, context in
            return try await self.handleNotify(request: request, context: context)
        }
        
        router.get("/health") { request, context in
            return try await self.handleHealth(request: request, context: context)
        }
        
        do {
            let app = Application(
                router: router,
                configuration: .init(
                    address: .hostname("127.0.0.1", port: self.port),
                    serverName: "alerto"
                )
            )
            
            self.app = app
            self.startTime = Date()
            self.status = .running(port: self.port)
            
            logger.info("HTTP server started on port \(self.port)")
            
            let serviceGroup = ServiceGroup(
                configuration: .init(
                    services: [app],
                    logger: logger
                )
            )
            
            self.serviceGroup = serviceGroup
            
            serverTask = Task {
                do {
                    try await serviceGroup.run()
                } catch {
                    await MainActor.run {
                        if !Task.isCancelled {
                            let errorMessage = error.localizedDescription
                            if errorMessage.contains("Address already in use") || errorMessage.contains("EADDRINUSE") {
                                self.status = .error(message: "Port \(self.port) is already in use")
                            } else {
                                self.status = .error(message: errorMessage)
                            }
                            logger.error("HTTP server error: \(error)")
                        }
                    }
                }
            }
        } catch {
            let errorMessage = error.localizedDescription
            if errorMessage.contains("Address already in use") || errorMessage.contains("EADDRINUSE") {
                self.status = .error(message: "Port \(self.port) is already in use")
            } else {
                self.status = .error(message: errorMessage)
            }
            logger.error("Failed to start HTTP server: \(error)")
        }
    }
    
    func stop() async {
        serverTask?.cancel()
        serverTask = nil
        
        self.app = nil
        self.serviceGroup = nil
        self.startTime = nil
        self.status = .stopped
        
        logger.info("HTTP server stopped")
    }
    
    func restart() async {
        await stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await start()
    }
    
    func updatePort(_ newPort: Int) async {
        guard newPort != port else { return }
        port = newPort
        UserDefaults.standard.set(newPort, forKey: "httpPort")
        
        if case .running = status {
            await restart()
        }
    }
    
    private func handleNotify(request: Request, context: BasicRequestContext) async throws -> Response {
        AppLogger.shared.info("\(request.method) \(request.uri.path)", category: .http)

        var source: String?
        var type: String?
        var message: String?
        var hookType: HookType?

        if let query = request.uri.query {
            let params = parseQueryParams(query)
            source = params["source"]
            type = params["type"]
            message = params["message"]
        }

        if request.method == .post {
            if let body = try? await request.body.collect(upTo: 1024 * 1024),
               body.readableBytes > 0 {
                let data = body.getData(at: 0, length: body.readableBytes) ?? Data()
                let bodyString = String(data: data, encoding: .utf8) ?? "Unable to decode body"
                AppLogger.shared.debug("POST body: \(bodyString)", category: .http)

                // First try to parse as HookPayload (agent lifecycle hook data)
                if let hookPayload = try? JSONDecoder().decode(HookPayload.self, from: data) {
                    let hookEventName = hookPayload.hookEventName ?? hookPayload.hookType ?? "nil"
                    AppLogger.shared.info("Parsed as HookPayload: hookEventName=\(hookEventName), message=\(hookPayload.effectiveMessage)", category: .http)
                    source = source ?? hookPayload.effectiveSource
                    type = type ?? hookPayload.effectiveType
                    message = message ?? hookPayload.effectiveMessage

                    // Extract hook type if present
                    hookType = hookPayload.effectiveHookType
                }
                // Fall back to old format (NotifyRequest) for backward compatibility
                else if let json = try? JSONDecoder().decode(NotifyRequest.self, from: data) {
                    AppLogger.shared.info("Parsed as NotifyRequest: source=\(json.source), type=\(json.type), message=\(json.message)", category: .http)
                    source = source ?? json.source
                    type = type ?? json.type
                    message = message ?? json.message
                } else {
                    AppLogger.shared.warning("Failed to parse request body as either HookPayload or NotifyRequest", category: .http)
                }
            } else {
                AppLogger.shared.warning("Request body is empty or unreadable", category: .http)
            }
        }

        guard let sourceValue = source, !sourceValue.isEmpty else {
            AppLogger.shared.error("Missing required parameter: source", category: .http)
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error": "Missing required parameter: source"}"#))
            )
        }

        guard let typeValue = type, !typeValue.isEmpty else {
            AppLogger.shared.error("Missing required parameter: type", category: .http)
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error": "Missing required parameter: type"}"#))
            )
        }

        guard let messageValue = message, !messageValue.isEmpty else {
            AppLogger.shared.error("Missing required parameter: message", category: .http)
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error": "Missing required parameter: message"}"#))
            )
        }

        guard let notificationSource = NotificationSource(rawValue: sourceValue) else {
            AppLogger.shared.error("Invalid source: \(sourceValue)", category: .http)
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error": "Invalid source: \(sourceValue)"}"#))
            )
        }

        guard let notificationType = NotificationType(rawValue: typeValue) else {
            AppLogger.shared.error("Invalid type: \(typeValue)", category: .http)
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error": "Invalid type: \(typeValue)"}"#))
            )
        }

        NotificationManager.shared.handleNotification(
            source: notificationSource,
            type: notificationType,
            message: messageValue,
            hookType: hookType,
            rawMessage: nil
        )
        AppLogger.shared.info("Notification dispatched: source=\(notificationSource.rawValue), type=\(notificationType.rawValue), hookType=\(hookType?.rawValue ?? "none")", category: .http)

        return Response(
            status: .ok,
            body: .init(byteBuffer: ByteBuffer(string: #"{"success": true}"#))
        )
    }
    
    private func handleHealth(request: Request, context: BasicRequestContext) async throws -> Response {
        let uptime = self.uptime
        let response = HealthResponse(status: "ok", uptime: uptime)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        return Response(
            status: .ok,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
    
    private func parseQueryParams(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.split(separator: "&")
        
        for pair in pairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else { continue }
            
            let key = String(components[0])
            let value = String(components[1]).removingPercentEncoding ?? String(components[1])
            params[key] = value
        }
        
        return params
    }
}

private struct NotifyRequest: Codable {
    let source: String
    let type: String
    let message: String
}

/// Represents a lifecycle hook payload from supported coding agents.
struct HookPayload: Codable {
    // Top-level fields (backward compatibility)
    let source: String?
    let type: String?
    let message: String?

    // Claude Code hook specific fields
    let hookType: String?
    let stopHookActive: Bool?

    // Notification hook fields
    let notification: NotificationPayload?

    // Session fields
    let sessionId: String?
    let reason: String?

    // Actual Claude Code hook payload fields
    let hookEventName: String?
    let lastAssistantMessage: String?
    let permissionMode: String?
    let toolName: String?
    let toolInput: ToolInputPayload?
    let agentType: String?
    let cwd: String?
    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case source, type, message
        case hookType = "hook_type"
        case stopHookActive = "stop_hook_active"
        case notification
        case sessionId = "session_id"
        case reason
        case hookEventName = "hook_event_name"
        case lastAssistantMessage = "last_assistant_message"
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case agentType = "agent_type"
        case cwd
        case transcriptPath = "transcript_path"
    }

    /// Extract the effective message from the payload
    var effectiveMessage: String {
        if let msg = message, !msg.isEmpty {
            return msg
        }
        if let notif = notification?.message, !notif.isEmpty {
            return notif
        }
        if (hookEventName ?? hookType)?.lowercased() == "permissionrequest",
           let description = toolInput?.description,
           !description.isEmpty {
            return description
        }
        if let msg = lastAssistantMessage, !msg.isEmpty {
            return msg
        }
        if let description = toolInput?.description, !description.isEmpty {
            return description
        }
        // Fallback based on hook event name
        if let hookEvent = hookEventName ?? hookType {
            switch hookEvent.lowercased() {
            case "stop":
                return "Task completed"
            case "notification":
                return "Claude needs your attention"
            case "sessionend":
                return "Session ended"
            case "permissionrequest":
                if let toolName, !toolName.isEmpty {
                    return "Approval requested for \(toolName)"
                }
                return "Approval requested"
            case "subagentstop":
                if let agentType, !agentType.isEmpty {
                    return "\(agentType) subagent completed"
                }
                return "Subagent completed"
            default:
                return "Notification from Claude Code"
            }
        }
        return "Notification from Claude Code"
    }

    /// Extract the effective type from the payload
    var effectiveType: String {
        if let t = type, !t.isEmpty {
            return t
        }
        if let ht = hookEventName ?? hookType {
            switch ht.lowercased() {
            case "notification":
                return "attention"
            case "stop", "subagentstop":
                return "complete"
            case "sessionend", "session_end":
                return "stop"
            case "permissionrequest":
                return "permission"
            default:
                return "attention"
            }
        }
        return type ?? "attention"
    }

    /// Extract the effective hook type
    var effectiveHookType: HookType? {
        if let ht = hookEventName ?? hookType {
            return HookType(rawValue: ht)
        }
        return nil
    }

    /// Extract the effective source from the payload
    var effectiveSource: String {
        return source ?? "claude"
    }
}

struct NotificationPayload: Codable {
    let message: String?
}

struct ToolInputPayload: Codable {
    let description: String?

    enum CodingKeys: String, CodingKey {
        case description
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            description = nil
            return
        }
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

private struct HealthResponse: Codable {
    let status: String
    let uptime: Int
}
