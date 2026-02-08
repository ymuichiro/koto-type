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
                Text("文字起こし履歴")
                    .font(.headline)
                Spacer()
                Button("更新") {
                    reload()
                }
                Button("すべて削除", role: .destructive) {
                    TranscriptionHistoryManager.shared.clear()
                    reload()
                }
            }

            TextField("履歴を検索", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("履歴はまだありません")
                        .foregroundColor(.secondary)
                    Text("録音または音声ファイル文字起こしの結果がここに保存されます")
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
                Button("閉じる") {
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
                Button("コピー") {
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
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}
