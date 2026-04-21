import Foundation
import CryptoKit
import ContentBlockerConverter

struct PipelineResult {
    let sourceRuleCount: Int
    let postPreFilterCount: Int
    let finalJSONEntryCount: Int
    let jsonData: Data
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
        case .ruleCountExceeded(let n):  return "Rule count \(n) exceeds 150,000 limit"
        }
    }
}

private let ruleLimit = 150_000
private let warnThreshold = 120_000

func runPipeline(rulesText: String, stripDomain: Bool, includeCSSDisplayNone: Bool) throws -> PipelineResult {
    let sourceLines = rulesText.components(separatedBy: .newlines)
    let sourceRuleCount = sourceLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count

    DebugLogger.log("Pipeline start: \(sourceRuleCount) source rules, stripDomain=\(stripDomain), includeCSSDisplayNone=\(includeCSSDisplayNone)")

    let preFiltered = preFilter(rules: sourceLines, stripDomain: stripDomain, includeCSSDisplayNone: includeCSSDisplayNone)
    DebugLogger.log("Post pre-filter: \(preFiltered.count) rules")

    let conversionResult = ContentBlockerConverter().convertArray(
        rules: preFiltered,
        safariVersion: .safari16,
        advancedBlocking: false
    )

    guard let jsonData = conversionResult.safariRulesJSON.data(using: .utf8) else {
        throw PipelineError.invalidJSON
    }

    let (finalData, finalCount) = try postFilter(jsonData: jsonData, includeCSSDisplayNone: includeCSSDisplayNone)

    var warnings: [String] = []
    if finalCount > ruleLimit {
        throw PipelineError.ruleCountExceeded(finalCount)
    }
    if finalCount > warnThreshold {
        warnings.append("Rule count \(finalCount) is approaching the 150,000 limit")
    }
    if conversionResult.errorsCount > 0 {
        warnings.append("Converter reported \(conversionResult.errorsCount) error(s)")
    }
    if conversionResult.discardedSafariRules > 0 {
        warnings.append("\(conversionResult.discardedSafariRules) rule(s) discarded (over limit or unsupported)")
    }

    let jsonHash = finalData.md5HexString
    DebugLogger.log("Pipeline complete: \(finalCount) final rules, JSON hash \(jsonHash)")

    let blockedDomains = extractBlockedDomains(from: preFiltered)
    SharedStorage.saveBlockedDomains(blockedDomains)
    DebugLogger.log("Saved \(blockedDomains.count) blocked domains for tracker detection")

    return PipelineResult(
        sourceRuleCount: sourceRuleCount,
        postPreFilterCount: preFiltered.count,
        finalJSONEntryCount: finalCount,
        jsonData: finalData,
        warnings: warnings
    )
}

private func extractBlockedDomains(from rules: [String]) -> [String] {
    var domains: Set<String> = []
    for rule in rules {
        // Network rules: ||domain^
        if rule.hasPrefix("||") {
            let body = rule.dropFirst(2)
            let domainPart = body.split(omittingEmptySubsequences: true,
                                        whereSeparator: { $0 == "^" || $0 == "$" }).first
                .map(String.init) ?? ""
            if !domainPart.isEmpty, !domainPart.contains("/"), !domainPart.contains("*") {
                domains.insert(domainPart.lowercased())
            }
        }
        // Cosmetic rules: domain##selector  (also catches domain#@#selector)
        if let range = rule.range(of: "##") ?? rule.range(of: "#@#") {
            let domainPart = String(rule[rule.startIndex..<range.lowerBound])
            // Skip generic cosmetic (no domain prefix) and tilde-negated
            if !domainPart.isEmpty, !domainPart.hasPrefix("~"), !domainPart.contains("*") {
                for d in domainPart.split(separator: ",") {
                    let clean = d.trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "~"))
                    if !clean.isEmpty { domains.insert(clean.lowercased()) }
                }
            }
        }
    }
    return Array(domains).sorted()
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
