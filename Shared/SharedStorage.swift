import Foundation

struct SharedStorage {
    static let rulesFileName   = "mail_tracker_rules.json"
    static let logFileName     = "mail_tracker_debug.log"
    static let domainsFileName = "blocked_domains.txt"
    static let eventsFileName  = "tracker_events.json"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
    }

    // MARK: - Rules JSON

    static func saveRulesJSON(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(rulesFileName) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadRulesJSON() -> Data? {
        guard let url = containerURL?.appendingPathComponent(rulesFileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Blocked domains list (for MEMessageActionHandler)

    static func saveBlockedDomains(_ domains: [String]) {
        guard let url = containerURL?.appendingPathComponent(domainsFileName) else { return }
        try? domains.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func loadBlockedDomains() -> [String] {
        guard let url = containerURL?.appendingPathComponent(domainsFileName),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    // MARK: - Tracker events

    static func appendTrackerEvent(_ event: TrackerEvent) {
        var events = loadTrackerEvents()
        // Avoid duplicates for the same message
        guard !events.contains(where: { $0.messageID == event.messageID }) else { return }
        events.insert(event, at: 0)
        if events.count > 500 { events = Array(events.prefix(500)) }
        guard let url = containerURL?.appendingPathComponent(eventsFileName),
              let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadTrackerEvents() -> [TrackerEvent] {
        guard let url = containerURL?.appendingPathComponent(eventsFileName),
              let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([TrackerEvent].self, from: data) else { return [] }
        return events
    }

    static func clearTrackerEvents() {
        guard let url = containerURL?.appendingPathComponent(eventsFileName) else { return }
        try? "[]".write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Debug log

    static func appendLog(_ entry: String) {
        guard let url = containerURL?.appendingPathComponent(logFileName) else { return }
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func readLog() -> String {
        guard let url = containerURL?.appendingPathComponent(logFileName),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return content
    }

    static func clearLog() {
        guard let url = containerURL?.appendingPathComponent(logFileName) else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
}
