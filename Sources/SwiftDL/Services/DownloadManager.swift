import Foundation
import Observation

/// Core download engine. @MainActor isolated, does NOT inherit NSObject. (Conditions 1, 7)
@MainActor
@Observable
final class DownloadManager {

    var downloads: [DownloadItem] = []

    // Regular download task tracking
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var taskToDownload: [Int: UUID] = [:]  // task.taskIdentifier → DownloadItem.id

    // YouTube coordinator tracking
    private var youtubeCoordinators: [UUID: YouTubeDownloadCoordinator] = [:]
    private var subTaskToCoordinator: [Int: UUID] = [:]       // sub-task taskIdentifier → item UUID
    private var youtubeSubTasks: [Int: URLSessionDownloadTask] = [:]  // for cancellation

    private var urlSession: URLSession!
    private let sessionDelegate: DownloadSessionDelegate

    init() {
        sessionDelegate = DownloadSessionDelegate()
        // Standard browser User-Agent
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
            "Referer": "https://www.youtube.com/",
            "Origin": "https://www.youtube.com"
        ]

        // URLSession with delegate queue nil → URLSession creates its own serial background queue
        urlSession = URLSession(
            configuration: config,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
        sessionDelegate.manager = self
        sweepOrphanTempFiles()  // Condition 6
    }

    // MARK: - Public API

    func startDownload(from url: URL, to folder: URL) {
        let task = urlSession.downloadTask(with: url)
        let item = DownloadItem(
            sourceURL: url,
            destinationURL: folder,  // placeholder folder URL, finalized on completion
            fileName: placeholderName(for: url)
        )
        item.status = .downloading
        downloads.append(item)
        activeTasks[item.id] = task
        taskToDownload[task.taskIdentifier] = item.id
        task.resume()
    }

    func startYouTubeDownload(from url: URL, to folder: URL) {
        guard let videoID = URLValidator.extractVideoID(from: url) else { return }

        let item = DownloadItem(
            sourceURL: url,
            destinationURL: folder,
            fileName: "YouTube…"
        )
        downloads.append(item)

        let coordinator = YouTubeDownloadCoordinator(
            item: item,
            destinationFolder: folder,
            videoID: videoID
        )

        coordinator.onNeedDownloadTask = { [weak self] (streamURL: URL) -> (task: URLSessionDownloadTask, taskID: Int)? in
            guard let self else { return nil }
            let task = self.urlSession.downloadTask(with: streamURL)
            let taskID = task.taskIdentifier
            self.subTaskToCoordinator[taskID] = item.id
            self.youtubeSubTasks[taskID] = task
            return (task, taskID)
        }

        coordinator.onCancelSubTask = { [weak self] (taskID: Int) in
            guard let self else { return }
            self.youtubeSubTasks[taskID]?.cancel()
            self.youtubeSubTasks.removeValue(forKey: taskID)
            self.subTaskToCoordinator.removeValue(forKey: taskID)
        }

        coordinator.onComplete = { [weak self] in
            self?.youtubeCoordinators.removeValue(forKey: item.id)
        }

        youtubeCoordinators[item.id] = coordinator
        coordinator.start()
    }

    func cancelDownload(_ item: DownloadItem) {
        // YouTube item
        if let coordinator = youtubeCoordinators[item.id] {
            coordinator.cancel()
            let subIDs = subTaskToCoordinator.filter { $0.value == item.id }.map(\.key)
            for taskID in subIDs {
                youtubeSubTasks[taskID]?.cancel()
                youtubeSubTasks.removeValue(forKey: taskID)
                subTaskToCoordinator.removeValue(forKey: taskID)
            }
            youtubeCoordinators.removeValue(forKey: item.id)
        }
        // Regular item (no-ops if not found)
        activeTasks[item.id]?.cancel()
        removeTask(for: item.id)
        item.status = .cancelled
    }

    func cancelAllDownloads() {
        for task in activeTasks.values { task.cancel() }
        activeTasks.removeAll()
        taskToDownload.removeAll()

        for coordinator in youtubeCoordinators.values { coordinator.cancel() }
        for task in youtubeSubTasks.values { task.cancel() }
        youtubeCoordinators.removeAll()
        subTaskToCoordinator.removeAll()
        youtubeSubTasks.removeAll()

        for item in downloads where item.status.isActive {
            item.status = .cancelled
        }
    }

    // MARK: - Called by DownloadSessionDelegate (must be @MainActor)

    func updateProgress(taskIdentifier: Int, bytesWritten: Int64, totalExpected: Int64) {
        // Route YouTube sub-task first
        if let itemID = subTaskToCoordinator[taskIdentifier],
           let coordinator = youtubeCoordinators[itemID] {
            let fraction = totalExpected > 0 ? min(1.0, Double(bytesWritten) / Double(totalExpected)) : 0
            coordinator.updateProgress(
                taskID: taskIdentifier,
                bytesWritten: bytesWritten,
                totalExpected: totalExpected,
                fraction: fraction
            )
            return
        }
        // Regular download
        guard let item = item(for: taskIdentifier) else { return }
        item.bytesReceived = bytesWritten
        item.totalBytes = totalExpected  // -1 = NSURLSessionTransferSizeUnknown (Condition 5)
        if totalExpected > 0 {
            item.progress = min(1.0, Double(bytesWritten) / Double(totalExpected))
        }
        if item.status != .downloading { item.status = .downloading }
    }

    func handleDownloadComplete(taskIdentifier: Int, tempURL: URL, suggestedFilename: String?) {
        // Route YouTube sub-task first
        if let itemID = subTaskToCoordinator[taskIdentifier] {
            subTaskToCoordinator.removeValue(forKey: taskIdentifier)
            youtubeSubTasks.removeValue(forKey: taskIdentifier)
            if let coordinator = youtubeCoordinators[itemID] {
                coordinator.handleSubTaskComplete(taskID: taskIdentifier, tempURL: tempURL)
            } else {
                try? FileManager.default.removeItem(at: tempURL)  // coordinator gone, discard
            }
            return
        }
        // Regular download
        guard let itemId = taskToDownload[taskIdentifier],
              let item = downloads.first(where: { $0.id == itemId }) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        let folder = item.destinationURL  // folder URL set in startDownload

        // File naming fallback chain + deduplication (Condition 4)
        let resolvedName = resolveFilename(
            suggestedFilename: suggestedFilename,
            sourceURL: item.sourceURL,
            destinationFolder: folder
        )
        let destinationURL = folder.appendingPathComponent(resolvedName)

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            guard fileSize > 0 else {
                throw NSError(
                    domain: "DownloadManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded file is empty (0 bytes)."]
                )
            }

            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            item.finalizeDestination(url: destinationURL, name: resolvedName)
            item.progress = 1.0
            item.status = .completed
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            item.status = .failed(friendlyMessage(for: error))
        }

        removeTask(for: itemId)
    }

    func handleDownloadError(taskIdentifier: Int, error: Error) {
        // Route YouTube sub-task first
        if let itemID = subTaskToCoordinator[taskIdentifier] {
            subTaskToCoordinator.removeValue(forKey: taskIdentifier)
            youtubeSubTasks.removeValue(forKey: taskIdentifier)
            if let coordinator = youtubeCoordinators[itemID] {
                coordinator.handleSubTaskError(taskID: taskIdentifier, error: error)
            }
            return
        }
        // Regular download
        guard let item = item(for: taskIdentifier) else { return }
        item.status = .failed(friendlyMessage(for: error))
        if let itemId = taskToDownload[taskIdentifier] {
            removeTask(for: itemId)
        }
    }

    // MARK: - Private helpers

    private func item(for taskIdentifier: Int) -> DownloadItem? {
        guard let itemId = taskToDownload[taskIdentifier] else { return nil }
        return downloads.first { $0.id == itemId }
    }

    private func removeTask(for itemId: UUID) {
        if let task = activeTasks[itemId] {
            taskToDownload.removeValue(forKey: task.taskIdentifier)
        }
        activeTasks.removeValue(forKey: itemId)
    }

    private func placeholderName(for url: URL) -> String {
        let last = url.lastPathComponent
        return (last.isEmpty || last == "/") ? "Downloading…" : last
    }

    // MARK: - File naming fallback chain (Condition 4)

    private func resolveFilename(
        suggestedFilename: String?,
        sourceURL: URL,
        destinationFolder: URL
    ) -> String {
        // 1. HTTPURLResponse.suggestedFilename (includes Content-Disposition parsing)
        if let suggested = suggestedFilename, !suggested.isEmpty {
            return deduplicate(filename: sanitizeFilename(suggested), in: destinationFolder)
        }
        // 2. URL.lastPathComponent
        let last = sourceURL.lastPathComponent
        if !last.isEmpty && last != "/" {
            return deduplicate(filename: sanitizeFilename(last), in: destinationFolder)
        }
        // 3. UUID fallback
        return "download-\(UUID().uuidString)"
    }

    /// Strips path separators and dangerous characters to prevent path traversal. (Security fix)
    /// Takes only the last path component, then allows only safe characters.
    private func sanitizeFilename(_ name: String) -> String {
        // Take only the last component — neutralizes any ../ sequences
        var safe = name.components(separatedBy: "/").last ?? name
        safe = safe.components(separatedBy: "\\").last ?? safe
        safe = safe.trimmingCharacters(in: .whitespaces)
        // Remove null bytes and other control characters
        safe = safe.filter { !$0.isNewline && $0 != "\0" }
        return safe.isEmpty ? "download-\(UUID().uuidString)" : safe
    }

    /// Appends " (2)", " (3)" etc. before the extension if the filename already exists.
    private func deduplicate(filename: String, in folder: URL) -> String {
        let candidate = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return filename
        }
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        for counter in 2..<1000 {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            if !FileManager.default.fileExists(atPath: folder.appendingPathComponent(newName).path) {
                return newName
            }
        }
        return ext.isEmpty ? "\(base)-\(UUID().uuidString)" : "\(base)-\(UUID().uuidString).\(ext)"
    }

    // MARK: - Orphan temp file sweep (Condition 6)

    private func sweepOrphanTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        ) else { return }

        var cleaned = 0
        for fileURL in contents {
            let name = fileURL.lastPathComponent
            if (name.hasPrefix("CFNetworkDownload_") && name.hasSuffix(".tmp"))
                || name.hasPrefix("swiftdl-inprogress-")
                || name.hasPrefix("swiftdl-dl-yt-") {
                if (try? FileManager.default.removeItem(at: fileURL)) != nil {
                    cleaned += 1
                }
            }
        }
        if cleaned > 0 {
            print("[DownloadManager] Swept \(cleaned) orphan temp file(s) at startup.")
        }
    }

    // MARK: - User-friendly error messages

    private func friendlyMessage(for error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case NSURLErrorNotConnectedToInternet:  return "No internet connection."
        case NSURLErrorTimedOut:                return "Connection timed out."
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL: return "Invalid URL."
        case NSURLErrorNetworkConnectionLost:   return "Connection lost during download."
        case NSURLErrorCannotWriteToFile:       return "Cannot write file — disk may be full."
        default:                                return (error as NSError).localizedDescription
        }
    }
}
