import Foundation

/// URLSession delegate adapter. Receives URLSession callbacks on a background queue
/// and dispatches all state mutations to DownloadManager on @MainActor. (Condition 1)
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {

    /// Weak reference to avoid retain cycle (DownloadManager → delegate → DownloadManager).
    /// Marked nonisolated(unsafe): access is always followed by a @MainActor dispatch. (Condition 1)
    nonisolated(unsafe) weak var manager: DownloadManager?

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        let received = totalBytesWritten
        let total = totalBytesExpectedToWrite
        Task { @MainActor in
            self.manager?.updateProgress(
                taskIdentifier: taskId,
                bytesWritten: received,
                totalExpected: total
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier
        let response = downloadTask.response as? HTTPURLResponse
        let statusCode = response?.statusCode ?? -1
        let suggestedFilename = response?.suggestedFilename

        // Validate HTTP success (2xx)
        guard statusCode >= 200 && statusCode < 300 else {
            let error = NSError(
                domain: "DownloadSessionDelegate",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(statusCode)"]
            )
            Task { @MainActor in
                self.manager?.handleDownloadError(taskIdentifier: taskId, error: error)
            }
            return
        }

        // URLSession deletes the temp file when this method returns.
        // Copy it to a new temp location before dispatching to MainActor.
        let tempCopyURL: URL
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let tempName = "swiftdl-inprogress-\(taskId)-\(UUID().uuidString)"
            tempCopyURL = tempDir.appendingPathComponent(tempName)
            try FileManager.default.copyItem(at: location, to: tempCopyURL)
        } catch {
            Task { @MainActor in
                self.manager?.handleDownloadError(taskIdentifier: taskId, error: error)
            }
            return
        }

        Task { @MainActor in
            self.manager?.handleDownloadComplete(
                taskIdentifier: taskId,
                tempURL: tempCopyURL,
                suggestedFilename: suggestedFilename
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error else { return }  // success handled in didFinishDownloadingTo
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }  // expected cancellation

        let taskId = task.taskIdentifier
        Task { @MainActor in
            self.manager?.handleDownloadError(taskIdentifier: taskId, error: error)
        }
    }
}
