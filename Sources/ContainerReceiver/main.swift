import AppKit
import BraveDestinations
import Foundation

@MainActor
final class Receiver: NSObject, NSApplicationDelegate {
    private var pending: [[String]] = []
    private var draining = false
    private var showingError = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else {
            show(AdapterError("The sender did not include a URL.")); return
        }
        if direct.descriptorType == typeAEList {
            var strings: [String] = []
            for index in 1...max(1, direct.numberOfItems) {
                guard let value = direct.atIndex(index)?.stringValue else {
                    show(AdapterError("The sender included an invalid URL list.")); return
                }
                strings.append(value)
            }
            enqueue(strings)
        } else if let value = direct.stringValue { enqueue([value]) }
        else { show(AdapterError("The sender included an invalid URL event.")) }
    }

    // Also accepts AppKit's batched URL delivery. The custom GURL handler above
    // consumes its own events; it does not forward them to AppKit a second time.
    func application(_ application: NSApplication, open urls: [URL]) {
        enqueue(urls.map(\.absoluteString))
    }

    private func enqueue(_ strings: [String]) {
        pending.append(strings)
        drain()
    }

    private func drain() {
        guard !draining, !showingError else { return }
        draining = true
        defer { draining = false }
        while !pending.isEmpty {
            let batch = pending.removeFirst()
            do {
                // Read configuration and metadata afresh for every received batch.
                guard let resource = Bundle.main.resourceURL else { throw AdapterError("App resources are missing.") }
                let config = try DestinationConfiguration.read(from: resource.appendingPathComponent("destination.json"))
                _ = try BraveInstallation(paths: config.destination.paths)
                let urls = try batch.map(WebURL.init)
                let resolved = try Discovery(paths: config.destination.paths).resolve(config.destination)
                let request = try LaunchRequest(resolved: resolved, urls: urls)
                try BraveLauncher.launch(request) { error in
                    Task { @MainActor [weak self] in self?.show(error) }
                }
            } catch {
                show(error as? AdapterError ?? AdapterError("Destination resolution failed. Run cbc doctor."))
            }
        }
    }

    private func show(_ error: AdapterError) {
        // Modal alerts run a nested event loop. Queue URLs received while visible.
        guard !showingError else { return }
        showingError = true
        let alert = NSAlert()
        alert.messageText = "Could not open Brave container"
        alert.informativeText = error.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
        showingError = false
        drain()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pending.isEmpty && !draining && !showingError ? .terminateNow : .terminateCancel
    }
}

let app = NSApplication.shared
let receiver = Receiver()
app.setActivationPolicy(.accessory)
app.delegate = receiver
// Remain resident without a Dock icon. An idle timeout can lose late URL events.
app.run()
