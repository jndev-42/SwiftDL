import SwiftUI

struct ContentView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(LibraryManager.self) private var libraryManager

    @State private var showSettings = false
    @State private var showFirstLaunchSheet = false

    var body: some View {
        VStack(spacing: 0) {
            DownloadInputView()

            Divider()

            ActiveDownloadsView()
                .frame(minHeight: 100, maxHeight: 240)

            Divider()

            LibraryListView()
                .frame(minHeight: 150)
        }
        .frame(minWidth: 600, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(settings)
        }
        .sheet(isPresented: $showFirstLaunchSheet) {
            firstLaunchSheet
        }
        .task {
            // First-launch: prompt folder selection if none configured
            if settings.downloadFolderURL == nil {
                showFirstLaunchSheet = true
            }
        }
        .onAppear {
            // Ensure window is key when first shown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            // Initial library scan on launch
            if let folder = settings.downloadFolderURL {
                libraryManager.scanFolder(folder)
            }
        }
        .onChange(of: downloadManager.downloads.map(\.status)) {
            // Refresh library after any download completes
            let hasNewCompletion = downloadManager.downloads.contains { $0.status == .completed }
            if hasNewCompletion, let folder = settings.downloadFolderURL {
                libraryManager.scanFolder(folder)
            }
        }
        // App lifecycle: cleanup on termination (Condition 3 + Step 6)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            downloadManager.cancelAllDownloads()
            settings.stopAccess()
        }
    }

    private var firstLaunchSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to SwiftDL")
                .font(.title2.bold())

            Text("Choose a folder where your downloads will be saved.\nYou can change this later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                settings.pickFolder()
                if settings.downloadFolderURL != nil {
                    showFirstLaunchSheet = false
                    if let folder = settings.downloadFolderURL {
                        libraryManager.scanFolder(folder)
                    }
                }
            } label: {
                Label("Choose Download Folder", systemImage: "folder.badge.plus")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip for now") {
                showFirstLaunchSheet = false
            }
            .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 380)
    }
}
