import MailKit

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {

    // MARK: - MEMessageDecoder

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        let domains = SharedStorage.loadBlockedDomains()
        guard !domains.isEmpty else { return nil }

        let bodyText: String
        if let s = String(data: data, encoding: .utf8) {
            bodyText = s.lowercased()
        } else if let s = String(data: data, encoding: .isoLatin1) {
            bodyText = s.lowercased()
        } else {
            return nil
        }

        var matchedDomains: Set<String> = []
        for domain in domains where bodyText.contains(domain) {
            matchedDomains.insert(domain)
        }

        guard !matchedDomains.isEmpty else { return nil }

        // Extract headers from raw RFC-822 data (use original case for display)
        let rawText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let senderAddress = extractLineHeader("from", from: rawText) ?? "unknown"
        let subject = extractLineHeader("subject", from: rawText) ?? "(no subject)"
        let messageID = extractLineHeader("message-id", from: rawText) ?? "\(senderAddress)-\(Date().timeIntervalSince1970)"

        // We should still return security information/banner for this message
        // even if it was already recorded before (e.g. Mail re-opens/re-renders it).
        // Deduplication is only for persisted statistics events.
        let existingEvents = SharedStorage.loadTrackerEvents()
        let isAlreadyRecorded = existingEvents.contains(where: { $0.messageID == messageID })

        let event = TrackerEvent(
            messageID: messageID,
            detectedAt: Date(),
            senderAddress: senderAddress,
            subject: subject,
            matchedDomains: matchedDomains.sorted()
        )
        if !isAlreadyRecorded {
            SharedStorage.appendTrackerEvent(event)
            DebugLogger.log("Tracker decoded: '\(subject)' → \(matchedDomains.sorted().joined(separator: ", "))")
        } else {
            DebugLogger.log("Tracker re-detected (already recorded): '\(subject)'")
        }

        let reason = "Possible tracker: \(matchedDomains.sorted().joined(separator: ", "))"
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

    // Matches "Header-Name: value" only at the start of a line (avoids DKIM h= fields)
    private func extractLineHeader(_ name: String, from raw: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?m)^\(escaped):\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
