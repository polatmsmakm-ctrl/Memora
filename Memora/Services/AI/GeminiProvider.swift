import Foundation

/// Google Gemini via the public REST API (no SDK).
/// POST {base}/models/{model}:generateContent  — header `x-goog-api-key`.
final class GeminiProvider: AIProvider {
    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    static let defaultModel = "gemini-flash-latest"
    /// Used once when the chosen model is overloaded or unavailable.
    static let fallbackModel = "gemini-flash-lite-latest"

    let providerName = "Google Gemini"
    let model: String
    private let apiKeyProvider: () -> String?
    private let session: URLSession

    init(model: String, apiKeyProvider: @escaping () -> String? = { AIKeyStore.currentKey }) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (trimmed.isEmpty ? Self.defaultModel : trimmed).replacingOccurrences(of: "models/", with: "")
        self.apiKeyProvider = apiKeyProvider
        let configuration = URLSessionConfiguration.default
        // Generating a whole set of learning units can take well over a minute.
        // Requests stream, so this is the longest silence allowed between chunks.
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 480
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: Requests

    /// Thinking makes flash models much slower and isn't needed for card generation;
    /// switched off after a 400 in case a model rejects the setting.
    private var limitThinking = true

    private func makeRequest(_ request: AIRequest, stream: Bool, model: String? = nil) throws -> URLRequest {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw AIError.noKey }
        let model = model ?? self.model
        let path = stream ? "models/\(model):streamGenerateContent" : "models/\(model):generateContent"
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if stream { components?.queryItems = [URLQueryItem(name: "alt", value: "sse")] }
        guard let url = components?.url else { throw AIError.invalidResponse }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request, model: model))
        return urlRequest
    }

    private func body(for request: AIRequest, model: String) -> [String: Any] {
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
        var generationConfig: [String: Any] = ["temperature": request.temperature, "maxOutputTokens": 32_768]
        if request.jsonOutput { generationConfig["responseMimeType"] = "application/json" }
        if limitThinking && !model.lowercased().contains("pro") {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }
        var body: [String: Any] = ["contents": contents, "generationConfig": generationConfig]
        if !request.systemInstruction.isEmpty {
            body["systemInstruction"] = ["parts": [["text": request.systemInstruction]]]
        }
        return body
    }

    // MARK: AIProvider

    /// Streams under the hood so long answers never sit silent until the timeout, then
    /// returns the whole text. Retries once on busy/rate-limit errors, then tries the
    /// lighter fallback model.
    func generate(_ request: AIRequest) async throws -> String {
        var lastError: Error = AIError.invalidResponse
        let attempts: [(model: String, delay: UInt64)] = [(model, 0), (model, 2_000_000_000), (Self.fallbackModel, 1_000_000_000)]
        for (index, attempt) in attempts.enumerated() {
            if index > 0 && attempt.model == Self.fallbackModel && model == Self.fallbackModel { break }
            if attempt.delay > 0 { try await Task.sleep(nanoseconds: attempt.delay) }
            do {
                return try await collect(request, model: attempt.model)
            } catch let error as AIError {
                lastError = error
                switch error {
                case .rateLimited, .overloaded, .timeout, .server: continue
                case .modelNotFound where attempt.model != Self.fallbackModel: continue
                case .message where limitThinking:
                    // A model may reject the thinking setting: retry without it.
                    limitThinking = false
                    continue
                default: throw error
                }
            }
        }
        throw lastError
    }

    private func collect(_ request: AIRequest, model: String) async throws -> String {
        var text = ""
        var finish: String?
        do {
            let urlRequest = try makeRequest(request, stream: true, model: model)
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
            guard http.statusCode == 200 else {
                var body = Data()
                for try await byte in bytes { body.append(byte); if body.count > 8_000 { break } }
                throw Self.httpError(http.statusCode, body: body)
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                if let reason = Self.finishReason(from: payload) { finish = reason }
                if let chunk = try Self.extractText(from: payload), !chunk.isEmpty {
                    text += chunk
                    request.onPartial?(text)
                }
            }
        } catch {
            throw Self.map(error)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw finish == "MAX_TOKENS" ? AIError.truncated : AIError.invalidResponse }
        return trimmed
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try self.makeRequest(request, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 8_000 { break } }
                        throw Self.httpError(http.statusCode, body: body)
                    }
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

    static func finishReason(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["candidates"] as? [[String: Any]])?.first else { return nil }
        return first["finishReason"] as? String
    }

    /// Maps an HTTP error, keeping Google's own message where it explains the problem.
    static func httpError(_ status: Int, body: Data = Data()) -> AIError {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = message?.lowercased() ?? ""
        switch status {
        case 400 where lowered.contains("api key") || lowered.contains("api_key"): return .forbidden
        case 401, 403: return .forbidden
        case 404: return .modelNotFound
        case 429: return .rateLimited
        case 500, 503, 504: return .overloaded
        default:
            if let message, !message.isEmpty { return .message(String(message.prefix(220))) }
            return .server(status)
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
