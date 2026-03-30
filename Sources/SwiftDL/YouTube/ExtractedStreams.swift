import Foundation

/// Represents the extracted stream(s) from a YouTube video.
enum ExtractedStreams {
    /// A single stream that contains both video and audio.
    case muxed(url: URL, title: String)
    
    /// Separate video and audio streams that need to be merged.
    case adaptive(videoURL: URL, audioURL: URL, title: String)
}
