import XCTest
@testable import pspsps

// MARK: - Mock URLProtocol

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves httpBody to httpBodyStream; reconstruct it for the handler.
        var handlerRequest = request
        if handlerRequest.httpBody == nil, let stream = handlerRequest.httpBodyStream {
            var bodyData = Data()
            stream.open()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 { bodyData.append(buffer, count: read) }
            }
            buffer.deallocate()
            stream.close()
            var rebuilt = URLRequest(url: request.url!)
            rebuilt.httpMethod = request.httpMethod
            rebuilt.allHTTPHeaderFields = request.allHTTPHeaderFields
            rebuilt.httpBody = bodyData
            handlerRequest = rebuilt
        }

        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 0))
            return
        }
        do {
            let (response, data) = try handler(handlerRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class OllamaPostProcessorTests: XCTestCase {

    var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    private func makeContext(activeApp: String? = nil) -> PostProcessContext {
        PostProcessContext(
            activeApp: activeApp,
            activeAppBundleID: nil,
            previousTranscript: nil,
            timestamp: Date()
        )
    }

    private func successHandler(content: String) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        return { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"message\":{\"role\":\"assistant\",\"content\":\"\(content)\"}}".data(using: .utf8)!
            return (response, body)
        }
    }

    // MARK: - Request body structure

    func testRequestBodyHasCorrectStructure() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}".data(using: .utf8)!
            return (response, body)
        }

        let processor = OllamaPostProcessor(model: "qwen3.5:4b", session: session)
        _ = try await processor.clean(transcript: "hello world", context: makeContext(activeApp: "Xcode"))

        let request = try XCTUnwrap(capturedRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "qwen3.5:4b")
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "user")

        let userContent = try XCTUnwrap(messages[1]["content"] as? String)
        XCTAssertTrue(userContent.contains("Active app:"), "User message must include active app")
        XCTAssertTrue(userContent.contains("Transcript:"), "User message must include transcript label")
    }

    // MARK: - System prompt

    func testSystemPromptContainsAllRequiredRules() async throws {
        var capturedSystemPrompt: String?
        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let messages = json["messages"] as? [[String: Any]],
               let systemContent = messages.first?["content"] as? String {
                capturedSystemPrompt = systemContent
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let responseBody = "{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}".data(using: .utf8)!
            return (response, responseBody)
        }

        let processor = OllamaPostProcessor(session: session)
        _ = try await processor.clean(transcript: "test", context: makeContext())

        let prompt = try XCTUnwrap(capturedSystemPrompt, "System prompt was not captured")

        // 6 cleanup rules
        XCTAssertTrue(prompt.contains("Fix obvious transcription errors"), "Missing rule 1")
        XCTAssertTrue(prompt.contains("Fix punctuation and capitalization"), "Missing rule 2")
        XCTAssertTrue(prompt.contains("Expand common abbreviations"), "Missing rule 3")
        XCTAssertTrue(prompt.contains("Remove filler words"), "Missing rule 4")
        XCTAssertTrue(prompt.contains("Correct technical terms"), "Missing rule 5")
        XCTAssertTrue(prompt.contains("active application"), "Missing rule 6")

        // 4 "Do NOT" rules
        XCTAssertTrue(prompt.contains("Do NOT"), "Missing Do NOT section")
        XCTAssertTrue(prompt.contains("Rephrase or rewrite"), "Missing Do NOT rule 1")
        XCTAssertTrue(prompt.contains("Add words the speaker did not say"), "Missing Do NOT rule 2")
        XCTAssertTrue(prompt.contains("intentional repetition"), "Missing Do NOT rule 3")
        XCTAssertTrue(prompt.contains("speaker's meaning"), "Missing Do NOT rule 4")
    }

    // MARK: - Response parsing

    func testSuccessfulResponseParsesMessageContent() async throws {
        MockURLProtocol.requestHandler = successHandler(content: "The quick brown fox.")

        let processor = OllamaPostProcessor(session: session)
        let result = try await processor.clean(transcript: "the quick brown fox", context: makeContext())

        XCTAssertEqual(result, "The quick brown fox.")
    }

    // MARK: - Fallback behavior

    func testConnectionFailureReturnsRawTranscript() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let processor = OllamaPostProcessor(session: session)
        let result = try await processor.clean(transcript: "raw transcript", context: makeContext())

        XCTAssertEqual(result, "raw transcript")
    }

    func testModelNotFoundReturnsRawTranscript() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let processor = OllamaPostProcessor(session: session)
        let result = try await processor.clean(transcript: "raw transcript", context: makeContext())

        XCTAssertEqual(result, "raw transcript")
    }

    // MARK: - isAvailable

    func testIsAvailableChecksBothHostReachabilityAndModelExistence() async {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(
                request.url?.path.hasSuffix("/api/tags") == true,
                "Should call GET /api/tags, got \(request.url?.absoluteString ?? "nil")"
            )
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"models\":[{\"name\":\"qwen3.5:4b\"},{\"name\":\"llama3.2:3b\"}]}".data(using: .utf8)!
            return (response, body)
        }

        let processor = OllamaPostProcessor(model: "qwen3.5:4b", session: session)
        let available = await processor.checkAvailability()

        XCTAssertTrue(available, "Should be available when model is in tags list")
        XCTAssertTrue(processor.isAvailable)
    }

    func testIsAvailableFalseWhenModelNotInTags() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"models\":[{\"name\":\"llama3.2:3b\"}]}".data(using: .utf8)!
            return (response, body)
        }

        let processor = OllamaPostProcessor(model: "qwen3.5:4b", session: session)
        let available = await processor.checkAvailability()

        XCTAssertFalse(available, "Should be unavailable when model is not in tags list")
        XCTAssertFalse(processor.isAvailable)
    }
}
