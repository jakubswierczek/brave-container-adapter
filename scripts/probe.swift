// Minimal direct Process integration probe. Use only isolated test data.
// swift scripts/probe.swift /path/to/Brave.app /path/to/test-data Default Work
import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 4, args[0].hasPrefix("/"), args[1].hasPrefix("/") else {
    fputs("Usage: swift scripts/probe.swift BRAVE_APP TEST_DATA PROFILE_DIRECTORY CONTAINER_NAME\n", stderr)
    exit(2)
}
let process = Process()
process.executableURL = URL(fileURLWithPath: args[0]).appendingPathComponent("Contents/MacOS/Brave Browser")
process.arguments = ["--user-data-dir=\(args[1])", "--profile-directory=\(args[2])", "--container=\(args[3])", "--", "https://example.com"]
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
do {
    try process.run()
    print("Brave process started. Verify profile and container badge in the GUI; process creation is not a routing assertion.")
} catch {
    fputs("Could not execute Brave. URL and browser output omitted.\n", stderr)
    exit(1)
}
