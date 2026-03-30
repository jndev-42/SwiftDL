import SwiftUI

struct DownloadInputView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SettingsManager.self) private var settings

    @State private var urlString = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Paste download URL here…", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { startDownload() }
                    .onAppear {
                        // Small delay ensures the window is ready for focus transitions
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }

                Button {
                    startDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .padding()
        .animation(.default, value: errorMessage)
    }

    private func startDownload() {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard let url = URLValidator.url(from: trimmed) else {
            errorMessage = "Invalid URL. Please enter a valid HTTP or HTTPS link."
            return
        }

        guard let folder = settings.downloadFolderURL else {
            errorMessage = "No download folder selected. Open Settings (⌘,) to choose one."
            return
        }

        errorMessage = nil
        urlString = ""
        if URLValidator.isYouTubeURL(trimmed) {
            downloadManager.startYouTubeDownload(from: url, to: folder)
        } else {
            downloadManager.startDownload(from: url, to: folder)
        }
    }
}
