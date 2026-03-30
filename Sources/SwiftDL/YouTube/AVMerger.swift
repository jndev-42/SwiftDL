import AVFoundation

enum AVMergerError: LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case exportSessionCreationFailed
    case exportFailed(String)
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:                  return "No video track in downloaded file."
        case .noAudioTrack:                  return "No audio track in downloaded file."
        case .exportSessionCreationFailed:   return "Could not create AVAssetExportSession."
        case .exportFailed(let msg):         return "Merge failed: \(msg)"
        case .exportCancelled:               return "Merge was cancelled."
        }
    }
}

enum AVMerger {

    /// Merges a video-only MP4 and an audio-only M4A/MP4 into a single MP4.
    /// Uses Passthrough preset — no re-encoding, near-instant for H.264+AAC.
    static func merge(videoFileURL: URL, audioFileURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoFileURL)
        let audioAsset = AVURLAsset(url: audioFileURL)

        // Load tracks asynchronously (macOS 12+ async API)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw AVMergerError.noVideoTrack
        }
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw AVMergerError.noAudioTrack
        }

        let duration = try await videoAsset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        // Add video
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AVMergerError.noVideoTrack }
        try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        // Add audio
        guard let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AVMergerError.noAudioTrack }
        try compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)

        // Remove any existing partial output
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough  // remux only, no re-encode
        ) else {
            throw AVMergerError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        // AVAssetExportSession is NS_SWIFT_NONSENDABLE; safe here since we own the session
        // and the completion handler only fires once.
        let session = exportSession
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: AVMergerError.exportCancelled)
                default:
                    let msg = session.error?.localizedDescription ?? "Unknown error"
                    continuation.resume(throwing: AVMergerError.exportFailed(msg))
                }
            }
        }
    }
}
