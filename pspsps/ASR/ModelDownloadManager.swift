import FluidAudio
import Foundation
import WhisperKit

@MainActor
class ModelDownloadManager: ObservableObject {
    @Published var whisperKitState: ModelState = .notDownloaded
    @Published var parakeetState: ModelState = .notDownloaded

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)  // 0.0 to 1.0
        case downloaded
        case failed(String)                 // error description
    }

    init() {
        if isDownloaded(.whisperKit) {
            whisperKitState = .downloaded
        }
        if isDownloaded(.parakeet) {
            parakeetState = .downloaded
        }
    }

    func downloadWhisperKit() async {
        whisperKitState = .downloading(progress: 0.0)
        do {
            try FileManager.default.createDirectory(
                at: WhisperKitEngine.modelDirectory,
                withIntermediateDirectories: true
            )
            _ = try await WhisperKit.download(
                variant: "openai_whisper-large-v3-turbo",
                downloadBase: WhisperKitEngine.modelDirectory
            )
            whisperKitState = .downloaded
        } catch {
            whisperKitState = .failed(error.localizedDescription)
        }
    }

    func downloadParakeet() async {
        parakeetState = .downloading(progress: 0.0)
        do {
            _ = try await AsrModels.download(to: ParakeetEngine.modelDirectory)
            parakeetState = .downloaded
        } catch {
            parakeetState = .failed(error.localizedDescription)
        }
    }

    func isDownloaded(_ engine: AppConfig.ASREngineOption) -> Bool {
        switch engine {
        case .whisperKit:
            let dir = WhisperKitEngine.modelDirectory
            return (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == false
        case .parakeet:
            return AsrModels.modelsExist(at: ParakeetEngine.modelDirectory)
        }
    }

    func deleteModel(_ engine: AppConfig.ASREngineOption) {
        switch engine {
        case .whisperKit:
            try? FileManager.default.removeItem(at: WhisperKitEngine.modelDirectory)
            whisperKitState = .notDownloaded
        case .parakeet:
            try? FileManager.default.removeItem(at: ParakeetEngine.modelDirectory)
            parakeetState = .notDownloaded
        }
    }
}
