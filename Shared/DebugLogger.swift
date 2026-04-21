import Foundation

struct DebugLogger {
    static func log(_ message: String) {
        #if DEBUG
        let formatter = ISO8601DateFormatter()
        let entry = "[\(formatter.string(from: Date()))] \(message)\n"
        SharedStorage.appendLog(entry)
        #endif
    }
}
