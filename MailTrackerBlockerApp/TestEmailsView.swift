import SwiftUI

struct TestEmailsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var openedScenario: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(TestEmailGenerator.all, id: \.scenario) { email in
                        TestEmailRow(email: email, openedScenario: $openedScenario)
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    private var toolbar: some View {
        HStack {
            Text("Test Emails")
                .font(.headline)
                .padding(.leading)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("MEContentBlocker: open EML → view in Mail → check Proxyman for blocked requests.", systemImage: "shield")
            Label("MEMessageActionHandler: only fires for received messages — send EML to yourself via SMTP.", systemImage: "envelope")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(10)
    }
}

// MARK: - TestEmailRow

private struct TestEmailRow: View {
    let email: TestEmail
    @Binding var openedScenario: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Scenario badge
            Text(email.scenario)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .cornerRadius(6)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(email.subject)
                    .font(.headline)
                Text(email.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("From: \(email.fromAddress)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 6) {
                Button("Open in Mail") { openInMail(email) }
                    .buttonStyle(.borderedProminent)
                    .help("Opens EML in Mail viewer — tests MEContentBlocker (Proxyman)")
                Button("Add to Inbox") { addToInbox(email) }
                    .buttonStyle(.bordered)
                    .help("Creates message directly in Mail Inbox via AppleScript — tests MEMessageActionHandler (Tracker Stats)")
                if openedScenario == email.scenario {
                    Label("Done", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .frame(width: 120)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func openInMail(_ email: TestEmail) {
        guard let url = TestEmailGenerator.writeToTempFile(email) else { return }
        NSWorkspace.shared.open(url)
        openedScenario = email.scenario
    }

    private func addToInbox(_ email: TestEmail) {
        let subject = email.subject.replacingOccurrences(of: "\"", with: "'")
        let sender  = email.fromAddress.replacingOccurrences(of: "\"", with: "'")
        // Strip HTML tags for plain-text AppleScript content
        let plain   = email.htmlBody
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let script = """
        tell application "Mail"
            activate
            set theAccount to first account
            set theMailbox to inbox of theAccount
            set newMsg to make new message at beginning of theMailbox ¬
                with properties {subject:"\(subject)", content:"\(plain)", ¬
                read status:false, sender:"\(sender)"}
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        if error != nil {
            // AppleScript failed — fall back to opening in Finder
            guard let url = TestEmailGenerator.writeToTempFile(email) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        openedScenario = email.scenario
    }
}
