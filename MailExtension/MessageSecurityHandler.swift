import MailKit

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {
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
        if RuntimeFlags.disableMessageSecurityHandler {
            return nil
        }

        let t0 = PerfClock.now()
        var stage: [String] = []
        func mark(_ name: String, _ started: PerfClock.Instant) {
            let ms = PerfClock.elapsedMs(since: started)
            stage.append("\(name)=\(ms)ms")
        }

        let tDomains = PerfClock.now()
        let blockedSet = SharedStorage.loadBlockedDomainsSet()
        mark("domains", tDomains)
        DebugLogger.log("decodedMessage invoked size=\(data.count) domains=\(blockedSet.count)")
        guard !blockedSet.isEmpty else { return nil }

        let tDecode = PerfClock.now()
        let rawText: String
        if let s = String(data: data, encoding: .utf8) {
            rawText = s
        } else if let s = String(data: data, encoding: .isoLatin1) {
            rawText = s
        } else {
            return nil
        }
        mark("decode", tDecode)

        let tHeaders = PerfClock.now()
        let headersText = String(headerSection(from: rawText))
        let senderAddress = extractLineHeader("from", from: headersText) ?? "unknown"
        let subject = extractLineHeader("subject", from: headersText) ?? "(no subject)"
        let messageID = extractLineHeader("message-id", from: headersText) ?? "\(senderAddress)-\(Date().timeIntervalSince1970)"
        mark("headers", tHeaders)

        // Fast path: if we have already detected this message before,
        // skip full body scan and return annotation immediately.
        let tCache = PerfClock.now()
        if let existing = SharedStorage.trackerEvent(messageID: messageID),
           !existing.matchedDomains.isEmpty {
            mark("eventCacheHit", tCache)
            let totalMs = PerfClock.elapsedMs(since: t0)
            if totalMs >= 80 {
                DebugLogger.log("decodedMessage cache-hit total=\(totalMs)ms size=\(data.count) id=\(messageID.prefix(40)) \(stage.joined(separator: " "))")
            }
            return makeDecodedMessage(
                data: data,
                matchedDomains: existing.matchedDomains
            )
        }
        mark("eventCacheMiss", tCache)

        let tLower = PerfClock.now()
        let bodyText = rawText.lowercased()
        mark("lowercase", tLower)

        let tMatch = PerfClock.now()
        let matchedDomains = findMatchedDomains(
            in: bodyText,
            blockedDomains: blockedSet,
            stageRecorder: { stage.append($0) }
        )
        mark("matchTotal", tMatch)
        guard !matchedDomains.isEmpty else {
            DebugLogger.log("decodedMessage no-match size=\(data.count) from=\(senderAddress.prefix(60)) \(stage.joined(separator: " "))")
            return nil
        }

        // We should still return security information/banner for this message
        // even if it was already recorded before (e.g. Mail re-opens/re-renders it).
        // Deduplication is only for persisted statistics events.
        let sorted = Array(matchedDomains).sorted()

        // Write event asynchronously — never block Mail's synchronous decode call
        let event = TrackerEvent(
            messageID: messageID,
            detectedAt: Date(),
            senderAddress: senderAddress,
            subject: subject,
            matchedDomains: sorted
        )
        DispatchQueue.global(qos: .utility).async {
            SharedStorage.appendTrackerEvent(event)
        }

        let totalMs = PerfClock.elapsedMs(since: t0)
        DebugLogger.log("decodedMessage \(totalMs)ms size=\(data.count) matches=\(sorted.count) \(stage.joined(separator: " "))")

        return makeDecodedMessage(data: data, matchedDomains: sorted)
    }

    private func makeDecodedMessage(data: Data, matchedDomains: [String]) -> MEDecodedMessage {
        let reason = "Possible tracker: \(matchedDomains.joined(separator: ", "))"
        let secInfo = MEMessageSecurityInformation(
            signers: [],
            isEncrypted: false,
            signingError: nil,
            encryptionError: nil,
            shouldBlockRemoteContent: true,
            localizedRemoteContentBlockingReason: reason
        )
        return MEDecodedMessage(
            data: data,
            securityInformation: secInfo,
            context: nil,
            banner: nil
        )
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

    private func findMatchedDomains(
        in text: String,
        blockedDomains: Set<String>,
        stageRecorder: ((String) -> Void)? = nil
    ) -> Set<String> {
        let blockedSet = blockedDomains
        stageRecorder?("blockedSet=0ms")

        let tExtract = PerfClock.now()
        let candidateHosts = extractCandidateHosts(from: text)
        stageRecorder?("extractHosts=\(PerfClock.elapsedMs(since: tExtract))ms")

        let tSuffix = PerfClock.now()
        var matched: Set<String> = []

        for host in candidateHosts {
            if blockedSet.contains(host) {
                matched.insert(host)
            }

            var dotIndex = host.firstIndex(of: ".")
            while let dot = dotIndex {
                let next = host.index(after: dot)
                if next < host.endIndex {
                    let suffix = String(host[next...])
                    if blockedSet.contains(suffix) {
                        matched.insert(suffix)
                    }
                    dotIndex = host[next...].firstIndex(of: ".")
                } else {
                    break
                }
            }
        }
        stageRecorder?("suffixMatch=\(PerfClock.elapsedMs(since: tSuffix))ms hosts=\(candidateHosts.count)")

        // Fast second pass for encoded URLs like https%3a%2f%2fhost%2epath
        if matched.isEmpty && text.contains("%2") {
            let tDecodePass = PerfClock.now()
            let decodedLike = text
                .replacingOccurrences(of: "%2e", with: ".")
                .replacingOccurrences(of: "%2f", with: "/")
                .replacingOccurrences(of: "%3a", with: ":")
            let decodedHosts = extractCandidateHosts(from: decodedLike)
            for host in decodedHosts {
                if blockedSet.contains(host) {
                    matched.insert(host)
                }
                var dotIndex = host.firstIndex(of: ".")
                while let dot = dotIndex {
                    let next = host.index(after: dot)
                    if next < host.endIndex {
                        let suffix = String(host[next...])
                        if blockedSet.contains(suffix) {
                            matched.insert(suffix)
                        }
                        dotIndex = host[next...].firstIndex(of: ".")
                    } else {
                        break
                    }
                }
            }
            stageRecorder?("encodedPass=\(PerfClock.elapsedMs(since: tDecodePass))ms hosts=\(decodedHosts.count)")
        }

        return matched
    }

    private func extractCandidateHosts(from text: String) -> Set<String> {
        var hosts: Set<String> = []
        hosts.reserveCapacity(256)

        var tokenStart: String.Index?
        var tokenLen = 0
        var hasDot = false

        @inline(__always)
        func isHostChar(_ ch: Character) -> Bool {
            switch ch {
            case "a"..."z", "0"..."9", ".", "-", "_":
                return true
            default:
                return false
            }
        }

        func flushToken(until end: String.Index) {
            guard let start = tokenStart else { return }
            defer {
                tokenStart = nil
                tokenLen = 0
                hasDot = false
            }
            guard hasDot, tokenLen >= 4, tokenLen <= 253 else { return }

            var host = String(text[start..<end])
            while host.first == "." { host.removeFirst() }
            while host.last == "." { host.removeLast() }
            guard !host.isEmpty, host.contains(".") else { return }
            hosts.insert(host)
        }

        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if isHostChar(ch) {
                if tokenStart == nil {
                    tokenStart = idx
                    tokenLen = 0
                    hasDot = false
                }
                tokenLen += 1
                if ch == "." { hasDot = true }
            } else {
                flushToken(until: idx)
            }
            idx = text.index(after: idx)
        }
        flushToken(until: text.endIndex)

        return hosts
    }

    private func headerSection(from raw: String) -> Substring {
        if let range = raw.range(of: "\r\n\r\n") {
            return raw[..<range.lowerBound]
        }
        if let range = raw.range(of: "\n\n") {
            return raw[..<range.lowerBound]
        }
        return raw[raw.startIndex..<raw.endIndex]
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
