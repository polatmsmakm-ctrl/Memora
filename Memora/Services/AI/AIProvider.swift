import Foundation

enum AIRole: String, Codable {
    case user, model
}

struct AIMessage: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var role: AIRole
    var text: String
}

struct AIAttachment {
    var mimeType: String
    var data: Data
}

struct AIRequest {
    var systemInstruction: String
    var messages: [AIMessage]
    var attachments: [AIAttachment] = []
    var jsonOutput: Bool = false
    var temperature: Double = 0.3
}

struct AIModelInfo: Identifiable, Hashable {
    var id: String
    var displayName: String
}

enum AIError: LocalizedError, Equatable {
    case noKey, offline, timeout, rateLimited, forbidden, modelNotFound
    case blocked, invalidResponse, server(Int), ungrounded

    var errorDescription: String? {
        switch self {
        case .noKey: return L("ai.error.noKey")
        case .offline: return L("ai.error.offline")
        case .timeout: return L("ai.error.timeout")
        case .rateLimited: return L("ai.error.rateLimited")
        case .forbidden: return L("ai.error.forbidden")
        case .modelNotFound: return L("ai.error.model")
        case .blocked: return L("ai.error.blocked")
        case .invalidResponse: return L("ai.error.invalid")
        case .server(let code): return LF("ai.error.server", code)
        case .ungrounded: return L("ai.error.ungrounded")
        }
    }
}

/// Provider abstraction so other AI back-ends can be added without touching features.
protocol AIProvider {
    var providerName: String { get }
    func generate(_ request: AIRequest) async throws -> String
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
    func listModels() async throws -> [AIModelInfo]
}
