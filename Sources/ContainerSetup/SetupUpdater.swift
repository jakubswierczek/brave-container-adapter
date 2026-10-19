import AppKit
import Combine
import Sparkle

/// Retain one instance for Setup's lifetime. Only packaged apps can check for updates.
@MainActor
final class SetupUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private(set) var configurationError: String?
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32,
              bytes.contains(where: { $0 != 0 }),
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ==
                "https://github.com/jakubswierczek/brave-container-adapter/releases/latest/download/appcast.xml"
        else {
            configurationError = "Updates are unavailable in this build. Download a configured release from GitHub."
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        self.controller = controller
        do {
            try controller.updater.start()
            observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
                [weak self] _, change in
                let enabled = change.newValue ?? false
                Task { @MainActor [weak self] in self?.canCheckForUpdates = enabled }
            }
        } catch {
            configurationError = "The updater could not start. Download a fresh release from GitHub."
            self.controller = nil
        }
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(sender)
    }
}
