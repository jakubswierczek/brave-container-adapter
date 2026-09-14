import AppKit
import AppPackaging
import BraveDestinations
import Foundation

private struct Options {
    let command: String
    var values: [String: String] = [:]
    var all = false
    var temporary = false

    init(_ arguments: [String]) throws {
        command = arguments.first ?? "help"
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            if key == "--all" {
                guard !all else { throw AdapterError("Repeated --all option.") }
                all = true; index += 1; continue
            }
            if key == "--temporary" {
                guard !temporary else { throw AdapterError("Repeated --temporary option.") }
                temporary = true; index += 1; continue
            }
            guard ["--brave", "--user-data-dir", "--profile", "--container-id", "--output", "--receiver", "--name", "--app"].contains(key),
                  index + 1 < arguments.count, values[key] == nil else {
                throw AdapterError("Unknown, repeated, or incomplete option. Run cbc help.")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
    }

    var paths: BravePaths {
        BravePaths(application: values["--brave"] ?? BravePaths.standard.application,
                   userData: values["--user-data-dir"] ?? BravePaths.standard.userData)
    }
}

private func sayError(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

@MainActor
private func run() throws {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    if ["help", "--help", "-h"].contains(options.command) {
        print("""
        cbc list [--profile DIRECTORY] [path options]
        cbc doctor [--app PATH | --profile DIRECTORY (--container-id ID | --temporary)] [path options]
        cbc generate --profile DIRECTORY (--container-id ID | --temporary) --output DIRECTORY [options]
        cbc install (--all | --profile DIRECTORY (--container-id ID | --temporary)) [options]

        Path options: --brave APP --user-data-dir DIRECTORY
        Generation options: --receiver EXECUTABLE --name LABEL
        --all may be restricted with --profile. It installs enabled, saved configured containers.
        --temporary creates a fresh container per incoming URL batch; requires Brave 1.95.101+.
        install uses ~/Applications/Choosy Brave Containers. Existing destinations keep their IDs.
        No command changes Brave preferences or the default browser.
        """)
        return
    }
    guard ["list", "doctor", "generate", "install"].contains(options.command) else {
        throw AdapterError("Unknown command. Run cbc help.")
    }
    guard !options.temporary || (options.command != "list" && !options.all && options.values["--container-id"] == nil && options.values["--app"] == nil) else {
        throw AdapterError("--temporary requires doctor, generate, or install and cannot be combined with --all, --container-id, or --app.")
    }
    var paths = options.paths
    var selected: Destination?
    if let app = options.values["--app"] {
        guard options.command == "doctor" else { throw AdapterError("--app is only valid with doctor.") }
        let config = try DestinationConfiguration.read(from: URL(fileURLWithPath: BravePaths.canonical(app)).appendingPathComponent("Contents/Resources/destination.json"))
        paths = config.destination.paths
        selected = config.destination
    }
    if selected == nil, options.temporary || options.values["--container-id"] != nil {
        guard let profile = options.values["--profile"] else {
            throw AdapterError("A container destination requires --profile DIRECTORY.")
        }
        let selection: ContainerSelection = options.temporary ? .temporary : .configured(id: options.values["--container-id"]!)
        selected = try Destination(paths: paths, profileDirectory: profile, selection: selection)
    }
    let installation = try BraveInstallation(paths: paths)
    let discovery = Discovery(paths: paths)
    let selectedProfile = selected?.profileDirectory ?? options.values["--profile"]
    let profiles = try discovery.profiles().filter { selectedProfile == nil || $0.directory == selectedProfile }
    guard !profiles.isEmpty else { throw AdapterError("No matching profiles in Local State. Use the profile directory key, not its display name.") }
    if options.command == "list" || options.command == "doctor" {
        print("Brave \(installation.version)")
        var failed = false
        for profile in profiles {
            print("\(profile.directory)  \(profile.displayName)")
            do {
                let snapshot = try discovery.containers(profileDirectory: profile.directory)
                print("  Containers: \(snapshot.enabled ? "enabled" : "disabled or not explicitly saved")")
                if try snapshot.enabled && installation.supportsTemporaryContainers && !discovery.explicitlyDisabledFeature() {
                    print("  temporary  --temporary  Fresh container per incoming URL batch")
                }
                if let configured = snapshot.configured {
                    for container in configured { print("  configured  \(container.id)  \(container.name)") }
                    if configured.isEmpty { print("  No configured containers.") }
                } else {
                    print("  Container list not saved. Add or edit a container in Brave UI, then wait for it to save.")
                }
                let configuredIDs = Set((snapshot.configured ?? []).map(\.id))
                if snapshot.configured != nil {
                    print("  Retained-only records: \(snapshot.retained.keys.filter { !configuredIDs.contains($0) }.count) (not offered as destinations)")
                } else {
                    print("  Retained snapshots: \(snapshot.retained.count) (configured list unavailable; not offered as destinations)")
                }
                if options.command == "doctor" && selected == nil {
                    for container in snapshot.configured ?? [] where snapshot.enabled {
                        _ = try discovery.resolve(Destination(paths: paths, profileDirectory: profile.directory, containerID: container.id))
                    }
                    if !snapshot.enabled || snapshot.configured == nil { failed = true }
                }
            } catch { failed = true; sayError("  " + ((error as? AdapterError)?.message ?? "Metadata inspection failed.")) }
        }
        if options.command == "list" { if failed { throw AdapterError("Some profiles could not be read.") }; return }
        if let selected {
            let resolved = try discovery.resolve(selected)
            print("Destination resolves: \(resolved.displayName)")
            print("Bundle ID: \(selected.bundleIdentifier)")
        }
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        print("HTTPS default: \(handler?.deletingPathExtension().lastPathComponent ?? "unavailable") (unchanged)")
        print("Inspection is read-only. GUI container selection is not confirmed by doctor.")
        print("Named routing baseline: Brave 1.92.140. Temporary routing requires 1.95.101+. Verify routing after Brave updates.")
        if try discovery.explicitlyDisabledFeature() { throw AdapterError("Containers feature is explicitly disabled in brave://flags.") }
        if failed { throw AdapterError("One or more profiles are not ready. See diagnostics above.") }
        return
    }
    guard !(options.all && options.values["--container-id"] != nil), !(options.all && options.values["--name"] != nil) else {
        throw AdapterError("--all cannot be combined with --container-id or --name.")
    }
    let output: URL
    if options.command == "install" {
        guard options.values["--output"] == nil else { throw AdapterError("install uses its dedicated directory. Use generate for a custom output directory.") }
        output = AppGenerator.installDirectory
    } else {
        guard let directory = options.values["--output"] else { throw AdapterError("generate requires --output DIRECTORY.") }
        output = URL(fileURLWithPath: BravePaths.canonical(directory))
    }
    let receiver = options.values["--receiver"].map { URL(fileURLWithPath: BravePaths.canonical($0)) }
        ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("ContainerReceiver")
    var destinations: [ResolvedDestination] = []
    if options.all {
        for profile in profiles {
            let snapshot = try discovery.containers(profileDirectory: profile.directory)
            guard snapshot.enabled, let configured = snapshot.configured else {
                sayError("Skipping \(profile.directory): containers disabled or list not saved."); continue
            }
            for container in configured {
                destinations.append(try discovery.resolve(Destination(paths: paths, profileDirectory: profile.directory, containerID: container.id)))
            }
        }
    } else {
        guard let selected else {
            throw AdapterError("Choose --all or supply --profile DIRECTORY with --container-id ID or --temporary.")
        }
        destinations = [try discovery.resolve(selected)]
    }
    guard !destinations.isEmpty else { throw AdapterError("No enabled, saved container destinations were found. Configure containers in Brave's UI, then run list.") }
    for resolved in destinations {
        let configuration = DestinationConfiguration(destination: resolved.destination, displayName: options.values["--name"] ?? resolved.displayName)
        let app = try AppGenerator.generate(configuration: configuration, receiver: receiver, directory: output)
        if options.command == "install" { try AppGenerator.register(app) }
        print(app.path)
    }
}

do { try run() }
catch { sayError((error as? AdapterError)?.message ?? "Operation failed. Check paths, permissions, and cbc help."); exit(1) }
