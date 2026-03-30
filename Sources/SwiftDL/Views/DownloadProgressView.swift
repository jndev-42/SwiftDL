import SwiftUI

struct DownloadProgressView: View {
    let item: DownloadItem
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.body)

                // Progress bar
                if item.status == .extracting || item.isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }

                // Info label
                HStack {
                    switch item.status {
                    case .extracting:
                        Text(item.statusDetail ?? "Fetching video info…")
                    case .merging:
                        Text(item.statusDetail ?? "Merging video + audio…")
                    case .failed(let msg):
                        if item.bytesReceived > 0 {
                            if item.isIndeterminate {
                                Text("\(item.bytesReceived.formattedFileSize) received")
                            } else {
                                Text("\(Int(item.progress * 100))% — \(item.bytesReceived.formattedFileSize) / \(item.totalBytes.formattedFileSize)")
                            }
                        }
                        Spacer()
                        Label(msg, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    default:
                        if item.isIndeterminate {
                            Text("\(item.bytesReceived.formattedFileSize) received")
                        } else {
                            Text("\(Int(item.progress * 100))% — \(item.bytesReceived.formattedFileSize) / \(item.totalBytes.formattedFileSize)")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel download")
        }
        .padding(.vertical, 4)
    }
}
