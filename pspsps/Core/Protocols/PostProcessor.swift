protocol PostProcessor: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    func clean(transcript: String, context: PostProcessContext) async throws -> String
}
