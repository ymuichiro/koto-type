import SwiftUI

struct ThirdPartyLicensesView: View {
    @Binding var isPresented: Bool
    @State private var notices: [ThirdPartyNotice] = []
    @State private var selectedNoticeID: String?
    @State private var selectedNoticeText = ""
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open-source licenses")
                .font(.headline)

            if let loadError {
                Text(loadError)
                    .foregroundColor(.red)
            } else {
                HStack(spacing: 16) {
                    List(notices, selection: $selectedNoticeID) { notice in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.name)
                            Text(notice.licenseName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 220)

                    VStack(alignment: .leading, spacing: 10) {
                        if let selectedNotice = notices.first(where: { $0.id == selectedNoticeID }) {
                            Text(selectedNotice.name)
                                .font(.title3)
                            Text(selectedNotice.licenseName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if let bundledComponent = selectedNotice.bundledComponent {
                                Text("Bundled component: \(bundledComponent)")
                                    .font(.caption)
                            }
                            if let revision = selectedNotice.revision {
                                Text("Pinned revision: \(revision)")
                                    .font(.caption)
                            }
                            if let upstreamBaseModel = selectedNotice.upstreamBaseModel {
                                Text("Upstream base model: \(upstreamBaseModel)")
                                    .font(.caption)
                            }
                            if let summary = selectedNotice.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let projectURL = URL(string: selectedNotice.projectURL) {
                                Link("Open project page", destination: projectURL)
                            }

                            Divider()

                            ScrollView {
                                Text(selectedNoticeText)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Spacer()
                            Text("Select a component to view its license.")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
        .task {
            loadNoticesIfNeeded()
        }
        .onChange(of: selectedNoticeID) { _ in
            loadSelectedNoticeText()
        }
    }

    private func loadNoticesIfNeeded() {
        guard notices.isEmpty else { return }
        do {
            notices = try ThirdPartyNoticesLoader.load()
            selectedNoticeID = notices.first?.id
            loadSelectedNoticeText()
        } catch {
            loadError = "Failed to load open-source notices: \(error.localizedDescription)"
        }
    }

    private func loadSelectedNoticeText() {
        guard let selectedNoticeID,
            let selectedNotice = notices.first(where: { $0.id == selectedNoticeID })
        else {
            selectedNoticeText = ""
            return
        }

        do {
            selectedNoticeText = try ThirdPartyNoticesLoader.noticeText(for: selectedNotice)
        } catch {
            selectedNoticeText = "Failed to load license text: \(error.localizedDescription)"
        }
    }
}
