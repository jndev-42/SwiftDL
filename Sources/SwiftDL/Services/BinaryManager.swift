import Foundation

/// Manages external binaries like yt-dlp, downloading them if missing.
enum BinaryManager {

    private static let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("swiftdl")
    private static let binDir = appSupportDir.appendingPathComponent("bin")

    static var ytDlpURL: URL {
        binDir.appendingPathComponent("yt-dlp")
    }

    /// Ensures yt-dlp is available in the Application Support folder.
    static func ensureBinariesExist() async throws {
        // Create directories if missing
        if !FileManager.default.fileExists(atPath: binDir.path) {
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        }

        // Check if yt-dlp already exists and is executable
        if FileManager.default.isExecutableFile(atPath: ytDlpURL.path) {
            return
        }

        // Otherwise, download the latest version for macOS
        // We use the universal binary from yt-dlp/yt-dlp releases
        print("[BinaryManager] Downloading yt-dlp...")
        let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let (data, response) = try await URLSession.shared.data(from: downloadURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "BinaryManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download yt-dlp binary."])
        }

        try data.write(to: ytDlpURL)

        // Make it executable
        let attributes = [FileAttributeKey.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: ytDlpURL.path)
        print("[BinaryManager] yt-dlp installed at \(ytDlpURL.path)")
    }
}
