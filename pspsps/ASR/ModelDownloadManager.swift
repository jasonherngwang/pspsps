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
                downloadBase: WhisperKitEngine.modelDirectory,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.whisperKitState = .downloading(progress: progress.fractionCompleted)
                    }
                }
            )
            whisperKitState = .downloaded
        } catch {
            whisperKitState = .failed(error.localizedDescription)
        }
    }

    func downloadParakeet() async {
        parakeetState = .downloading(progress: 0.0)
        let pollingTask = Task {
            let totalBytes: Double = 480 * 1024 * 1024 // ~480 MB
            while !Task.isCancelled {
                let currentBytes = Double(currentDownloadBytes(targetUrl: ParakeetEngine.modelDirectory))
                let progress = min(1.0, currentBytes / totalBytes)
                await MainActor.run {
                    if case .downloading = self.parakeetState {
                        self.parakeetState = .downloading(progress: progress)
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        do {
            _ = try await AsrModels.download(to: ParakeetEngine.modelDirectory)
            pollingTask.cancel()
            parakeetState = .downloaded
        } catch {
            pollingTask.cancel()
            parakeetState = .failed(error.localizedDescription)
        }
    }

    private func currentDownloadBytes(targetUrl: URL) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0
        
        // 1. Calculate bytes already moved to the target directory
        if let enumerator = fileManager.enumerator(at: targetUrl, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [], errorHandler: { _, _ in false }) {
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                      let fileSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize else { continue }
                size += Int64(fileSize)
            }
        }
        
        // 2. Add the size of the largest active URLSession temporary download file 
        // to approximate the stream of the current file being fetched.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let tempEnumerator = fileManager.enumerator(at: tempDir, includingPropertiesForKeys: [.creationDateKey, .fileAllocatedSizeKey], options: [.skipsSubdirectoryDescendants], errorHandler: nil) {
            var maxRecentTmpSize: Int64 = 0
            let now = Date()
            for case let fileURL as URL in tempEnumerator {
                if fileURL.lastPathComponent.hasPrefix("CFNetworkDownload_") && fileURL.lastPathComponent.hasSuffix(".tmp") {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileAllocatedSizeKey]),
                       let creationDate = resourceValues.creationDate,
                       let fileSize = resourceValues.fileAllocatedSize {
                        // Only count active tmp files created in the last 15 minutes
                        if now.timeIntervalSince(creationDate) < 900 {
                            maxRecentTmpSize = max(maxRecentTmpSize, Int64(fileSize))
                        }
                    }
                }
            }
            size += maxRecentTmpSize
        }
        
        return size
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
