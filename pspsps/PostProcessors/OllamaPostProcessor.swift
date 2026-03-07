import Foundation
import OSLog

final class OllamaPostProcessor: PostProcessor {
    let model: String
    let host: String
    let urlSession: URLSession

    var name: String { "Ollama (\(model))" }

    private var _isAvailable: Bool = false
    var isAvailable: Bool { _isAvailable }

    private static let logger = Logger(subsystem: "com.pspsps.pspsps", category: "OllamaPostProcessor")

    private static let systemPrompt = """
        You are a text cleanup tool. You receive raw speech-to-text output and return a cleaned version.

        Rules:
        - Fix punctuation, capitalization, and obvious transcription errors
        - Remove accidental filler words (um, uh)
        - Do NOT rephrase, add words, or change meaning
        - ALWAYS return the cleaned text, even if it seems incomplete or unusual
        - NEVER refuse. NEVER explain. NEVER add commentary
        - Output ONLY the cleaned transcript text, nothing else
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

        let userMessage = transcript
        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: userMessage)
            ],
            stream: false,
            options: ChatOptions(num_predict: 1024),
            think: false
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120  // Ollama may need time to load model on first call
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
            let cleaned = chatResponse.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // If the model refused or returned meta-commentary, fall back to raw transcript.
            let refusalPatterns = ["unable to", "i can't", "i cannot", "as an ai", "i'm sorry"]
            let lower = cleaned.lowercased()
            if refusalPatterns.contains(where: { lower.hasPrefix($0) }) {
                Self.logger.warning("Ollama returned a refusal, using raw transcript")
                return transcript
            }

            return cleaned
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
    let options: ChatOptions?
    let think: Bool?
}

private struct ChatOptions: Encodable {
    let num_predict: Int
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
