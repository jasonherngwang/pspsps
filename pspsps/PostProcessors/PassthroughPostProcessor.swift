final class PassthroughPostProcessor: PostProcessor {
    let name = "Passthrough"
    let isAvailable = true

    func clean(transcript: String, context: PostProcessContext) async throws -> String {
        return transcript
    }
}
