import AppKit
import BraveDestinations
import Foundation

@MainActor
final class Receiver: NSObject, NSApplicationDelegate {
    private var pending = URLRequestQueue()
    private var deferredError: AdapterError?
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
        do {
            let descriptors: [NSAppleEventDescriptor]
            if direct.descriptorType == typeAEList {
                guard (1...URLBatch.maximumURLs).contains(direct.numberOfItems) else {
                    throw AdapterError("Send between 1 and 128 URLs per request. This request was rejected.")
                }
                descriptors = try (1...direct.numberOfItems).map {
                    guard let item = direct.atIndex($0) else { throw AdapterError("The sender included an invalid URL list.") }
                    return item
                }
            } else { descriptors = [direct] }
            var total = 0
            let strings = try descriptors.map { descriptor in
                // Bound native descriptor bytes before decoding potentially large strings.
                let bytes = Int(AEGetDescDataSize(descriptor.aeDesc))
                total += bytes
                guard bytes <= URLBatch.maximumURLBytes * 2, total <= URLBatch.maximumBytes * 2,
                      let value = descriptor.stringValue else {
                    throw AdapterError("The URL event is invalid or too large. This request was rejected.")
                }
                return value
            }
            try enqueue(strings)
        } catch {
            reply.setParam(NSAppleEventDescriptor(int32: -10000), forKeyword: keyErrorNumber)
            show(error as? AdapterError ?? AdapterError("The URL request was rejected."))
        }
    }

    // Also accepts AppKit's batched URL delivery. The custom GURL handler above
    // consumes its own events; it does not forward them to AppKit a second time.
    func application(_ application: NSApplication, open urls: [URL]) {
        do {
            guard urls.count <= URLBatch.maximumURLs else { throw AdapterError("Too many URLs in one request; this request was rejected.") }
            try enqueue(urls.map(\.absoluteString))
        } catch { show(error as? AdapterError ?? AdapterError("The URL request was rejected.")) }
    }

    private func enqueue(_ strings: [String]) throws {
        try pending.enqueue(URLBatch(strings))
        drain()
    }

    private func drain() {
        guard !draining, !showingError else { return }
        draining = true
        Task {
            while !showingError, let batch = pending.next() {
                do {
                    guard let resource = Bundle.main.resourceURL else { throw AdapterError("App resources are missing.") }
                    let request = try await Task.detached(priority: .userInitiated) {
                        let config = try DestinationConfiguration.read(from: resource.appendingPathComponent("destination.json"))
                        _ = try BraveInstallation(paths: config.destination.paths)
                        let resolved = try Discovery(paths: config.destination.paths).resolve(config.destination)
                        return try LaunchRequest(resolved: resolved, urls: batch.urls)
                    }.value
                    try BraveLauncher.launch(request) { error in
                        Task { @MainActor [weak self] in self?.show(error) }
                    }
                } catch {
                    show(error as? AdapterError ?? AdapterError("Destination resolution failed. Run cbc doctor."))
                }
            }
            draining = false
            if !pending.isEmpty { drain() }
        }
    }

    private func show(_ error: AdapterError) {
        // Modal alerts run a nested event loop. Queue URLs received while visible.
        guard !showingError else {
            deferredError = deferredError ?? error
            return
        }
        showingError = true
        let alert = NSAlert()
        alert.messageText = "Could not open Brave container"
        alert.informativeText = error.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
        showingError = false
        if let next = deferredError {
            deferredError = nil
            Task { @MainActor in self.show(next) }
        } else { drain() }
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
