import Foundation

struct TranscriptEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var timestamp: Date
    var sourceApp: String?
    var sourceAppBundleID: String?

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.sourceAppBundleID = sourceAppBundleID
    }
}
