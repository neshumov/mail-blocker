import SwiftUI
import MailKit

struct ContentView: View {
    @State private var rulesText: String = ""
    @State private var rulesFilePath: String = ""
    @State private var stripDomain: Bool = false
    @State private var includeCSSDisplayNone: Bool = false
    @State private var pipelineResult: PipelineResult?
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?
    @State private var reloadStatus: String = ""
    @State private var showStats: Bool = false
    @State private var showTestEmails: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rulesInputSection
                Divider()
                settingsSection
                Divider()
                runSection
                if let result = pipelineResult {
                    Divider()
                    statsSection(result: result)
                }
                Divider()
                onboardingSection
                Divider()
                logSection
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 560)
        .sheet(isPresented: $showStats) {
            TrackerStatsView()
        }
        .sheet(isPresented: $showTestEmails) {
            TestEmailsView()
        }
    }

    // MARK: - Sections

    private var rulesInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rules Input", systemImage: "doc.text")
                .font(.headline)

            HStack {
                Text(rulesFilePath.isEmpty ? "No file loaded" : rulesFilePath)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Load filter.txt") { loadFilterFile() }
            }

            if !rulesText.isEmpty {
                TextEditor(text: $rulesText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.3))
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pipeline Settings", systemImage: "slider.horizontal.3")
                .font(.headline)
            Toggle("Strip $domain= modifier", isOn: $stripDomain)
                .help("Removes domain= option from rules — tests if-domain/unless-domain behaviour in Mail.app")
            Toggle("Include css-display-none rules", isOn: $includeCSSDisplayNone)
                .help("Passes cosmetic ##selector rules through the pipeline — tests CSS visibility in Mail.app")
        }
    }

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: executePipeline) {
                HStack {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Text(isRunning ? "Running…" : "Run Pipeline")
                }
            }
            .disabled(rulesText.isEmpty || isRunning)
            .buttonStyle(.borderedProminent)

            if !reloadStatus.isEmpty {
                Text(reloadStatus)
                    .foregroundColor(reloadStatus.contains("✓") ? .green : .secondary)
                    .font(.callout)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
            }
        }
    }

    private func statsSection(result: PipelineResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pipeline Stats", systemImage: "chart.bar")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                statRow(label: "Source rules:", value: "\(result.sourceRuleCount)")
                statRow(label: "Post pre-filter:", value: "\(result.postPreFilterCount)")
                statRow(
                    label: "Total entries:",
                    value: "\(result.finalJSONEntryCount) / 300,000",
                    valueColor: result.finalJSONEntryCount > 270_000 ? .orange : .primary
                )
                statRow(label: "Extension 1:", value: "\(result.primaryJSONEntryCount) / 150,000")
                statRow(label: "Extension 2:", value: "\(result.secondaryJSONEntryCount) / 150,000")
            }
            .font(.system(.body, design: .monospaced))

            ForEach(result.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.callout)
            }
        }
    }

    private func statRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundColor(.secondary).frame(width: 160, alignment: .leading)
            Text(value).foregroundColor(valueColor)
        }
    }

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Enable Extension", systemImage: "info.circle")
                .font(.headline)
            Text("Open Mail → Settings → Extensions → enable **Mail Tracker Blocker Extension** and **Mail Tracker Blocker Extension 2**, then run the pipeline.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logSection: some View {
        HStack {
            Label("Tools", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Spacer()
            Button("Test Emails") { showTestEmails = true }
            Button("Tracker Stats") { showStats = true }
        }
    }

    // MARK: - Actions

    private func loadFilterFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.title = "Select filter.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rulesFilePath = url.path
        rulesText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func executePipeline() {
        guard !rulesText.isEmpty else { return }
        isRunning = true
        errorMessage = nil
        reloadStatus = ""

        let capturedText = rulesText
        let capturedStrip = stripDomain
        let capturedCSS = includeCSSDisplayNone

        Task.detached(priority: .userInitiated) {
            do {
                let result = try runPipeline(
                    rulesText: capturedText,
                    stripDomain: capturedStrip,
                    includeCSSDisplayNone: capturedCSS
                )
                SharedStorage.saveRulesJSON(
                    primary: result.primaryJSONData,
                    secondary: result.secondaryJSONData
                )
                DebugLogger.log(
                    "Saved rules to App Group: ext1=\(result.primaryJSONData.count) bytes, ext2=\(result.secondaryJSONData?.count ?? 2) bytes"
                )

                await triggerExtensionReload()

                await MainActor.run {
                    pipelineResult = result
                    isRunning = false
                }
            } catch {
                DebugLogger.log("Pipeline error: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }

    @MainActor
    private func triggerExtensionReload() async {
        // MailKit does not expose a public reloadContentBlocker API equivalent to
        // SFContentBlockerManager. Rules are read by Mail on next evaluation.
        // Relaunch Mail.app to pick up changes immediately.
        reloadStatus = "✓ Rules saved — restart Mail.app to apply"
        DebugLogger.log("Rules written to App Group; user prompted to restart Mail.app")
    }
}
