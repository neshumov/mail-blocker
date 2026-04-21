import SwiftUI

struct DebugLogView: View {
    @State private var logContent: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent.isEmpty ? "Log is empty." : logContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                }
                .onAppear {
                    logContent = SharedStorage.readLog()
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private var toolbar: some View {
        HStack {
            Text("Debug Log")
                .font(.headline)
                .padding(.leading)
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logContent, forType: .string)
            }
            Button("Clear") {
                SharedStorage.clearLog()
                logContent = ""
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }
}
