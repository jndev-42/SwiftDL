import Foundation
import Observation

enum DownloadStatus: Equatable {
    case pending
    case extracting   // fetching YouTube stream info
    case downloading
    case merging      // AVFoundation video+audio merge
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .pending, .extracting, .downloading, .merging: return true
        case .completed, .failed, .cancelled: return false
        }
    }
}

@MainActor
@Observable
final class DownloadItem: Identifiable {
    let id: UUID
    let sourceURL: URL
    private(set) var destinationURL: URL  // folder during download, file URL on completion
    var fileName: String
    var progress: Double = 0.0
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = -1  // -1 = NSURLSessionTransferSizeUnknown (no Content-Length)
    var status: DownloadStatus = .pending
    var statusDetail: String?  // e.g. "Fetching video info…", "Merging video + audio…"

    var isIndeterminate: Bool { totalBytes == -1 }

    init(id: UUID = UUID(), sourceURL: URL, destinationURL: URL, fileName: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.fileName = fileName
    }

    /// Called by DownloadManager on completion to finalize the destination file URL and name.
    func finalizeDestination(url: URL, name: String) {
        self.destinationURL = url
        self.fileName = name
    }
}
