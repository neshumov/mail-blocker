import Foundation

struct SharedStorage {
    static let rulesFileName   = "mail_tracker_rules.json"
    static let logFileName     = "mail_tracker_debug.log"
    static let domainsFileName = "blocked_domains.txt"
    static let eventsFileName  = "tracker_events.json"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
    }

    private static let cacheQueue = DispatchQueue(label: "SharedStorage.cache.queue")
    private static var blockedDomainsCache: [String] = []
    private static var blockedDomainsModifiedAt: Date?
    private static var trackerEventIDsCache: Set<String>?

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
        cacheQueue.sync {
            blockedDomainsCache = domains
            blockedDomainsModifiedAt = fileModifiedDate(at: url)
        }
    }

    static func loadBlockedDomains() -> [String] {
        guard let url = containerURL?.appendingPathComponent(domainsFileName) else { return [] }
        return cacheQueue.sync {
            let modifiedAt = fileModifiedDate(at: url)
            if modifiedAt == blockedDomainsModifiedAt {
                return blockedDomainsCache
            }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                blockedDomainsCache = []
                blockedDomainsModifiedAt = modifiedAt
                return []
            }
            let domains = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            blockedDomainsCache = domains
            blockedDomainsModifiedAt = modifiedAt
            return domains
        }
    }

    // MARK: - Tracker events

    static func hasTrackerEvent(messageID: String) -> Bool {
        cacheQueue.sync {
            ensureTrackerEventIDsLoaded()
            return trackerEventIDsCache?.contains(messageID) ?? false
        }
    }

    @discardableResult
    static func appendTrackerEvent(_ event: TrackerEvent) -> Bool {
        cacheQueue.sync {
            ensureTrackerEventIDsLoaded()
            if trackerEventIDsCache?.contains(event.messageID) == true { return false }

            var events = loadTrackerEventsUncached()
            events.insert(event, at: 0)
            if events.count > 500 { events = Array(events.prefix(500)) }
            guard let url = containerURL?.appendingPathComponent(eventsFileName),
                  let data = try? JSONEncoder().encode(events) else { return false }
            try? data.write(to: url, options: .atomic)
            trackerEventIDsCache?.insert(event.messageID)
            return true
        }
    }

    static func loadTrackerEvents() -> [TrackerEvent] {
        cacheQueue.sync {
            let events = loadTrackerEventsUncached()
            trackerEventIDsCache = Set(events.map(\.messageID))
            return events
        }
    }

    static func clearTrackerEvents() {
        guard let url = containerURL?.appendingPathComponent(eventsFileName) else { return }
        try? "[]".write(to: url, atomically: true, encoding: .utf8)
        cacheQueue.sync {
            trackerEventIDsCache = []
        }
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

    // MARK: - Private helpers

    private static func loadTrackerEventsUncached() -> [TrackerEvent] {
        guard let url = containerURL?.appendingPathComponent(eventsFileName),
              let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([TrackerEvent].self, from: data) else { return [] }
        return events
    }

    private static func ensureTrackerEventIDsLoaded() {
        if trackerEventIDsCache != nil { return }
        trackerEventIDsCache = Set(loadTrackerEventsUncached().map(\.messageID))
    }

    private static func fileModifiedDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
