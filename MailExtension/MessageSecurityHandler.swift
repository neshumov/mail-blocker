import MailKit

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {
    private static let domainRegex = try? NSRegularExpression(
        pattern: "(?:https?://|https?%3a%2f%2f)?([a-z0-9.-]+\\.[a-z]{2,})(?::\\d+)?",
        options: [.caseInsensitive]
    )

    private static let fromHeaderRegex = try? NSRegularExpression(
        pattern: "(?m)^from:\\s*(.+)",
        options: [.caseInsensitive]
    )
    private static let subjectHeaderRegex = try? NSRegularExpression(
        pattern: "(?m)^subject:\\s*(.+)",
        options: [.caseInsensitive]
    )
    private static let messageIDHeaderRegex = try? NSRegularExpression(
        pattern: "(?m)^message-id:\\s*(.+)",
        options: [.caseInsensitive]
    )

    // MARK: - MEMessageDecoder

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        let domains = SharedStorage.loadBlockedDomains()
        guard !domains.isEmpty else { return nil }

        let rawText: String
        if let s = String(data: data, encoding: .utf8) {
            rawText = s
        } else if let s = String(data: data, encoding: .isoLatin1) {
            rawText = s
        } else {
            return nil
        }
        let bodyText = rawText.lowercased()

        let matchedDomains = findMatchedDomains(in: bodyText, blockedDomains: domains)

        guard !matchedDomains.isEmpty else { return nil }

        let senderAddress = extractLineHeader("from", from: rawText) ?? "unknown"
        let subject = extractLineHeader("subject", from: rawText) ?? "(no subject)"
        let messageID = extractLineHeader("message-id", from: rawText) ?? "\(senderAddress)-\(Date().timeIntervalSince1970)"

        // We should still return security information/banner for this message
        // even if it was already recorded before (e.g. Mail re-opens/re-renders it).
        // Deduplication is only for persisted statistics events.
        let isAlreadyRecorded = SharedStorage.hasTrackerEvent(messageID: messageID)

        let event = TrackerEvent(
            messageID: messageID,
            detectedAt: Date(),
            senderAddress: senderAddress,
            subject: subject,
            matchedDomains: Array(matchedDomains).sorted()
        )
        if !isAlreadyRecorded {
            SharedStorage.appendTrackerEvent(event)
            DebugLogger.log("Tracker decoded: '\(subject)' → \(Array(matchedDomains).sorted().joined(separator: ", "))")
        } else {
            DebugLogger.log("Tracker re-detected (already recorded): '\(subject)'")
        }

        let reason = "Possible tracker: \(Array(matchedDomains).sorted().joined(separator: ", "))"
        let secInfo = MEMessageSecurityInformation(
            signers: [],
            isEncrypted: false,
            signingError: nil,
            encryptionError: nil,
            shouldBlockRemoteContent: true,
            localizedRemoteContentBlockingReason: reason
        )
        let banner = MEDecodedMessageBanner(
            title: "Blocked possible tracker",
            primaryActionTitle: "Details",
            dismissable: true
        )
        // Pass original data unchanged — we're not decrypting, just annotating
        return MEDecodedMessage(data: data, securityInformation: secInfo, context: nil, banner: banner)
    }

    // MARK: - MEMessageEncoder (pass-through — we don't sign/encrypt)

    func getEncodingStatus(
        for message: MEMessage,
        composeContext: MEComposeContext,
        completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void
    ) {
        completionHandler(MEOutgoingMessageEncodingStatus(
            canSign: false, canEncrypt: false,
            securityError: nil, addressesFailingEncryption: []
        ))
    }

    func encode(
        _ message: MEMessage,
        composeContext: MEComposeContext,
        completionHandler: @escaping (MEMessageEncodingResult) -> Void
    ) {
        completionHandler(MEMessageEncodingResult(
            encodedMessage: nil, signingError: nil, encryptionError: nil
        ))
    }

    // MARK: - MEMessageSecurityHandler UI (unused — we have no custom view controller)

    func extensionViewController(signers: [MEMessageSigner]) -> MEExtensionViewController? { nil }
    func extensionViewController(messageContext: Data) -> MEExtensionViewController? { nil }
    func primaryActionClicked(forMessageContext context: Data,
                              completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        completionHandler(nil)
    }

    // MARK: - Helpers

    private func findMatchedDomains(in text: String, blockedDomains: [String]) -> Set<String> {
        let blockedSet = Set(blockedDomains)
        let candidateHosts = extractCandidateHosts(from: text)
        var matched: Set<String> = []

        for host in candidateHosts {
            for suffix in hostSuffixes(host) where blockedSet.contains(suffix) {
                matched.insert(suffix)
            }
        }

        // Fallback for edge cases where host extraction misses obfuscated URLs.
        if matched.isEmpty {
            for domain in blockedSet where text.contains(domain) {
                matched.insert(domain)
            }
        }
        return matched
    }

    private func extractCandidateHosts(from text: String) -> Set<String> {
        guard let regex = Self.domainRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var hosts: Set<String> = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { return }
            let host = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if host.contains(".") {
                hosts.insert(host)
            }
        }
        return hosts
    }

    private func hostSuffixes(_ host: String) -> [String] {
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return [host] }
        var result: [String] = []
        result.reserveCapacity(parts.count - 1)
        for idx in 0..<(parts.count - 1) {
            result.append(parts[idx...].joined(separator: "."))
        }
        return result
    }

    private func extractLineHeader(_ name: String, from raw: String) -> String? {
        let regex: NSRegularExpression?
        switch name.lowercased() {
        case "from":
            regex = Self.fromHeaderRegex
        case "subject":
            regex = Self.subjectHeaderRegex
        case "message-id":
            regex = Self.messageIDHeaderRegex
        default:
            let escaped = NSRegularExpression.escapedPattern(for: name)
            regex = try? NSRegularExpression(pattern: "(?m)^\(escaped):\\s*(.+)", options: .caseInsensitive)
        }

        guard let regex,
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
