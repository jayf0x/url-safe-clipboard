import AppKit
import SwiftUI

@main
struct URLSafeClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            Button(appState.isActive ? "Pause" : "Activate") {
                appState.toggleActive()
            }

            Toggle("Replace params", isOn: Binding(
                get: { appState.replaceModeEnabled },
                set: { appState.setReplaceMode($0) }
            ))
            .keyboardShortcut("r")

            Divider()

            Button(appState.isRefetchingRules ? "Refetching rules..." : "Refetch rules") {
                appState.refetchRules()
            }
            .disabled(appState.isRefetchingRules)

            if !appState.isActive {
                Text("Status: Paused")
                    .font(.caption)
            } else if appState.replaceModeEnabled {
                Text("Status: Active (Replace)")
                    .font(.caption)
            }

            if let rulesStatusMessage = appState.rulesStatusMessage {
                Text(rulesStatusMessage)
                    .font(.caption2)
                    .lineLimit(2)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var iconName: String {
        if !appState.isActive {
            return "pause.circle.fill"
        }
        return "link.circle.fill"
    }
}
