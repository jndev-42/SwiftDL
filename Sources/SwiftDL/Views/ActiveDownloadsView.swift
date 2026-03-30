import SwiftUI

struct ActiveDownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager

    private var activeItems: [DownloadItem] {
        downloadManager.downloads.filter {
            $0.status != .completed && $0.status != .cancelled
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            Divider()

            if activeItems.isEmpty {
                ContentUnavailableView(
                    "No Active Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Paste a URL above to start downloading")
                )
                .frame(minHeight: 80)
            } else {
                List(activeItems) { item in
                    DownloadProgressView(item: item) {
                        downloadManager.cancelDownload(item)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Label("Active Downloads", systemImage: "arrow.down.circle")
                .font(.headline)
            Spacer()
            if !activeItems.isEmpty {
                Text("\(activeItems.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2), in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 8)
    }
}
