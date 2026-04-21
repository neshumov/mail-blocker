import Foundation
import AppKit

struct TestEmail {
    let scenario: String
    let subject: String
    let description: String
    let fromAddress: String
    let htmlBody: String
    let contentType: String
    let plainBody: String?

    init(
        scenario: String,
        subject: String,
        description: String,
        fromAddress: String,
        htmlBody: String,
        contentType: String = "text/html; charset=UTF-8",
        plainBody: String? = nil
    ) {
        self.scenario = scenario
        self.subject = subject
        self.description = description
        self.fromAddress = fromAddress
        self.htmlBody = htmlBody
        self.contentType = contentType
        self.plainBody = plainBody
    }

    var emlContent: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let dateStr = formatter.string(from: Date())
        let body = plainBody ?? htmlBody
        return """
        From: \(fromAddress)
        To: me@localhost
        Subject: [MTB Test] \(subject)
        Date: \(dateStr)
        Message-ID: <mtb-test-\(scenario)@localhost>
        MIME-Version: 1.0
        Content-Type: \(contentType)
        X-MTB-Scenario: \(scenario)

        \(body)
        """
    }
}

enum TestEmailGenerator {

    static let all: [TestEmail] = [
        scenario1_basicBlocking,
        scenario2a_domainScoped,
        scenario2b_domainStripped,
        scenario3_cssDisplayNone,
        scenario4_realWorld,
        scenario5_clean,
        scenario6_spywareText_ru,
        scenario7_spywareText_global,
        scenario8_spywareText_mixed,
    ]

    // MARK: - Scenario 1: Basic blocking
    // Rules: ||mtb-test-block.example^ ||pixel.mtb-test.example^ etc.
    // Expected: all 4 img requests blocked → nothing loads

    static let scenario1_basicBlocking = TestEmail(
        scenario: "1",
        subject: "Scenario 1 — Basic Blocking",
        description: """
        Rules loaded: ||mtb-test-block.example^ and friends.
        Expected: все 4 запроса заблокированы.
        Проверка: открой письмо → в Proxyman 4 запроса должны отобразиться как заблокированные (или отсутствовать).
        """,
        fromAddress: "sender@any.example",
        htmlBody: """
        <html><body style="font-family:sans-serif;padding:16px">
        <h3>Scenario 1 — Basic Blocking</h3>
        <p>This email contains 4 tracking pixels. All should be blocked by MEContentBlocker.</p>
        <table>
          <tr><td>Pixel 1 (mtb-test-block.example):</td>
              <td><img src="https://mtb-test-block.example/open.gif" width="1" height="1" alt="[pixel1]"></td></tr>
          <tr><td>Pixel 2 (pixel.mtb-test.example):</td>
              <td><img src="https://pixel.mtb-test.example/t.gif" width="1" height="1" alt="[pixel2]"></td></tr>
          <tr><td>Pixel 3 (open.mtb-test.example):</td>
              <td><img src="https://open.mtb-test.example/r.gif" width="1" height="1" alt="[pixel3]"></td></tr>
          <tr><td>Pixel 4 (beacon.mtb-test.example):</td>
              <td><img src="https://beacon.mtb-test.example/b.gif" width="1" height="1" alt="[pixel4]"></td></tr>
        </table>
        <p style="color:gray;font-size:12px">If blocking works, the alt text [pixel1]–[pixel4] will NOT be visible (images fail to load).</p>
        </body></html>
        """
    )

    // MARK: - Scenario 2a: domain-scoped rule, Strip $domain = OFF
    // Rule: ||mtb-test-scoped.example^$domain=sender.mtb-test.example
    // Run pipeline with Strip $domain = OFF before opening this email.

    static let scenario2a_domainScoped = TestEmail(
        scenario: "2a",
        subject: "Scenario 2a — if-domain (Strip OFF)",
        description: """
        Правило: ||mtb-test-scoped.example^$domain=sender.mtb-test.example
        Запусти pipeline с "Strip $domain = OFF".
        Ожидание A (if-domain работает): пиксель заблокирован.
        Ожидание B (документ всегда about:blank): пиксель НЕ заблокирован.
        """,
        fromAddress: "news@sender.mtb-test.example",
        htmlBody: """
        <html><body style="font-family:sans-serif;padding:16px">
        <h3>Scenario 2a — if-domain (Strip $domain = OFF)</h3>
        <p>Sender domain: <b>sender.mtb-test.example</b></p>
        <p>Rule: <code>||mtb-test-scoped.example^$domain=sender.mtb-test.example</code></p>
        <p>Tracker pixel:</p>
        <img src="https://mtb-test-scoped.example/open.gif" width="1" height="1" alt="[scoped-pixel]">
        <p>If <b>blocked</b>: if-domain works in Mail.app → strip $domain is NOT needed.<br>
           If <b>not blocked</b>: Mail renders as about:blank → strip $domain IS needed.</p>
        </body></html>
        """
    )

    // MARK: - Scenario 2b: universal rule, Strip $domain = ON
    // Same pixel, but run pipeline with Strip $domain = ON first.

    static let scenario2b_domainStripped = TestEmail(
        scenario: "2b",
        subject: "Scenario 2b — if-domain (Strip ON)",
        description: """
        Те же правила, но запусти pipeline с "Strip $domain = ON".
        Правило становится универсальным: ||mtb-test-scoped.example^
        Ожидание: пиксель заблокирован независимо от домена документа.
        """,
        fromAddress: "news@sender.mtb-test.example",
        htmlBody: """
        <html><body style="font-family:sans-serif;padding:16px">
        <h3>Scenario 2b — if-domain (Strip $domain = ON)</h3>
        <p>Same pixel as 2a, but rule has no $domain restriction after stripping.</p>
        <img src="https://mtb-test-scoped.example/open.gif" width="1" height="1" alt="[scoped-pixel]">
        <p>Expected: <b>always blocked</b>.</p>
        </body></html>
        """
    )

    // MARK: - Scenario 3: css-display-none
    // Rules: mtb-test-css.example##img[data-tracker="true"]
    //        mtb-test-css.example##img[width="1"][height="1"]
    // Run pipeline with "Include css-display-none" ON.

    static let scenario3_cssDisplayNone = TestEmail(
        scenario: "3",
        subject: "Scenario 3 — css-display-none",
        description: """
        Включи "Include css-display-none rules" и запусти pipeline.
        Правила: mtb-test-css.example##img[width="1"][height="1"]
        Открой Accessibility Inspector → найди img → проверь display:none.
        """,
        fromAddress: "promo@mtb-test-css.example",
        htmlBody: """
        <html><body style="font-family:sans-serif;padding:16px">
        <h3>Scenario 3 — css-display-none</h3>
        <p style="color:green">▼ Tracking pixel below (should be hidden if css-display-none works)</p>
        <img width="1" height="1" src="https://mtb-test-css.example/track.gif"
             data-tracker="true" id="test-pixel" alt="[css-pixel]">
        <p style="color:green">▲ Tracking pixel above</p>
        <p>Check with <b>Accessibility Inspector</b>: select the img#test-pixel element.<br>
           If css-display-none works → element is hidden.<br>
           If not → element is visible (1×1 px, nearly invisible).</p>
        <p>Note: the network request may still go out — css-display-none only hides, not blocks.</p>
        </body></html>
        """
    )

    // MARK: - Scenario 4: Real-world known trackers

    static let scenario4_realWorld = TestEmail(
        scenario: "4",
        subject: "Scenario 4 — Real-world Trackers",
        description: """
        Домены: track.mailerlite.com, trk.mailchimp.com, justtrack.io,
        pixel.visitiq.io, tracker.zmaticoo.com — все есть в filter.txt.
        Ожидание: все 5 запросов заблокированы.
        """,
        fromAddress: "marketing@shop.example.com",
        htmlBody: """
        <html><body style="font-family:sans-serif;padding:16px">
        <h3>Scenario 4 — Real-world Trackers</h3>
        <table>
          <tr><td>track.mailerlite.com:</td>
              <td><img src="https://track.mailerlite.com/e1/o/test" width="1" height="1" alt="[mailerlite]"></td></tr>
          <tr><td>trk.mailchimp.com:</td>
              <td><img src="https://trk.mailchimp.com/open?u=test" width="1" height="1" alt="[mailchimp]"></td></tr>
          <tr><td>justtrack.io:</td>
              <td><img src="https://justtrack.io/pixel.gif" width="1" height="1" alt="[justtrack]"></td></tr>
          <tr><td>pixel.visitiq.io:</td>
              <td><img src="https://pixel.visitiq.io/t.gif" width="1" height="1" alt="[visitiq]"></td></tr>
          <tr><td>tracker.zmaticoo.com:</td>
              <td><img src="https://tracker.zmaticoo.com/open.gif" width="1" height="1" alt="[zmaticoo]"></td></tr>
        </table>
        </body></html>
        """
    )

    // MARK: - Scenario 5: Clean email (control)

    static let scenario5_clean = TestEmail(
        scenario: "5",
        subject: "Scenario 5 — Clean Email (Control)",
        description: """
        Нет правил для clean.mtb-test.example.
        Ожидание: 0 заблокированных запросов, 0 в Tracker Stats.
        Используй как baseline — если здесь что-то блокируется, это false positive.
        """,
        fromAddress: "friend@clean.mtb-test.example",
        htmlBody: """
        <html><body style="font-family:sans-serif;padding:16px">
        <h3>Scenario 5 — Clean Email (Control)</h3>
        <p>This email has no tracking pixels. No requests should be blocked.</p>
        <img src="https://clean.mtb-test.example/logo.png" width="200" height="60" alt="Logo">
        <p style="color:gray">If anything is blocked in this email → false positive in rules.</p>
        </body></html>
        """
    )

    // MARK: - Scenario 6-8: Plain text emails with real filter_3_Spyware trackers

    static let scenario6_spywareText_ru = TestEmail(
        scenario: "6",
        subject: "Scenario 6 — Spyware Text (RU trackers)",
        description: """
        Plain text письмо (text/plain) с URL из filter_3_Spyware:
        click.sender.yandex.ru/px, feedback.send.yandex.ru/px, api.peeper.plus.yandex.net/v1/p,
        read.sendsay.ru, wstat.ozon.ru.
        """,
        fromAddress: "newsletter@retail.example",
        htmlBody: "",
        contentType: "text/plain; charset=UTF-8",
        plainBody: """
        Scenario 6 (plain text)
        If detection works, this message should be marked as possible tracker.

        https://click.sender.yandex.ru/px/open.gif?mid=1001
        https://feedback.send.yandex.ru/px/open.gif?mid=1001
        https://api.peeper.plus.yandex.net/v1/p/abc123.gif
        https://read.sendsay.ru/open/track.gif?id=42
        https://wstat.ozon.ru/pixel.gif?uid=777
        """
    )

    static let scenario7_spywareText_global = TestEmail(
        scenario: "7",
        subject: "Scenario 7 — Spyware Text (Global vendors)",
        description: """
        Plain text письмо (text/plain) с глобальными трекерами из filter_3_Spyware:
        track.customer.io, ct.sendgrid.net, api.iterable.com,
        static-tracking.klaviyo.com, telemetrics.klaviyo.com.
        """,
        fromAddress: "marketing@global.example",
        htmlBody: "",
        contentType: "text/plain; charset=UTF-8",
        plainBody: """
        Scenario 7 (plain text)
        URL list for blocked spyware trackers:

        https://track.customer.io/e/o/xyz
        https://ct.sendgrid.net/wf/open?upn=test
        https://api.iterable.com/api/email/open?id=abc
        https://static-tracking.klaviyo.com/pixel.gif?m=1
        https://telemetrics.klaviyo.com/collect/open?id=2
        """
    )

    static let scenario8_spywareText_mixed = TestEmail(
        scenario: "8",
        subject: "Scenario 8 — Spyware Text (Encoded + mixed)",
        description: """
        Plain text письмо с mixed/encoded трекерами из spyware-паттернов.
        Проверяет, что детект цепляет и обычные, и URL-encoded варианты.
        """,
        fromAddress: "batch@notifications.example",
        htmlBody: "",
        contentType: "text/plain; charset=UTF-8",
        plainBody: """
        Scenario 8 (plain text)
        Normal:
        https://click.sender.yandex.ru/px/p.gif
        https://github.com/notifications/beacon/abc.gif

        Encoded:
        https%3A%2F%2Ffeedback.send.yandex.ru%2Fpx%2Fopen.gif
        https%3A%2F%2Fapi.peeper.plus.yandex.net%2Fv1%2Fp%2Fid.gif
        """
    )

    // MARK: - File I/O

    static func writeToTempFile(_ email: TestEmail) -> URL? {
        let fileName = "mtb-test-\(email.scenario).eml"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        guard (try? email.emlContent.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }
}
