import Foundation
import OSLog

final class OllamaPostProcessor: PostProcessor, @unchecked Sendable {
    let model: String
    let host: String
    let urlSession: URLSession

    var name: String { "Ollama (\(model))" }

    private var _isAvailable: Bool = false
    var isAvailable: Bool { _isAvailable }

    private static let logger = Logger(subsystem: "com.pspsps", category: "OllamaPostProcessor")

    private static let systemPrompt = """
        You are a transcription cleanup assistant. The user will give you a raw speech-to-text transcript.
        Your job is to:
        1. Fix obvious transcription errors (wrong homophones, clearly garbled words)
        2. Fix punctuation and capitalization
        3. Expand common abbreviations if context is clear
        4. Remove filler words (um, uh, like) ONLY if they appear to be accidental
        5. Correct technical terms, product names, and proper nouns based on context
        6. If the active application is provided, use it to infer the appropriate register (formal for email, casual for Slack, code-aware for Xcode)

        Do NOT:
        - Rephrase or rewrite content
        - Add words the speaker did not say
        - Remove intentional repetition or emphasis
        - Change the speaker's meaning in any way

        Return ONLY the cleaned transcript. No explanations, no preamble.
        """

    init(
        model: String = "qwen3.5:4b",
        host: String = "http://localhost:11434",
        session: URLSession = .shared
    ) {
        self.model = model
        self.host = host
        self.urlSession = session
    }

    /// Checks if Ollama host is reachable and the configured model exists in /api/tags.
    @discardableResult
    func checkAvailability() async -> Bool {
        guard let url = URL(string: "\(host)/api/tags") else {
            _isAvailable = false
            return false
        }
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                _isAvailable = false
                return false
            }
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            let found = tags.models.contains { $0.name == model || $0.name.hasPrefix("\(model):") }
            _isAvailable = found
            return found
        } catch {
            Self.logger.error("Ollama availability check failed: \(error)")
            _isAvailable = false
            return false
        }
    }

    func clean(transcript: String, context: PostProcessContext) async throws -> String {
        guard let url = URL(string: "\(host)/api/chat") else {
            Self.logger.error("Invalid Ollama host URL: \(self.host)")
            return transcript
        }

        let userMessage = "Active app: \(context.activeApp ?? "unknown")\nTranscript: \(transcript)"
        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: userMessage)
            ],
            stream: false
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Self.logger.error("Non-HTTP response from Ollama")
                return transcript
            }

            guard httpResponse.statusCode == 200 else {
                Self.logger.error("Ollama returned HTTP \(httpResponse.statusCode) for model \(self.model)")
                return transcript
            }

            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            return chatResponse.message.content
        } catch {
            Self.logger.error("Ollama request failed: \(error)")
            return transcript
        }
    }
}

// MARK: - Private types

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let message: ChatMessage
}

private struct TagsResponse: Decodable {
    let models: [TagModel]

    struct TagModel: Decodable {
        let name: String
    }
}
