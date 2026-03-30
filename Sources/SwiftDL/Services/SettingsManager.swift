import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class SettingsManager {
    private(set) var downloadFolderURL: URL?
    private var currentAccessedURL: URL?

    private let bookmarkKey = "downloadFolderBookmark"

    init() {
        resolveBookmark()
    }

    // MARK: - Public API

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose where swiftdl will save downloaded files."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Stop access to previous folder before starting on the new one (Condition 3)
        stopAccess()

        if url.startAccessingSecurityScopedResource() {
            currentAccessedURL = url
        }
        downloadFolderURL = url
        saveBookmark(for: url)
    }

    /// Call on app termination to release the security-scoped resource. (Condition 3)
    func stopAccess() {
        currentAccessedURL?.stopAccessingSecurityScopedResource()
        currentAccessedURL = nil
    }

    // MARK: - Private

    private func resolveBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Attempt to refresh the stale bookmark before continuing (Security fix)
                saveBookmark(for: url)
            }
            if url.startAccessingSecurityScopedResource() {
                currentAccessedURL = url
                downloadFolderURL = url
            }
        } catch {
            print("[SettingsManager] Failed to resolve bookmark: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            print("[SettingsManager] Failed to save bookmark: \(error.localizedDescription)")
        }
    }
}
