import AppKit
import SwiftUI

struct HistoryView: View {
    @State private var entries: [TranscriptionHistoryEntry] = []
    @State private var searchText = ""

    let onClose: () -> Void

    private var filteredEntries: [TranscriptionHistoryEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription History")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    reload()
                }
                Button("Clear All", role: .destructive) {
                    TranscriptionHistoryManager.shared.clear()
                    reload()
                }
            }

            TextField("Search history", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No history yet")
                        .foregroundColor(.secondary)
                    Text("Results from live recording or imported audio transcription are saved here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            HistoryRowView(entry: entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            reload()
        }
    }

    private func reload() {
        entries = TranscriptionHistoryManager.shared.loadEntries()
    }
}

private struct HistoryRowView: View {
    let entry: TranscriptionHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.dateFormatter.string(from: entry.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.source.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
                .buttonStyle(.bordered)
            }

            if let path = entry.audioFilePath, !path.isEmpty {
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text(entry.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}
