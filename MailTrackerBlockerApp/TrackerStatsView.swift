import SwiftUI

struct TrackerStatsView: View {
    @State private var events: [TrackerEvent] = []
    @State private var domainCount: Int = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            summary
            Divider()
            eventList
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear { reload() }
    }

    // MARK: - Sections

    private var toolbar: some View {
        HStack {
            Text("Tracker Statistics")
                .font(.headline)
                .padding(.leading)
            Spacer()
            Button("Refresh") { reload() }
            Button("Clear") {
                SharedStorage.clearTrackerEvents()
                events = []
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }

    private var summary: some View {
        HStack(spacing: 32) {
            statTile(value: "\(events.count)", label: "Messages with trackers")
            statTile(value: "\(totalMatchedDomains)", label: "Total domain matches")
            statTile(value: "\(domainCount)", label: "Blocked domains loaded")
        }
        .padding()
    }

    private var eventList: some View {
        Group {
            if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No trackers detected yet")
                        .foregroundColor(.secondary)
                    Text("Mail.app will call the extension as new messages arrive.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(events) { event in
                    EventRow(event: event)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Helpers

    private var totalMatchedDomains: Int {
        events.reduce(0) { $0 + $1.matchedDomains.count }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 140)
    }

    private func reload() {
        events = SharedStorage.loadTrackerEvents()
        domainCount = SharedStorage.loadBlockedDomains().count
    }
}

// MARK: - EventRow

private struct EventRow: View {
    let event: TrackerEvent
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.subject)
                        .font(.headline)
                        .lineLimit(1)
                    Text(event.senderAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.detectedAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(event.matchedDomains.count) domain(s)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Button(expanded ? "Hide" : "Show") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(event.matchedDomains, id: \.self) { domain in
                        Label(domain, systemImage: "xmark.shield.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
