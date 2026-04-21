import Foundation

struct SharedStorage {
    static let rulesFileName   = "mail_tracker_rules.json"
    static let logFileName     = "mail_tracker_debug.log"
    static let domainsFileName = "blocked_domains.txt"
    static let eventsFileName  = "tracker_events.json"

    private static let containerURL: URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
    }()

    private static let rulesQueue = DispatchQueue(label: "SharedStorage.rules.queue")
    private static let domainsQueue = DispatchQueue(label: "SharedStorage.domains.queue")
    private static let eventsQueue = DispatchQueue(label: "SharedStorage.events.queue")
    private static var blockedDomainsCache: [String] = []
    private static var blockedDomainsSetCache: Set<String> = []
    private static var blockedDomainsLoadedAt: Date?
    private static var trackerEventIDsCache: Set<String>?
    private static var trackerEventsByIDCache: [String: TrackerEvent]?
    private static var rulesJSONCache: Data?
    private static var rulesJSONLoadedAt: Date?

    // MARK: - Rules JSON

    static func saveRulesJSON(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(rulesFileName) else { return }
        try? data.write(to: url, options: .atomic)
        rulesQueue.sync {
            rulesJSONCache = data
            rulesJSONLoadedAt = Date()
        }
    }

    static func loadRulesJSON() -> Data? {
        guard let url = containerURL?.appendingPathComponent(rulesFileName) else { return nil }
        return rulesQueue.sync {
            let started = PerfClock.now()
            if let cached = rulesJSONCache {
                let elapsedMs = PerfClock.elapsedMs(since: started)
                if elapsedMs >= 20 {
                    DebugLogger.log("loadRulesJSON cache-hit: \(cached.count) bytes in \(elapsedMs)ms")
                }
                return cached
            }
            guard let data = try? Data(contentsOf: url) else {
                let elapsedMs = PerfClock.elapsedMs(since: started)
                DebugLogger.log("loadRulesJSON cache-miss: failed read in \(elapsedMs)ms")
                return nil
            }
            rulesJSONCache = data
            rulesJSONLoadedAt = Date()
            let elapsedMs = PerfClock.elapsedMs(since: started)
            DebugLogger.log("loadRulesJSON cache-miss: \(data.count) bytes in \(elapsedMs)ms")
            return data
        }
    }

    // MARK: - Blocked domains list (for MEMessageActionHandler)

    static func saveBlockedDomains(_ domains: [String]) {
        guard let url = containerURL?.appendingPathComponent(domainsFileName) else { return }
        try? domains.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        domainsQueue.sync {
            blockedDomainsCache = domains
            blockedDomainsSetCache = Set(domains)
            blockedDomainsLoadedAt = Date()
        }
    }

    static func loadBlockedDomains() -> [String] {
        guard let url = containerURL?.appendingPathComponent(domainsFileName) else { return [] }
        return domainsQueue.sync {
            let started = PerfClock.now()
            // Hot path for message decode: avoid touching filesystem for every email.
            // Rules are refreshed explicitly by pipeline + Mail restart.
            if !blockedDomainsCache.isEmpty {
                let elapsedMs = PerfClock.elapsedMs(since: started)
                if elapsedMs >= 20 {
                    DebugLogger.log("loadBlockedDomains cache-hit: \(blockedDomainsCache.count) domains in \(elapsedMs)ms")
                }
                return blockedDomainsCache
            }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                blockedDomainsCache = []
                blockedDomainsSetCache = []
                blockedDomainsLoadedAt = Date()
                let elapsedMs = PerfClock.elapsedMs(since: started)
                DebugLogger.log("loadBlockedDomains cache-miss: failed read in \(elapsedMs)ms")
                return []
            }
            let domains = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            blockedDomainsCache = domains
            blockedDomainsSetCache = Set(domains)
            blockedDomainsLoadedAt = Date()
            let elapsedMs = PerfClock.elapsedMs(since: started)
            DebugLogger.log("loadBlockedDomains cache-miss: \(domains.count) domains in \(elapsedMs)ms")
            return domains
        }
    }

    static func loadBlockedDomainsSet() -> Set<String> {
        guard let url = containerURL?.appendingPathComponent(domainsFileName) else { return [] }
        return domainsQueue.sync {
            if !blockedDomainsSetCache.isEmpty { return blockedDomainsSetCache }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                blockedDomainsCache = []
                blockedDomainsSetCache = []
                blockedDomainsLoadedAt = Date()
                return []
            }
            let domains = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            blockedDomainsCache = domains
            blockedDomainsSetCache = Set(domains)
            blockedDomainsLoadedAt = Date()
            return blockedDomainsSetCache
        }
    }

    // MARK: - Tracker events

    static func hasTrackerEvent(messageID: String) -> Bool {
        eventsQueue.sync {
            ensureTrackerEventIDsLoaded()
            return trackerEventIDsCache?.contains(messageID) ?? false
        }
    }

    static func trackerEvent(messageID: String) -> TrackerEvent? {
        eventsQueue.sync {
            ensureTrackerEventsMapLoaded()
            return trackerEventsByIDCache?[messageID]
        }
    }

    @discardableResult
    static func appendTrackerEvent(_ event: TrackerEvent) -> Bool {
        eventsQueue.sync {
            ensureTrackerEventIDsLoaded()
            if trackerEventIDsCache?.contains(event.messageID) == true { return false }

            var events = loadTrackerEventsUncached()
            events.insert(event, at: 0)
            if events.count > 500 { events = Array(events.prefix(500)) }
            guard let url = containerURL?.appendingPathComponent(eventsFileName),
                  let data = try? JSONEncoder().encode(events) else { return false }
            try? data.write(to: url, options: .atomic)
            trackerEventIDsCache?.insert(event.messageID)
            if trackerEventsByIDCache == nil { trackerEventsByIDCache = [:] }
            trackerEventsByIDCache?[event.messageID] = event
            return true
        }
    }

    static func loadTrackerEvents() -> [TrackerEvent] {
        eventsQueue.sync {
            let events = loadTrackerEventsUncached()
            trackerEventIDsCache = Set(events.map(\.messageID))
            trackerEventsByIDCache = Dictionary(uniqueKeysWithValues: events.map { ($0.messageID, $0) })
            return events
        }
    }

    static func clearTrackerEvents() {
        guard let url = containerURL?.appendingPathComponent(eventsFileName) else { return }
        try? "[]".write(to: url, atomically: true, encoding: .utf8)
        eventsQueue.sync {
            trackerEventIDsCache = []
            trackerEventsByIDCache = [:]
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
        let events = loadTrackerEventsUncached()
        trackerEventIDsCache = Set(events.map(\.messageID))
        if trackerEventsByIDCache == nil {
            trackerEventsByIDCache = Dictionary(uniqueKeysWithValues: events.map { ($0.messageID, $0) })
        }
    }

    private static func ensureTrackerEventsMapLoaded() {
        if trackerEventsByIDCache != nil { return }
        let events = loadTrackerEventsUncached()
        trackerEventsByIDCache = Dictionary(uniqueKeysWithValues: events.map { ($0.messageID, $0) })
        if trackerEventIDsCache == nil {
            trackerEventIDsCache = Set(events.map(\.messageID))
        }
    }

}
