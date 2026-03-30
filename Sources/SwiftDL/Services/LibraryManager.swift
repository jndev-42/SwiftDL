import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class LibraryManager {
    var items: [LibraryItem] = []

    func scanFolder(_ url: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        items = contents.compactMap { fileURL -> LibraryItem? in
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }

            // Filter using the canonical constant — no hardcoded list here (Condition 8)
            let ext = "." + fileURL.pathExtension.lowercased()
            guard URLValidator.videoExtensions.contains(ext) else { return nil }

            return LibraryItem(
                fileName: fileURL.lastPathComponent,
                fileURL: fileURL,
                fileSize: Int64(values.fileSize ?? 0),
                dateModified: values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.dateModified > $1.dateModified }
    }

    func deleteItem(_ item: LibraryItem) {
        do {
            try FileManager.default.removeItem(at: item.fileURL)
            items.removeAll { $0.id == item.id }
        } catch {
            print("[LibraryManager] Delete failed for \(item.fileName): \(error.localizedDescription)")
        }
    }

    func openItem(_ item: LibraryItem) {
        NSWorkspace.shared.open(item.fileURL)
    }

    func showInFinder(_ item: LibraryItem) {
        NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: "")
    }
}
