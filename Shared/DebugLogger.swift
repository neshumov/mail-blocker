import Foundation

struct DebugLogger {
    private static let formatter = ISO8601DateFormatter()

    static func log(_ message: String) {
        #if DEBUG
        let entry = "[\(formatter.string(from: Date()))] \(message)\n"
        SharedStorage.appendLog(entry)
        #endif
    }
}
