import MailKit

class ContentBlockerHandler: NSObject, MEContentBlocker {
    func contentRulesJSON() -> Data {
        DebugLogger.log("contentRulesJSON() called at \(Date())")
        guard let data = SharedStorage.loadRulesJSON() else {
            DebugLogger.log("No rules found in App Group, returning empty set")
            return Data("[]".utf8)
        }
        DebugLogger.log("Returning \(data.count) bytes of rules JSON")
        return data
    }
}
