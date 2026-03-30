import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.bold())

            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: settings.downloadFolderURL != nil ? "folder.fill" : "folder.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(settings.downloadFolderURL != nil ? Color.accentColor : .secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download Folder")
                            .font(.headline)
                        if let url = settings.downloadFolderURL {
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No folder selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Choose…") {
                        settings.pickFolder()
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 200)
    }
}
