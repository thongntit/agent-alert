import Foundation

struct ManagedAgentIntegrationManager {
    static let integrationVersion = 1

    enum IntegrationError: LocalizedError {
        case unsupportedAgent
        case conflictingFile(URL)
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .unsupportedAgent:
                return "This coding agent does not use a managed extension file."
            case .conflictingFile(let url):
                return "A file not owned by Alerto already exists at \(url.path)."
            case .invalidPort:
                return "The Alerto server port is invalid."
            }
        }
    }

    let agent: CodingAgent
    let rootDirectory: URL
    let fileManager: FileManager

    init(agent: CodingAgent, rootDirectory: URL, fileManager: FileManager = .default) {
        self.agent = agent
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    var integrationFile: URL? {
        switch agent {
        case .pi, .omp:
            return rootDirectory
                .appendingPathComponent("extensions", isDirectory: true)
                .appendingPathComponent("alerto-agent-state.ts")
        case .opencode:
            return rootDirectory
                .appendingPathComponent("plugins", isDirectory: true)
                .appendingPathComponent("alerto-agent-state.js")
        case .claude, .codex:
            return nil
        }
    }

    func isOwnedFile() -> Bool {
        guard let content = readContent() else { return false }
        return markerValue("ALERTO_INTEGRATION_ID", in: content) == agent.rawValue
    }

    func installedEvents() -> Set<IntegrationEvent> {
        guard let content = readContent(), isOwnedContent(content) else { return [] }
        let rawEvents = markerValue("ALERTO_EVENTS", in: content) ?? ""
        return Set(rawEvents.split(separator: ",").compactMap {
            IntegrationEvent(rawValue: String($0))
        }).intersection(agent.defaultEvents)
    }

    func status(currentPort: Int, isDetected: Bool) -> AgentIntegrationStatus {
        guard let integrationFile else { return isDetected ? .available : .unavailable }
        guard fileManager.fileExists(atPath: integrationFile.path) else {
            return isDetected ? .available : .unavailable
        }
        guard let content = readContent() else { return .error("Unable to read the integration file.") }
        guard isOwnedContent(content) else { return .conflict }

        let version = markerValue("ALERTO_INTEGRATION_VERSION", in: content).flatMap(Int.init)
        let port = markerValue("ALERTO_PORT", in: content).flatMap(Int.init)
        if version != Self.integrationVersion || port != currentPort || installedEvents().isEmpty {
            return .updateRequired
        }
        return .installed
    }

    func install(events: Set<IntegrationEvent>, port: Int) throws {
        guard (1...65_535).contains(port) else { throw IntegrationError.invalidPort }
        guard let integrationFile else { throw IntegrationError.unsupportedAgent }
        let enabledEvents = events.intersection(agent.defaultEvents)

        if fileManager.fileExists(atPath: integrationFile.path), !isOwnedFile() {
            throw IntegrationError.conflictingFile(integrationFile)
        }

        try fileManager.createDirectory(
            at: integrationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let content = renderedContent(events: enabledEvents, port: port)
        try Data(content.utf8).write(to: integrationFile, options: .atomic)
    }

    func uninstall() throws {
        guard let integrationFile, fileManager.fileExists(atPath: integrationFile.path) else { return }
        guard isOwnedFile() else { throw IntegrationError.conflictingFile(integrationFile) }
        try fileManager.removeItem(at: integrationFile)
    }

    private func readContent() -> String? {
        guard let integrationFile,
              let data = try? Data(contentsOf: integrationFile) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func isOwnedContent(_ content: String) -> Bool {
        markerValue("ALERTO_INTEGRATION_ID", in: content) == agent.rawValue
    }

    private func markerValue(_ name: String, in content: String) -> String? {
        let prefix = "// \(name)="
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func renderedContent(events: Set<IntegrationEvent>, port: Int) -> String {
        let sortedEvents = events.map(\.rawValue).sorted()
        let eventLiteral = sortedEvents.map { "\"\($0)\"" }.joined(separator: ", ")
        let header = """
        // installed by Alerto
        // managed by Alerto; edit event settings in Alerto instead of changing this file.
        // ALERTO_INTEGRATION_ID=\(agent.rawValue)
        // ALERTO_INTEGRATION_VERSION=\(Self.integrationVersion)
        // ALERTO_PORT=\(port)
        // ALERTO_EVENTS=\(sortedEvents.joined(separator: ","))

        """
        return header + template
            .replacingOccurrences(of: "__ALERTO_PORT__", with: String(port))
            .replacingOccurrences(of: "__ALERTO_EVENTS__", with: eventLiteral)
    }

    private var template: String {
        switch agent {
        case .pi: return Self.piTemplate
        case .omp: return Self.ompTemplate
        case .opencode: return Self.openCodeTemplate
        case .claude, .codex: return ""
        }
    }
}

private extension ManagedAgentIntegrationManager {
    static let deliveryTemplate = #"""
const alertoPort = __ALERTO_PORT__;
const enabledEvents = new Set([__ALERTO_EVENTS__]);
let deliveryQueue = Promise.resolve();

function deliveryAttempt(type, message, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  timeout.unref?.();
  return fetch(`http://127.0.0.1:${alertoPort}/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source: ALERTO_SOURCE, type, message }),
    signal: controller.signal,
  }).then(
    () => true,
    () => false,
  ).finally(() => clearTimeout(timeout));
}

async function deliverNow(type, message) {
  if (await deliveryAttempt(type, message, 500)) return;
  await deliveryAttempt(type, message, 1500);
}

function notifyAlerto(eventName, type, message) {
  if (!enabledEvents.has(eventName)) return Promise.resolve();
  deliveryQueue = deliveryQueue.then(
    () => deliverNow(type, message),
    () => deliverNow(type, message),
  );
  return deliveryQueue;
}
"""#

    static let piTemplate = #"""
// @ts-nocheck
const ALERTO_SOURCE = "pi";
"""# + deliveryTemplate + #"""

export default function alertoPiExtension(pi) {
  let rootSession = false;
  let agentActive = false;
  let completionSent = false;

  pi.on("session_start", (_event, ctx) => {
    rootSession = ctx?.mode === "tui";
    if (!rootSession) return;
    agentActive = ctx?.isIdle?.() === false;
    completionSent = false;
  });

  pi.on("agent_start", (_event, ctx) => {
    if (!rootSession || ctx?.mode !== "tui") return;
    agentActive = true;
    completionSent = false;
  });

  pi.on("agent_settled", async (_event, ctx) => {
    if (!rootSession || !agentActive || completionSent || ctx?.isIdle?.() !== true) return;
    agentActive = false;
    completionSent = true;
    await notifyAlerto("completion", "complete", "Pi finished responding");
  });
}
"""#

    static let ompTemplate = #"""
// @ts-nocheck
const ALERTO_SOURCE = "omp";
"""# + deliveryTemplate + #"""

const retryableErrorPattern = /overloaded|provider.?returned.?error|rate.?limit|too many requests|429|500|502|503|504|service.?unavailable|server.?error|internal.?error|network.?error|connection.?error|connection.?refused|connection.?lost|websocket.?closed|websocket.?error|fetch failed|socket hang up|timed? out|timeout|terminated|retry delay/i;

function lastAssistantMessage(messages) {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    if (messages[index]?.role === "assistant") return messages[index];
  }
  return undefined;
}

function endError(event) {
  const messages = Array.isArray(event?.messages) ? event.messages : [];
  const assistant = lastAssistantMessage(messages);
  if (assistant?.stopReason !== "error") return undefined;
  return String(assistant.errorMessage || "Agent error");
}

export default function alertoOmpExtension(pi) {
  let rootSession = false;
  let agentActive = false;
  let idleTimer;
  let retryTimer;

  const clearTimers = () => {
    if (idleTimer) clearTimeout(idleTimer);
    if (retryTimer) clearTimeout(retryTimer);
    idleTimer = undefined;
    retryTimer = undefined;
  };

  const activate = (ctx) => {
    if (ctx?.hasUI !== true) return false;
    rootSession = true;
    return true;
  };

  pi.on("session_start", (_event, ctx) => {
    if (!activate(ctx)) return;
    clearTimers();
    agentActive = ctx?.isIdle?.() === false;
  });

  pi.on("session_switch", (_event, ctx) => {
    if (!activate(ctx)) return;
    clearTimers();
    agentActive = false;
  });

  pi.on("agent_start", (_event, ctx) => {
    if (!rootSession && !activate(ctx)) return;
    clearTimers();
    agentActive = true;
  });

  pi.on("tool_approval_requested", async () => {
    if (!rootSession) return;
    await notifyAlerto("permission", "permission", "Oh My Pi needs your approval");
  });

  pi.on("tool_execution_start", async (event) => {
    if (!rootSession || event?.toolName !== "ask") return;
    await notifyAlerto("question", "question", "Oh My Pi is waiting for your input");
  });

  pi.on("agent_end", (event) => {
    if (!rootSession || !agentActive) return;
    agentActive = false;
    clearTimers();

    const errorMessage = endError(event);
    if (errorMessage && retryableErrorPattern.test(errorMessage)) {
      retryTimer = setTimeout(() => {
        retryTimer = undefined;
        void notifyAlerto("error", "error", "Oh My Pi could not resume after a provider error");
      }, 2500);
      retryTimer.unref?.();
      return;
    }
    if (errorMessage) {
      void notifyAlerto("error", "error", "Oh My Pi stopped with an error");
      return;
    }

    idleTimer = setTimeout(() => {
      idleTimer = undefined;
      void notifyAlerto("completion", "complete", "Oh My Pi finished responding");
    }, 250);
    idleTimer.unref?.();
  });

  pi.on("session_shutdown", clearTimers);
}
"""#

    static let openCodeTemplate = #"""
const ALERTO_SOURCE = "opencode";
"""# + deliveryTemplate + #"""

const childSessions = new Set();
let rootSessionID;
let completionArmed = false;
let completionSent = false;

function sessionIDFrom(properties) {
  return typeof properties?.sessionID === "string" ? properties.sessionID : undefined;
}

function markWorking(sessionID) {
  if (sessionID && childSessions.has(sessionID)) return;
  if (sessionID) rootSessionID = sessionID;
  completionArmed = true;
  completionSent = false;
}

async function markIdle(sessionID) {
  if (sessionID && childSessions.has(sessionID)) return;
  if (rootSessionID && sessionID && sessionID !== rootSessionID) return;
  if (!completionArmed || completionSent) return;
  completionArmed = false;
  completionSent = true;
  await notifyAlerto("completion", "complete", "OpenCode finished responding");
}

export const AlertoNotificationPlugin = async () => ({
  "chat.message": async ({ sessionID }) => markWorking(sessionID),
  event: async ({ event }) => {
    const type = event?.type;
    const properties = event?.properties || {};
    const sessionID = sessionIDFrom(properties);
    const info = properties.info;

    if (info?.id && info.parentID) childSessions.add(info.id);
    const isChild = sessionID && childSessions.has(sessionID);

    switch (type) {
      case "session.created":
      case "session.updated":
        if (!info?.parentID && sessionID && !rootSessionID) rootSessionID = sessionID;
        break;
      case "session.status": {
        const status = typeof properties.status === "string" ? properties.status : properties.status?.type;
        if (status === "idle") await markIdle(sessionID);
        else if (["active", "busy", "pending", "retry", "running", "streaming", "working"].includes(String(status).toLowerCase())) markWorking(sessionID);
        break;
      }
      case "session.idle":
        await markIdle(sessionID);
        break;
      case "permission.asked":
        await notifyAlerto("permission", "permission", "OpenCode needs your approval");
        break;
      case "question.asked":
        await notifyAlerto("question", "question", "OpenCode is waiting for your input");
        break;
      case "session.error":
        if (!isChild) {
          completionArmed = false;
          completionSent = true;
        }
        await notifyAlerto("error", "error", "OpenCode stopped with an error");
        break;
      case "tool.execute.before":
      case "tool.execute.after":
      case "permission.replied":
      case "question.replied":
      case "question.rejected":
      case "session.compacted":
        if (!isChild) markWorking(sessionID);
        break;
      default:
        break;
    }
  },
});
"""#
}
