import Combine
import Foundation

final class SettingsViewModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            config.save()
            let newConfig = config
            Task { @MainActor [weak coordinator] in
                if coordinator?.config != newConfig {
                    coordinator?.config = newConfig
                }
            }
        }
    }
    @Published var whisperKitState: ModelDownloadManager.ModelState = .notDownloaded
    @Published var parakeetState: ModelDownloadManager.ModelState = .notDownloaded

    private weak var coordinator: AppCoordinator?
    private weak var downloadManager: ModelDownloadManager?
    private var cancellables: Set<AnyCancellable> = []

    @MainActor
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.downloadManager = coordinator.downloadManager
        self.config = AppConfig.current
        self.whisperKitState = coordinator.downloadManager.whisperKitState
        self.parakeetState = coordinator.downloadManager.parakeetState

        coordinator.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                guard let self else { return }
                if self.config != newConfig {
                    self.config = newConfig
                }
            }
            .store(in: &cancellables)

        coordinator.downloadManager.$whisperKitState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.whisperKitState = state }
            .store(in: &cancellables)

        coordinator.downloadManager.$parakeetState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.parakeetState = state }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func downloadWhisperKit() {
        let dm = downloadManager
        Task { @MainActor in await dm?.downloadWhisperKit() }
    }

    func downloadParakeet() {
        let dm = downloadManager
        Task { @MainActor in await dm?.downloadParakeet() }
    }

    func deleteModel(_ engine: AppConfig.ASREngineOption) {
        let dm = downloadManager
        Task { @MainActor in dm?.deleteModel(engine) }
    }

    func clearHistory() {
        let c = coordinator
        Task { @MainActor in c?.transcriptHistory.clear() }
    }
}
