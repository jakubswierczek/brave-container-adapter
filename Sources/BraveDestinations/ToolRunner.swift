import Darwin
import Foundation

public struct ToolInvocation: Sendable {
    public let executable: String
    public let arguments: [String]
    public let failure: String
    public let timeout: TimeInterval

    public init(executable: String, arguments: [String], failure: String, timeout: TimeInterval = 15) {
        self.executable = executable
        self.arguments = arguments
        self.failure = failure
        self.timeout = timeout
    }
}

public enum ToolRunner {
    /// Waits on a worker thread. Cancellation/timeout only stops the child we started.
    public static func run(_ invocation: ToolInvocation) async throws {
        let worker = Task.detached(priority: .userInitiated) { try runBlocking(invocation) }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    private static func runBlocking(_ invocation: ToolInvocation) throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw AdapterError(invocation.failure) }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, invocation.timeout)
        while finished.wait(timeout: .now() + 0.025) == .timedOut {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                if process.isRunning { process.terminate() }
                if finished.wait(timeout: .now() + 0.25) == .timedOut, process.isRunning {
                    // Child has not been reaped while isRunning is true; do not target other PIDs.
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 0.25)
                }
                try Task.checkCancellation()
                throw AdapterError(invocation.failure + " The tool timed out; retry after checking the app directory.")
            }
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw AdapterError(invocation.failure) }
    }
}
