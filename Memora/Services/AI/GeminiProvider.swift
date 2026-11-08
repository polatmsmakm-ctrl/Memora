import Foundation

/// Google Gemini via the public REST API (no SDK).
/// POST {base}/models/{model}:generateContent  — header `x-goog-api-key`.
final class GeminiProvider: AIProvider {
    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    static let defaultModel = "gemini-flash-latest"

    let providerName = "Google Gemini"
    let model: String
    private let apiKeyProvider: () -> String?
    private let session: URLSession

    init(model: String, apiKeyProvider: @escaping () -> String? = { AIKeyStore.currentKey }) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (trimmed.isEmpty ? Self.defaultModel : trimmed).replacingOccurrences(of: "models/", with: "")
        self.apiKeyProvider = apiKeyProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: Requests

    private func makeRequest(_ request: AIRequest, stream: Bool) throws -> URLRequest {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw AIError.noKey }
        let path = stream ? "models/\(model):streamGenerateContent" : "models/\(model):generateContent"
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if stream { components?.queryItems = [URLQueryItem(name: "alt", value: "sse")] }
        guard let url = components?.url else { throw AIError.invalidResponse }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))
        return urlRequest
    }

    private func body(for request: AIRequest) -> [String: Any] {
        var contents: [[String: Any]] = []
        for (index, message) in request.messages.enumerated() {
            var parts: [[String: Any]] = [["text": message.text]]
            if index == request.messages.count - 1 && message.role == .user {
                for attachment in request.attachments {
                    parts.append(["inline_data": ["mime_type": attachment.mimeType, "data": attachment.data.base64EncodedString()]])
                }
            }
            contents.append(["role": message.role.rawValue, "parts": parts])
        }
        var generationConfig: [String: Any] = ["temperature": request.temperature]
        if request.jsonOutput { generationConfig["responseMimeType"] = "application/json" }
        var body: [String: Any] = ["contents": contents, "generationConfig": generationConfig]
        if !request.systemInstruction.isEmpty {
            body["systemInstruction"] = ["parts": [["text": request.systemInstruction]]]
        }
        return body
    }

    // MARK: AIProvider

    func generate(_ request: AIRequest) async throws -> String {
        let urlRequest = try makeRequest(request, stream: false)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
            guard http.statusCode == 200 else { throw Self.httpError(http.statusCode) }
            guard let text = try Self.extractText(from: data), !text.isEmpty else { throw AIError.invalidResponse }
            return text
        } catch {
            throw Self.map(error)
        }
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try self.makeRequest(request, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
                    guard http.statusCode == 200 else { throw Self.httpError(http.statusCode) }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let text = try Self.extractText(from: Data(payload.utf8)), !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [AIModelInfo] {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw AIError.noKey }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
        guard let url = components?.url else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
            guard http.statusCode == 200 else { throw Self.httpError(http.statusCode) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { throw AIError.invalidResponse }
            let infos = models.compactMap { model -> AIModelInfo? in
                guard let name = model["name"] as? String,
                      let methods = model["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent") else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                let lowered = id.lowercased()
                let excluded = ["embedding", "tts", "image", "live", "audio", "aqa", "veo", "imagen", "robotics"]
                guard lowered.hasPrefix("gemini"), !excluded.contains(where: { lowered.contains($0) }) else { return nil }
                return AIModelInfo(id: id, displayName: model["displayName"] as? String ?? id)
            }
            return Self.sortedNewestFirst(infos)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Helpers

    /// Newest-looking "flash" models first (versions parsed from the id).
    static func sortedNewestFirst(_ models: [AIModelInfo]) -> [AIModelInfo] {
        func version(_ id: String) -> Double {
            let parts = id.split(separator: "-")
            for part in parts { if let v = Double(part) { return v } }
            return 0
        }
        return models.sorted { a, b in
            let aFlash = a.id.contains("flash"), bFlash = b.id.contains("flash")
            if aFlash != bFlash { return aFlash }
            let aStable = !a.id.contains("preview") && !a.id.contains("exp")
            let bStable = !b.id.contains("preview") && !b.id.contains("exp")
            if version(a.id) != version(b.id) { return version(a.id) > version(b.id) }
            if aStable != bStable { return aStable }
            return a.id < b.id
        }
    }

    static func extractText(from data: Data) throws -> String? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let feedback = json["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            throw AIError.blocked
        }
        guard let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first else { return nil }
        if let reason = first["finishReason"] as? String, reason == "SAFETY" || reason == "PROHIBITED_CONTENT" {
            throw AIError.blocked
        }
        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    static func httpError(_ status: Int) -> AIError {
        switch status {
        case 400, 401: return .forbidden
        case 403: return .forbidden
        case 404: return .modelNotFound
        case 429: return .rateLimited
        default: return .server(status)
        }
    }

    static func map(_ error: Error) -> Error {
        if error is AIError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                return AIError.offline
            case .timedOut:
                return AIError.timeout
            case .cancelled:
                return CancellationError()
            default:
                return AIError.offline
            }
        }
        if error is CancellationError { return error }
        return AIError.invalidResponse
    }
}
