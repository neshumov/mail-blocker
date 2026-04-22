import Foundation

struct RulesSelfTestResult {
    let trackerHost: String
    let controlHost: String
    let generatedAt: Date
    let ext1Bytes: Int
    let ext2Bytes: Int
    let ext1Entries: Int
    let ext2Entries: Int
    let trackerHitsExt1: Int
    let trackerHitsExt2: Int
    let controlHitsExt1: Int
    let controlHitsExt2: Int
    let blockedDomainsHasTracker: Bool
    let blockedDomainsHasTrackerSuffix: Bool
    let trackerSamplesExt1: [String]
    let trackerSamplesExt2: [String]
    let cssDisplayNoneCountExt1: Int
    let cssDisplayNoneCountExt2: Int
    let cssSelectorProbe: String
    let cssSelectorProbeHitsExt1: Int
    let cssSelectorProbeHitsExt2: Int

    var trackerPresentInRules: Bool {
        (trackerHitsExt1 + trackerHitsExt2) > 0
    }

    var controlUnexpectedlyBlocked: Bool {
        (controlHitsExt1 + controlHitsExt2) > 0
    }

    var cssDisplayNoneTotal: Int {
        cssDisplayNoneCountExt1 + cssDisplayNoneCountExt2
    }

    var cssSelectorProbeTotalHits: Int {
        cssSelectorProbeHitsExt1 + cssSelectorProbeHitsExt2
    }
}

enum RulesSelfTest {
    static func run(trackerHost: String, controlHost: String) -> RulesSelfTestResult {
        let normalizedTracker = normalizeHost(trackerHost)
        let normalizedControl = normalizeHost(controlHost)
        let cssSelectorProbe = "data-mtb-css=\"hide\""

        let ext1Data = SharedStorage.loadRulesJSON(for: BundleIDs.mailExtension) ?? Data("[]".utf8)
        let ext2Data = SharedStorage.loadRulesJSON(for: BundleIDs.mailExtension2) ?? Data("[]".utf8)

        let ext1 = inspectRulesJSON(
            ext1Data,
            host: normalizedTracker,
            controlHost: normalizedControl,
            cssSelectorProbe: cssSelectorProbe
        )
        let ext2 = inspectRulesJSON(
            ext2Data,
            host: normalizedTracker,
            controlHost: normalizedControl,
            cssSelectorProbe: cssSelectorProbe
        )

        let blocked = SharedStorage.loadBlockedDomainsSet()
        let trackerSuffix = trackerSuffixFromHost(normalizedTracker)

        return RulesSelfTestResult(
            trackerHost: normalizedTracker,
            controlHost: normalizedControl,
            generatedAt: Date(),
            ext1Bytes: ext1Data.count,
            ext2Bytes: ext2Data.count,
            ext1Entries: ext1.totalEntries,
            ext2Entries: ext2.totalEntries,
            trackerHitsExt1: ext1.hostHits,
            trackerHitsExt2: ext2.hostHits,
            controlHitsExt1: ext1.controlHits,
            controlHitsExt2: ext2.controlHits,
            blockedDomainsHasTracker: blocked.contains(normalizedTracker),
            blockedDomainsHasTrackerSuffix: trackerSuffix.map { blocked.contains($0) } ?? false,
            trackerSamplesExt1: ext1.hostSamples,
            trackerSamplesExt2: ext2.hostSamples,
            cssDisplayNoneCountExt1: ext1.cssDisplayNoneCount,
            cssDisplayNoneCountExt2: ext2.cssDisplayNoneCount,
            cssSelectorProbe: cssSelectorProbe,
            cssSelectorProbeHitsExt1: ext1.cssSelectorProbeHits,
            cssSelectorProbeHitsExt2: ext2.cssSelectorProbeHits
        )
    }

    private static func inspectRulesJSON(
        _ data: Data,
        host: String,
        controlHost: String,
        cssSelectorProbe: String
    ) -> (
        totalEntries: Int,
        hostHits: Int,
        controlHits: Int,
        hostSamples: [String],
        cssDisplayNoneCount: Int,
        cssSelectorProbeHits: Int
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (0, 0, 0, [], 0, 0)
        }

        var hostHits = 0
        var controlHits = 0
        var samples: [String] = []
        var cssDisplayNoneCount = 0
        var cssSelectorProbeHits = 0

        for rule in object {
            if let action = rule["action"] as? [String: Any],
               let actionType = action["type"] as? String,
               actionType == "css-display-none" {
                cssDisplayNoneCount += 1
                if let selector = action["selector"] as? String,
                   selector.lowercased().contains(cssSelectorProbe.lowercased()) {
                    cssSelectorProbeHits += 1
                }
            }

            guard let trigger = rule["trigger"] as? [String: Any] else { continue }
            guard let filter = trigger["url-filter"] as? String else { continue }
            let normalizedFilter = filter.lowercased()

            if filterMentionsHost(normalizedFilter, host: host) {
                hostHits += 1
                if samples.count < 3 {
                    samples.append(filter)
                }
            }

            if filterMentionsHost(normalizedFilter, host: controlHost) {
                controlHits += 1
            }
        }

        return (object.count, hostHits, controlHits, samples, cssDisplayNoneCount, cssSelectorProbeHits)
    }

    private static func filterMentionsHost(_ filter: String, host: String) -> Bool {
        let escapedHost = host.replacingOccurrences(of: ".", with: "\\.")
        return filter.contains(host) || filter.contains(escapedHost)
    }

    private static func normalizeHost(_ host: String) -> String {
        host
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/")
            .first
            .map(String.init) ?? host.lowercased()
    }

    private static func trackerSuffixFromHost(_ host: String) -> String? {
        guard let dot = host.firstIndex(of: ".") else { return nil }
        let next = host.index(after: dot)
        guard next < host.endIndex else { return nil }
        return String(host[next...])
    }
}
