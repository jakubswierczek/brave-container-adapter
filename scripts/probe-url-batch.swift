// Sends one explicit URL-list event to an already-running test receiver.
// Use only generated test apps and neutral URLs; this does not use AppleScript.
import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2,
      let info = NSDictionary(contentsOf: URL(fileURLWithPath: args[0]).appendingPathComponent("Contents/Info.plist")),
      info["CBCManagedBundle"] as? Bool == true,
      let id = info["CFBundleIdentifier"] as? String,
      let receiver = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
    fputs("Usage: swift scripts/probe-url-batch.swift RUNNING_TEST_RECEIVER_APP HTTP_URL [HTTP_URL ...]\n", stderr)
    exit(2)
}
let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kInternetEventClass),
                                            eventID: AEEventID(kAEGetURL),
                                            targetDescriptor: NSAppleEventDescriptor(processIdentifier: receiver.processIdentifier),
                                            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
let urls = NSAppleEventDescriptor.list()
for (index, raw) in args.dropFirst().enumerated() {
    guard let url = URLComponents(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { exit(2) }
    urls.insert(NSAppleEventDescriptor(string: raw), at: index + 1)
}
event.setParam(urls, forKeyword: keyDirectObject)
do {
    try event.sendEvent(options: .noReply, timeout: 5)
    print("Sent \(args.count - 1) URLs in one event. Verify the browser tabs and badges.")
} catch {
    fputs("Could not deliver the test event. URL contents omitted.\n", stderr)
    exit(1)
}
