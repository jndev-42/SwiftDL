import Foundation

/// Orchestrates one YouTube download: extract → download stream(s) → merge (if DASH).
/// @MainActor to match DownloadManager isolation.
@MainActor
final class YouTubeDownloadCoordinator {

    let item: DownloadItem
    private let destinationFolder: URL
    private let videoID: String

    // Callbacks set by DownloadManager
    var onNeedDownloadTask: ((URL) -> (task: URLSessionDownloadTask, taskID: Int)?)?
    var onCancelSubTask: ((Int) -> Void)?   // cancel a registered sub-task by ID
    var onComplete: (() -> Void)?

    // Sub-task tracking
    private var videoTaskID: Int?
    private var audioTaskID: Int?
    private var videoTempURL: URL?
    private var audioTempURL: URL?
    private var videoCompleted = false
    private var audioCompleted = false
    private var isMuxed = false
    private var videoTitle = "youtube-video"

    // Per-stream bytes for accurate combined progress display
    private var videoBytesReceived: Int64 = 0
    private var audioBytesReceived: Int64 = 0
    private var videoTotalBytes: Int64 = -1
    private var audioTotalBytes: Int64 = -1

    private var extractionTask: Task<Void, Never>?
    private var mergeTask: Task<Void, Never>?      // stored so cancel() can stop the merge

    init(item: DownloadItem, destinationFolder: URL, videoID: String) {
        self.item = item
        self.destinationFolder = destinationFolder
        self.videoID = videoID
    }

    func start() {
        item.status = .extracting
        item.statusDetail = "Fetching video info…"

        extractionTask = Task {
            do {
                let streams = try await YouTubeExtractor.extract(videoID: videoID)
                handleExtractedStreams(streams)
            } catch {
                item.status = .failed(error.localizedDescription)
                item.statusDetail = nil
                onComplete?()
            }
        }
    }

    func cancel() {
        extractionTask?.cancel()
        mergeTask?.cancel()
        // Sub-task cancellation handled by DownloadManager via onCancelSubTask
        cleanup()
    }

    // MARK: - Called by DownloadManager on sub-task events

    func updateProgress(taskID: Int, bytesWritten: Int64, totalExpected: Int64, fraction: Double) {
        if isMuxed {
            item.bytesReceived = bytesWritten
            item.totalBytes = totalExpected
            item.progress = fraction
        } else {
            if taskID == videoTaskID {
                videoBytesReceived = bytesWritten
                videoTotalBytes = totalExpected
            } else if taskID == audioTaskID {
                audioBytesReceived = bytesWritten
                audioTotalBytes = totalExpected
            }
            // Combined bytes for display
            item.bytesReceived = videoBytesReceived + audioBytesReceived
            let totalKnown = (videoTotalBytes > 0 ? videoTotalBytes : 0)
                           + (audioTotalBytes > 0 ? audioTotalBytes : 0)
            item.totalBytes = totalKnown > 0 ? totalKnown : -1
            // Weighted progress: 45% video + 45% audio + 10% reserved for merge
            let vFrac = videoTotalBytes > 0 ? min(1, Double(videoBytesReceived) / Double(videoTotalBytes)) : 0
            let aFrac = audioTotalBytes > 0 ? min(1, Double(audioBytesReceived) / Double(audioTotalBytes)) : 0
            item.progress = min(0.9, vFrac * 0.45 + aFrac * 0.45)
        }
    }

    func handleSubTaskComplete(taskID: Int, tempURL: URL) {
        // Check for 0-byte files (YouTube rejection)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        if fileSize == 0 {
            handleSubTaskError(taskID: taskID, error: NSError(
                domain: "YouTubeCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Stream download resulted in 0 bytes (likely blocked by YouTube)."]
            ))
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        if taskID == videoTaskID {
            videoTempURL = tempURL
            videoCompleted = true
        } else if taskID == audioTaskID {
            audioTempURL = tempURL
            audioCompleted = true
        }

        if isMuxed && videoCompleted {
            finalizeMuxed()
        } else if !isMuxed && videoCompleted && audioCompleted {
            startMerge()
        }
    }

    func handleSubTaskError(taskID: Int, error: Error) {
        // Cancel the sibling task if one stream fails
        if taskID == videoTaskID, let aid = audioTaskID { onCancelSubTask?(aid) }
        if taskID == audioTaskID, let vid = videoTaskID { onCancelSubTask?(vid) }
        item.status = .failed(error.localizedDescription)
        item.statusDetail = nil
        cleanup()
        onComplete?()
    }

    // MARK: - Private

    private func handleExtractedStreams(_ streams: ExtractedStreams) {
        switch streams {
        case .muxed(let url, let title):
            isMuxed = true
            videoTitle = title
            item.fileName = sanitize(title) + ".mp4"
            item.status = .downloading
            item.statusDetail = nil
            startStreamDownload(url: url, isVideo: true)

        case .adaptive(let videoURL, let audioURL, let title):
            isMuxed = false
            videoTitle = title
            item.fileName = sanitize(title) + ".mp4"
            item.status = .downloading
            item.statusDetail = "Downloading video + audio…"
            startStreamDownload(url: videoURL, isVideo: true)
            startStreamDownload(url: audioURL, isVideo: false)

            // Guard: task IDs must be distinct for routing to work correctly
            if let vid = videoTaskID, let aid = audioTaskID, vid == aid {
                onCancelSubTask?(vid)
                item.status = .failed("Internal error: download task ID collision.")
                item.statusDetail = nil
                onComplete?()
            }
        }
    }

    private func startStreamDownload(url: URL, isVideo: Bool) {
        guard let result = onNeedDownloadTask?(url) else {
            // If audio setup fails after video was already started, cancel the video task
            if !isVideo, let vid = videoTaskID { onCancelSubTask?(vid) }
            item.status = .failed("Internal error: could not create download task.")
            item.statusDetail = nil
            onComplete?()
            return
        }
        if isVideo {
            videoTaskID = result.taskID
        } else {
            audioTaskID = result.taskID
        }
        result.task.resume()
    }

    private func finalizeMuxed() {
        guard let tempURL = videoTempURL else { return }
        let name = deduplicate(sanitize(videoTitle) + ".mp4")
        let finalURL = destinationFolder.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            videoTempURL = nil  // moved; do not delete in cleanup
            item.finalizeDestination(url: finalURL, name: name)
            item.progress = 1.0
            item.status = .completed
            item.statusDetail = nil
        } catch {
            item.status = .failed("Failed to save file: \(error.localizedDescription)")
            item.statusDetail = nil
        }
        onComplete?()
    }

    private func startMerge() {
        guard let videoTemp = videoTempURL, let audioTemp = audioTempURL else { return }

        item.status = .merging
        item.statusDetail = "Merging video + audio…"

        let name = deduplicate(sanitize(videoTitle) + ".mp4")
        let finalURL = destinationFolder.appendingPathComponent(name)

        mergeTask = Task {
            do {
                // AVFoundation needs file extensions to correctly identify formats.
                // Rename temp files to include .mp4 and .m4a hints.
                let vWithExt = videoTemp.appendingPathExtension("mp4")
                let aWithExt = audioTemp.appendingPathExtension("m4a")
                
                try? FileManager.default.removeItem(at: vWithExt)
                try? FileManager.default.removeItem(at: aWithExt)
                
                try FileManager.default.moveItem(at: videoTemp, to: vWithExt)
                try FileManager.default.moveItem(at: audioTemp, to: aWithExt)

                try await AVMerger.merge(
                    videoFileURL: vWithExt,
                    audioFileURL: aWithExt,
                    outputURL: finalURL
                )
                
                // Cleanup renamed temp files
                try? FileManager.default.removeItem(at: vWithExt)
                try? FileManager.default.removeItem(at: aWithExt)
                videoTempURL = nil
                audioTempURL = nil

                if Task.isCancelled { return }

                item.finalizeDestination(url: finalURL, name: name)
                item.progress = 1.0
                item.status = .completed
                item.statusDetail = nil
            } catch {
                if Task.isCancelled { return }
                item.status = .failed(error.localizedDescription)
                item.statusDetail = nil
            }
            cleanup()
            onComplete?()
        }
    }

    private func cleanup() {
        if let url = videoTempURL { try? FileManager.default.removeItem(at: url); videoTempURL = nil }
        if let url = audioTempURL { try? FileManager.default.removeItem(at: url); audioTempURL = nil }
    }

    /// Strips filesystem-unsafe chars, bidi overrides, zero-width chars, and leading dots.
    private func sanitize(_ title: String) -> String {
        var s = title
        // Replace filesystem-unsafe chars
        for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] {
            s = s.replacingOccurrences(of: ch, with: "-")
        }
        // Strip control chars, newlines, null bytes
        s = s.filter { !$0.isNewline && $0 != "\0" }
        // Strip Unicode bidi overrides and zero-width chars (UI-deception prevention)
        s = String(s.unicodeScalars.filter { scalar in
            let v = scalar.value
            let bidi = (v >= 0x202A && v <= 0x202E) || (v >= 0x2066 && v <= 0x2069)
                    || v == 0x200E || v == 0x200F
            let zw   = v == 0x200B || v == 0x200C || v == 0x200D || v == 0xFEFF
            return !bidi && !zw
        }.map(Character.init))
        // Strip leading dots (prevents hidden files)
        while s.hasPrefix(".") { s = String(s.dropFirst()) }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "youtube-video" : trimmed
    }

    private func deduplicate(_ filename: String) -> String {
        let candidate = destinationFolder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return filename }
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        for i in 2..<1000 {
            let name = "\(base) (\(i)).\(ext)"
            if !FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent(name).path) {
                return name
            }
        }
        return "\(base)-\(UUID().uuidString).\(ext)"
    }
}
