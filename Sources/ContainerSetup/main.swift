import AppKit
import AppPackaging
import BraveDestinations

@MainActor
final class Setup: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var paths = BravePaths.standard
    private var destinations: [ResolvedDestination] = []
    private let picker = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let location = NSTextField(wrappingLabelWithString: "")
    private let installButton = NSButton(title: "Install destination", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Brave Container Setup"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Add Brave containers to Choosy")
        title.font = .boldSystemFont(ofSize: 22)
        let instructions = NSTextField(wrappingLabelWithString:
            "Choose a destination on this Mac and install its app. Then drag that app into Choosy’s Browsers list. Repeat for each container you want.")
        picker.target = self
        picker.action = #selector(selectionChanged)
        picker.setAccessibilityLabel("Brave container destination")
        installButton.target = self
        installButton.action = #selector(install)
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [
            button("Refresh", #selector(refresh)), installButton,
            button("Show installed apps", #selector(showInstalled)),
        ])
        buttons.spacing = 10
        let pathsButtons = NSStackView(views: [
            button("Choose Brave…", #selector(chooseBrave)),
            button("Choose data folder…", #selector(chooseData)),
            button("Use standard locations", #selector(resetLocations)),
        ])
        pathsButtons.spacing = 10
        location.font = .systemFont(ofSize: 11)
        location.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Setup status")
        let footer = NSTextField(wrappingLabelWithString:
            "Configure containers in Brave Settings → Content. If none appear, add or edit a container there, wait for Brave to save, then Refresh. Your default browser stays unchanged.")
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, instructions, picker, buttons, status, pathsButtons, location, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            picker.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.heightAnchor.constraint(equalToConstant: 62),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            location.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Brave Container Setup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApplication.shared.mainMenu = menu
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        refresh()
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func refresh() {
        destinations = []
        picker.removeAllItems()
        location.stringValue = "Brave: \(paths.application)\nData: \(paths.userData)"
        do {
            _ = try BraveInstallation(paths: paths)
            let discovery = Discovery(paths: paths)
            var unavailable = 0
            var firstProblem: String?
            for profile in try discovery.profiles() {
                do {
                    let snapshot = try discovery.containers(profileDirectory: profile.directory)
                    guard snapshot.enabled, let containers = snapshot.configured else {
                        unavailable += 1
                        firstProblem = firstProblem ?? "Enable Containers and add or edit a container in Brave’s UI. Wait for the settings to save, then Refresh."
                        continue
                    }
                    for container in containers {
                        let destination = try Destination(paths: paths, profileDirectory: profile.directory, containerID: container.id)
                        destinations.append(try discovery.resolve(destination))
                    }
                } catch {
                    unavailable += 1
                    firstProblem = firstProblem ?? (error as? AdapterError)?.message ?? "Could not read this profile’s settings."
                }
            }
            picker.addItems(withTitles: destinations.map(\.displayName))
            if destinations.isEmpty {
                status.stringValue = "No ready destinations. " + (firstProblem ?? "No saved configured containers were found in the selected data folder.")
            } else {
                status.stringValue = "\(destinations.count) destinations ready." + (unavailable > 0 ? " Some profiles or containers are unavailable; check their saved settings in Brave." : "")
            }
        } catch {
            status.stringValue = (error as? AdapterError)?.message ?? "Could not read Brave’s settings. Check the selected locations."
        }
        selectionChanged()
    }

    @objc private func selectionChanged() { installButton.isEnabled = destinations.indices.contains(picker.indexOfSelectedItem) }

    @objc private func install() {
        guard destinations.indices.contains(picker.indexOfSelectedItem) else { return }
        do {
            let destination = destinations[picker.indexOfSelectedItem].destination
            _ = try BraveInstallation(paths: destination.paths)
            let resolved = try Discovery(paths: destination.paths).resolve(destination)
            guard let receiver = Bundle.main.resourceURL?.appendingPathComponent("ContainerReceiver") else {
                throw AdapterError("Setup resources are missing. Extract the complete setup app from its ZIP again.")
            }
            let configuration = DestinationConfiguration(destination: destination, displayName: resolved.displayName)
            let app = try AppGenerator.generate(configuration: configuration, receiver: receiver, directory: AppGenerator.installDirectory)
            try AppGenerator.register(app)
            status.stringValue = "Installed \(resolved.displayName). Drag the selected app from Finder into Choosy → Browsers."
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            status.stringValue = (error as? AdapterError)?.message ?? "Installation failed. Check destination permissions."
        }
    }

    @objc private func showInstalled() {
        if FileManager.default.fileExists(atPath: AppGenerator.installDirectory.path) {
            NSWorkspace.shared.open(AppGenerator.installDirectory)
        } else { status.stringValue = "Install a destination first. Its app will appear in Applications → Choosy Brave Containers inside your home folder." }
    }

    @objc private func chooseBrave() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Brave application"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            paths = BravePaths(application: url.path, userData: paths.userData)
            refresh()
        }
    }

    @objc private func chooseData() {
        let panel = NSOpenPanel()
        panel.title = "Choose Brave’s user data folder (contains Local State)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: paths.userData)
        if panel.runModal() == .OK, let url = panel.url {
            paths = BravePaths(application: paths.application, userData: url.path)
            refresh()
        }
    }

    @objc private func resetLocations() { paths = .standard; refresh() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let setup = Setup()
application.setActivationPolicy(.regular)
application.delegate = setup
application.run()
