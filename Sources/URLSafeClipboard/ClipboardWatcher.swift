import AppKit
import CryptoKit
import Foundation

@MainActor
final class ClipboardWatcher {
    private let cleaner: URLCleaner
    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private let debounceInterval: TimeInterval

    private var timer: Timer?
    private var pendingWorkItem: DispatchWorkItem?
    private var lastObservedChangeCount: Int
    private var lastClipboardHash: String?
    private var replaceModeEnabled = false

    init(
        cleaner: URLCleaner,
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.2,
        debounceInterval: TimeInterval = 0.08
    ) {
        self.cleaner = cleaner
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.debounceInterval = debounceInterval
        self.lastObservedChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        lastObservedChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollClipboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    func setReplaceMode(_ enabled: Bool) {
        replaceModeEnabled = enabled
    }

    private func pollClipboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastObservedChangeCount else { return }

        lastObservedChangeCount = changeCount
        let currentString = pasteboard.string(forType: .string)
        scheduleProcessing(snapshot: currentString, observedChangeCount: changeCount)
    }

    private func scheduleProcessing(snapshot: String?, observedChangeCount: Int) {
        pendingWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.processClipboard(snapshot: snapshot, observedChangeCount: observedChangeCount)
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func processClipboard(snapshot: String?, observedChangeCount: Int) {
        guard pasteboard.changeCount == observedChangeCount else { return }
        guard let snapshot, !snapshot.isEmpty else {
            lastClipboardHash = nil
            return
        }

        let currentHash = hashForClipboardString(snapshot)
        guard currentHash != lastClipboardHash else { return }

        guard let cleaned = cleaner.cleanedURLStringIfNeeded(from: snapshot, replaceMode: replaceModeEnabled) else {
            lastClipboardHash = currentHash
            return
        }

        if cleaned != snapshot {
            if replaceClipboard(with: cleaned) {
                lastClipboardHash = hashForClipboardString(cleaned)
            }
            return
        }

        lastClipboardHash = currentHash
    }

    private func replaceClipboard(with value: String) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            return false
        }
        lastObservedChangeCount = pasteboard.changeCount
        return true
    }

    private func hashForClipboardString(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
