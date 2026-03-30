import Foundation

/// Single source of truth for URL validation and video file extensions.
enum URLValidator {

    /// Canonical set of supported video file extensions. Referenced everywhere — not duplicated.
    static let videoExtensions: Set<String> = [
        ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".m4v", ".ts", ".webm"
    ]

    /// Returns true if the string is a valid HTTP or HTTPS URL.
    static func isValid(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    /// Returns a URL if valid, nil otherwise.
    static func url(from string: String) -> URL? {
        guard isValid(string) else { return nil }
        return URL(string: string)
    }

    // MARK: - YouTube Detection

    private static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "youtu.be", "www.youtu.be"
    ]

    /// Returns true if the string is a valid HTTPS YouTube video URL (not playlist/channel).
    static func isYouTubeURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              youtubeHosts.contains(host) else { return false }
        return extractVideoID(from: url) != nil
    }

    /// Extracts the 11-character video ID from a YouTube URL, or nil.
    /// Supports: youtube.com/watch?v=ID, youtu.be/ID, youtube.com/embed/ID, youtube.com/v/ID
    static func extractVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // youtu.be/VIDEO_ID
        if host.contains("youtu.be") {
            return validVideoID(url.pathComponents.dropFirst().first)
        }

        // youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return validVideoID(v)
        }

        // youtube.com/embed/VIDEO_ID or youtube.com/v/VIDEO_ID
        let path = url.pathComponents
        if let idx = path.firstIndex(where: { $0 == "embed" || $0 == "v" }), idx + 1 < path.count {
            return validVideoID(path[idx + 1])
        }

        return nil
    }

    /// Convenience overload for string input.
    static func extractVideoID(fromString urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return extractVideoID(from: url)
    }

    private static func validVideoID(_ candidate: String?) -> String? {
        guard let id = candidate, id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else { return nil }
        return id
    }
}
