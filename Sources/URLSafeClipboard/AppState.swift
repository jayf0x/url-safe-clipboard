import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isActive = true
    @Published private(set) var replaceModeEnabled = false
    @Published private(set) var isRefetchingRules = false
    @Published private(set) var rulesStatusMessage: String?

    private let cleaner: URLCleaner
    private let watcher: ClipboardWatcher

    init() {
        cleaner = URLCleaner()
        watcher = ClipboardWatcher(cleaner: cleaner)
        watcher.start()

        Task { [weak self] in
            await self?.refreshRulesOnLaunchIfNeeded()
        }
    }

    func toggleActive() {
        isActive ? pause() : activate()
    }

    func toggleReplaceMode() {
        setReplaceMode(!replaceModeEnabled)
    }

    func setReplaceMode(_ enabled: Bool) {
        replaceModeEnabled = enabled
        watcher.setReplaceMode(enabled)
    }

    func refetchRules() {
        guard !isRefetchingRules else { return }
        isRefetchingRules = true
        rulesStatusMessage = "Refetching rules..."

        Task { [weak self] in
            guard let self else { return }
            let status = await cleaner.refetchRulesManually()
            self.rulesStatusMessage = status.message
            self.isRefetchingRules = false
        }
    }

    func pause() {
        guard isActive else { return }
        isActive = false
        watcher.stop()
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        watcher.start()
    }

    private func refreshRulesOnLaunchIfNeeded() async {
        guard let status = await cleaner.refreshRulesIfNeededOnLaunch() else { return }
        rulesStatusMessage = status.message
    }
}
