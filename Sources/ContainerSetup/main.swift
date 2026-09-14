import AppKit
import AppPackaging
import BraveDestinations
import UniformTypeIdentifiers

@MainActor
final class Setup: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private var paths = BravePaths.standard
    private var destinations: [ResolvedDestination] = []
    private let picker = NSPopUpButton()
    private let appName = NSTextField()
    private let iconPicker = NSPopUpButton()
    private let iconPreview = NSImageView()
    private var selectedDestination: Destination?
    private var editingApp: URL?
    private var customIcon: Data?
    private var shortName: String?
    private var selectedIcon: AppIcon = .generated(.monogram)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let location = NSTextField(wrappingLabelWithString: "")
    private let installButton = NSButton(title: "Install destination", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Brave Container Setup"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Create Brave destination apps")
        title.font = .boldSystemFont(ofSize: 22)
        let instructions = NSTextField(wrappingLabelWithString:
            "Choose a container and profile, set an app name and icon, then install. Add the app to any browser switcher that supports macOS applications.")
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
            button("Edit installed app…", #selector(editInstalled)),
        ])
        buttons.spacing = 10
        appName.placeholderString = "Brave — Work"
        appName.setAccessibilityLabel("Destination app name")
        appName.delegate = self
        let nameRow = NSStackView(views: [NSTextField(labelWithString: "App name"), appName, button("Short name", #selector(useShortName))])
        nameRow.spacing = 10
        let nameHelp = NSTextField(wrappingLabelWithString: "Changes the app label and filename. The container in Brave keeps its name.")
        nameHelp.font = .systemFont(ofSize: 12)
        nameHelp.textColor = .secondaryLabelColor
        iconPicker.target = self
        iconPicker.action = #selector(iconChanged)
        iconPicker.setAccessibilityLabel("Destination icon style")
        iconPreview.imageScaling = .scaleProportionallyUpOrDown
        iconPreview.setAccessibilityLabel("Destination icon preview")
        let iconRow = NSStackView(views: [iconPreview, iconPicker, button("Choose image…", #selector(chooseIcon))])
        iconRow.spacing = 14
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
            "Temporary opens each request in a fresh container; URLs received together share it. Brave may retain temporary data for tab restoration. Requires Brave 1.95.101+. Enable Containers in Brave Settings → Content, wait for settings to save, then Refresh. Your default browser stays unchanged.")
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, instructions, picker, nameRow, nameHelp, iconRow, buttons, status, pathsButtons, location, footer])
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
            nameRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            appName.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
            iconPreview.widthAnchor.constraint(equalToConstant: 72),
            iconPreview.heightAnchor.constraint(equalToConstant: 72),
            iconPicker.widthAnchor.constraint(equalToConstant: 190),
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
            let installation = try BraveInstallation(paths: paths)
            let discovery = Discovery(paths: paths)
            var unavailable = 0
            var firstProblem: String?
            for profile in try discovery.profiles() {
                do {
                    let snapshot = try discovery.containers(profileDirectory: profile.directory)
                    guard snapshot.enabled else {
                        unavailable += 1
                        firstProblem = firstProblem ?? "Enable Containers and add or edit a container in Brave’s UI. Wait for the settings to save, then Refresh."
                        continue
                    }
                    if installation.supportsTemporaryContainers {
                        let temporary = try Destination(paths: paths, profileDirectory: profile.directory, selection: .temporary)
                        destinations.append(try discovery.resolve(temporary))
                    }
                    if snapshot.configured == nil {
                        unavailable += 1
                        firstProblem = firstProblem ?? "Add or edit a named container in Brave’s UI, then Refresh."
                    }
                    for container in snapshot.configured ?? [] {
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

    @objc private func selectionChanged() {
        selectedDestination = nil
        editingApp = nil
        shortName = nil
        appName.stringValue = ""
        installButton.isEnabled = false
        guard destinations.indices.contains(picker.indexOfSelectedItem) else { return }
        let resolved = destinations[picker.indexOfSelectedItem]
        selectedDestination = resolved.destination
        shortName = "Brave — \(resolved.container.name)"
        do {
            if let existing = try AppGenerator.installedApp(for: resolved.destination) {
                try loadAppearance(existing)
            } else {
                appName.stringValue = shortName ?? resolved.displayName
                setIcon(.generated(resolved.destination.isTemporary ? .temporary : .monogram))
                installButton.title = "Install destination"
                installButton.isEnabled = true
            }
        } catch { status.stringValue = message(error) }
    }

    private func loadAppearance(_ app: URL) throws {
        let saved = try AppGenerator.readManagedApp(app)
        let icon = try AppGenerator.savedIcon(at: app)
        editingApp = app
        selectedDestination = saved.destination
        paths = saved.destination.paths
        shortName = (try? Discovery(paths: paths).resolve(saved.destination)).map { "Brave — \($0.container.name)" }
        appName.stringValue = saved.displayName
        location.stringValue = "Profile: \(saved.destination.profileDirectory)\nApp: \(app.path)"
        setIcon(icon)
        installButton.title = "Save app"
        installButton.isEnabled = true
    }

    private func setIcon(_ icon: AppIcon) {
        selectedIcon = icon
        customIcon = nil
        iconPicker.removeAllItems()
        iconPicker.addItems(withTitles: IconPreset.allCases.map(\.title))
        switch icon {
        case .generated(let preset): iconPicker.selectItem(at: IconPreset.allCases.firstIndex(of: preset) ?? 0)
        case .custom(let data):
            customIcon = data
            iconPicker.addItem(withTitle: "Custom image")
            iconPicker.selectItem(at: IconPreset.allCases.count)
        }
        updatePreview()
    }

    @objc private func iconChanged() {
        if IconPreset.allCases.indices.contains(iconPicker.indexOfSelectedItem) {
            selectedIcon = .generated(IconPreset.allCases[iconPicker.indexOfSelectedItem])
        } else if let data = customIcon { selectedIcon = .custom(data) }
        updatePreview()
    }

    private func updatePreview() {
        guard let destination = selectedDestination else { iconPreview.image = nil; return }
        let config = DestinationConfiguration(destination: destination, displayName: appName.stringValue)
        do { iconPreview.image = NSImage(data: try DestinationIcons.data(for: selectedIcon, configuration: config)) }
        catch { status.stringValue = message(error) }
    }

    func controlTextDidChange(_ notification: Notification) { updatePreview() }

    @objc private func useShortName() {
        guard let shortName else { status.stringValue = "Enter the app name you want in the name field."; return }
        appName.stringValue = shortName
        updatePreview()
    }

    @objc private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app icon"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .icns]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do { setIcon(try DestinationIcons.importImage(at: url)) }
            catch { status.stringValue = message(error) }
        }
    }

    @objc private func editInstalled() {
        let panel = NSOpenPanel()
        panel.title = "Choose a generated destination app"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = AppGenerator.installDirectory
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try loadAppearance(url)
                destinations = []
                picker.removeAllItems()
                picker.addItem(withTitle: "Installed app · \(selectedDestination?.profileDirectory ?? "")")
                status.stringValue = "Edit the app name or icon, then Save app. Routing stays unchanged."
            } catch { status.stringValue = message(error) }
        }
    }

    private func message(_ error: Error) -> String {
        (error as? AdapterError)?.message ?? "Could not read or update the app. Check file permissions."
    }

    @objc private func install() {
        guard let destination = selectedDestination else { return }
        do {
            if editingApp == nil {
                _ = try BraveInstallation(paths: destination.paths)
                _ = try Discovery(paths: destination.paths).resolve(destination)
            }
            guard let receiver = Bundle.main.resourceURL?.appendingPathComponent("ContainerReceiver") else {
                throw AdapterError("Setup resources are missing. Extract the complete setup app from its ZIP again.")
            }
            let configuration = DestinationConfiguration(destination: destination,
                displayName: appName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            let app = try AppGenerator.generate(configuration: configuration, receiver: receiver,
                directory: editingApp?.deletingLastPathComponent() ?? AppGenerator.installDirectory,
                icon: selectedIcon, rename: true)
            try AppGenerator.register(app)
            try loadAppearance(app)
            status.stringValue = "Saved \(configuration.displayName). Add it to your browser switcher. If its name or icon is cached, remove the old entry and add this app again."
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch { status.stringValue = message(error) }
    }

    @objc private func showInstalled() {
        let directory = editingApp?.deletingLastPathComponent() ?? AppGenerator.installDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.open(directory)
        } else { status.stringValue = "Install a destination first. New apps appear in Applications → Brave Destinations inside your home folder." }
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
