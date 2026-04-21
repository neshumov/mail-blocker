import MailKit

class ContentBlockerHandler: NSObject, MEContentBlocker {
    func contentRulesJSON() -> Data {
        let started = PerfClock.now()
        guard let data = SharedStorage.loadRulesJSON() else {
            let elapsedMs = PerfClock.elapsedMs(since: started)
            DebugLogger.log("contentRulesJSON: no rules, returning [] (\(elapsedMs)ms)")
            return Data("[]".utf8)
        }
        let elapsedMs = PerfClock.elapsedMs(since: started)
        if elapsedMs >= 20 {
            DebugLogger.log("contentRulesJSON: loaded \(data.count) bytes in \(elapsedMs)ms")
        }
        return data
    }
}
