import Foundation
import CryptoKit
import ContentBlockerConverter

struct PipelineResult {
    let sourceRuleCount: Int
    let postPreFilterCount: Int
    let finalJSONEntryCount: Int
    let primaryJSONData: Data
    let secondaryJSONData: Data?
    let primaryJSONEntryCount: Int
    let secondaryJSONEntryCount: Int
    let warnings: [String]
}

enum PipelineError: LocalizedError {
    case conversionFailed(String)
    case invalidJSON
    case ruleCountExceeded(Int)

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let msg): return "Conversion failed: \(msg)"
        case .invalidJSON:               return "SafariConverterLib returned invalid JSON"
        case .ruleCountExceeded(let n):  return "Rule count \(n) exceeds 300,000 combined limit"
        }
    }
}

private let perExtensionRuleLimit = 150_000
private let combinedRuleLimit = 300_000
private let warnThreshold = 270_000

func runPipeline(rulesText: String, stripDomain: Bool, includeCSSDisplayNone: Bool) throws -> PipelineResult {
    let sourceLines = rulesText.components(separatedBy: .newlines)
    let sourceRuleCount = sourceLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count

    DebugLogger.log("Pipeline start: \(sourceRuleCount) source rules, stripDomain=\(stripDomain), includeCSSDisplayNone=\(includeCSSDisplayNone)")

    let preFiltered = preFilter(rules: sourceLines, stripDomain: stripDomain, includeCSSDisplayNone: includeCSSDisplayNone)
    DebugLogger.log("Post pre-filter: \(preFiltered.count) rules")

    let chunks = splitRulesForTwoExtensions(preFiltered)
    let primaryConversion = try convertChunk(
        rules: chunks.primary,
        includeCSSDisplayNone: includeCSSDisplayNone
    )
    let secondaryConversion = try convertChunk(
        rules: chunks.secondary,
        includeCSSDisplayNone: includeCSSDisplayNone
    )

    let finalCount = primaryConversion.count + secondaryConversion.count

    var warnings: [String] = []
    if finalCount > combinedRuleLimit {
        throw PipelineError.ruleCountExceeded(finalCount)
    }
    if finalCount > warnThreshold {
        warnings.append("Rule count \(finalCount) is approaching the 300,000 combined limit")
    }
    let totalErrors = primaryConversion.errors + secondaryConversion.errors
    if totalErrors > 0 {
        warnings.append("Converter reported \(totalErrors) error(s)")
    }
    let totalDiscarded = primaryConversion.discarded + secondaryConversion.discarded
    if totalDiscarded > 0 {
        warnings.append("\(totalDiscarded) rule(s) discarded (over limit or unsupported)")
    }

    let jsonHashPrimary = primaryConversion.data.md5HexString
    let jsonHashSecondary = secondaryConversion.data.md5HexString
    DebugLogger.log(
        "Pipeline complete: \(finalCount) final rules, ext1=\(primaryConversion.count) hash=\(jsonHashPrimary), ext2=\(secondaryConversion.count) hash=\(jsonHashSecondary)"
    )

    let blockedDomains = extractBlockedDomains(from: preFiltered)
    SharedStorage.saveBlockedDomains(blockedDomains)
    DebugLogger.log("Saved \(blockedDomains.count) blocked domains for tracker detection")

    return PipelineResult(
        sourceRuleCount: sourceRuleCount,
        postPreFilterCount: preFiltered.count,
        finalJSONEntryCount: finalCount,
        primaryJSONData: primaryConversion.data,
        secondaryJSONData: secondaryConversion.data,
        primaryJSONEntryCount: primaryConversion.count,
        secondaryJSONEntryCount: secondaryConversion.count,
        warnings: warnings
    )
}

private func splitRulesForTwoExtensions(_ rules: [String]) -> (primary: [String], secondary: [String]) {
    guard rules.count > 1 else { return (rules, []) }
    let pivot = rules.count / 2
    return (Array(rules.prefix(pivot)), Array(rules.dropFirst(pivot)))
}

private func convertChunk(
    rules: [String],
    includeCSSDisplayNone: Bool
) throws -> (data: Data, count: Int, errors: Int, discarded: Int) {
    guard !rules.isEmpty else { return (Data("[]".utf8), 0, 0, 0) }

    let conversionResult = ContentBlockerConverter().convertArray(
        rules: rules,
        safariVersion: .safari16,
        advancedBlocking: false
    )
    guard let jsonData = conversionResult.safariRulesJSON.data(using: .utf8) else {
        throw PipelineError.invalidJSON
    }

    let (postFilteredData, postFilteredCount) = try postFilter(
        jsonData: jsonData,
        includeCSSDisplayNone: includeCSSDisplayNone
    )
    guard postFilteredCount <= perExtensionRuleLimit else {
        throw PipelineError.ruleCountExceeded(postFilteredCount)
    }
    return (
        postFilteredData,
        postFilteredCount,
        conversionResult.errorsCount,
        conversionResult.discardedSafariRules
    )
}

private func extractBlockedDomains(from rules: [String]) -> [String] {
    var domains: Set<String> = []
    for rule in rules {
        guard let host = hostFromRule(rule) else { continue }
        domains.insert(host)
    }
    return Array(domains).sorted()
}

private func hostFromRule(_ rule: String) -> String? {
    let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { return nil }
    if trimmed.contains("##") || trimmed.contains("#@#") || trimmed.contains("#$#") || trimmed.contains("#%#") {
        // Cosmetic/scriptlet rules do not directly point to tracker hosts.
        return nil
    }

    var candidate = trimmed
    if let dollar = candidate.firstIndex(of: "$") {
        candidate = String(candidate[..<dollar])
    }
    if let hash = candidate.firstIndex(of: "#") {
        candidate = String(candidate[..<hash])
    }

    candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "@|~. "))
    if candidate.hasPrefix("||") {
        candidate.removeFirst(2)
    } else if candidate.hasPrefix("|") {
        candidate.removeFirst(1)
    }

    if let schemeRange = candidate.range(of: "://") {
        candidate = String(candidate[schemeRange.upperBound...])
    }

    let stopSet = CharacterSet(charactersIn: "/^*$?,:|")
    if let r = candidate.rangeOfCharacter(from: stopSet) {
        candidate = String(candidate[..<r.lowerBound])
    }

    candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    let lower = candidate.lowercased()

    guard lower.contains(".") else { return nil }
    guard !lower.contains("*") else { return nil }
    guard lower.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil else { return nil }

    return lower
}

private func preFilter(rules: [String], stripDomain: Bool, includeCSSDisplayNone: Bool) -> [String] {
    rules.compactMap { rule in
        let r = rule.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty, !r.hasPrefix("!"), !r.hasPrefix("[") else { return nil }

        // Scriptlet rules
        if r.contains("#%#") || r.contains("#@%#") { return nil }

        // CSS injection
        if r.contains("#$#") || r.contains("#@$#") { return nil }

        // Cosmetic / extended-CSS
        if r.contains("##") || r.contains("#@#") {
            // Always drop extended-CSS selectors
            if r.contains(":has(") || r.contains(":-abp-has") || r.contains(":xpath(") { return nil }
            // Drop plain cosmetic unless we're testing css-display-none
            if !includeCSSDisplayNone { return nil }
        }

        if stripDomain {
            return strippedDomain(from: r)
        }
        return r
    }
}

private func strippedDomain(from rule: String) -> String {
    guard rule.contains("$") else { return rule }
    let parts = rule.split(separator: "$", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return rule }
    let options = parts[1]
        .split(separator: ",")
        .map(String.init)
        .filter { !$0.hasPrefix("domain=") }
    return options.isEmpty ? parts[0] : parts[0] + "$" + options.joined(separator: ",")
}

private func postFilter(jsonData: Data, includeCSSDisplayNone: Bool) throws -> (Data, Int) {
    guard var rules = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
        throw PipelineError.invalidJSON
    }
    if !includeCSSDisplayNone {
        rules.removeAll {
            ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none"
        }
    }
    let data = try JSONSerialization.data(withJSONObject: rules, options: .prettyPrinted)
    return (data, rules.count)
}

private extension Data {
    var md5HexString: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
