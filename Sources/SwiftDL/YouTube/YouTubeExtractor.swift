import Foundation

/// Gère l'extraction des URLs de flux directs à l'aide de l'outil yt-dlp.
/// Cette classe est conçue pour contourner les limitations des extracteurs manuels en utilisant une référence de l'industrie.
enum YouTubeExtractor {

    /// Erreurs spécifiques à l'extraction de métadonnées YouTube.
    enum YouTubeExtractorError: LocalizedError {
        case invalidVideoID
        case binaryError(String)
        case apiError(String)
        case noSuitableStream
        case timeout
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidVideoID:       return "L'ID de la vidéo YouTube est invalide."
            case .binaryError(let msg): return "Erreur du binaire : \(msg)"
            case .apiError(let msg):    return "YouTube : \(msg)"
            case .noSuitableStream:     return "Aucun flux compatible trouvé."
            case .timeout:              return "Délai d'attente de yt-dlp dépassé."
            case .decodingError(let e): return "Échec de l'analyse des métadonnées : \(e.localizedDescription)"
            }
        }
    }

    /// Extrait les URLs de flux (vidéo seule, audio seul ou muxé) pour un ID de vidéo donné.
    /// - Parameter videoID: L'identifiant unique de la vidéo (ex: CoD8IS36Rjk).
    /// - Returns: Une structure `ExtractedStreams` contenant les URLs directes.
    static func extract(videoID: String) async throws -> ExtractedStreams {
        guard !videoID.isEmpty else { throw YouTubeExtractorError.invalidVideoID }

        // 1. S'assurer que le binaire yt-dlp est présent dans le dossier Application Support
        try await BinaryManager.ensureBinariesExist()

        // 2. Exécuter yt-dlp pour récupérer les métadonnées au format JSON
        let json = try await runYtDlp(videoID: videoID)

        // 3. Décoder la réponse
        let metadata: YtDlpMetadata
        do {
            metadata = try JSONDecoder().decode(YtDlpMetadata.self, from: json)
        } catch {
            throw YouTubeExtractorError.decodingError(error)
        }

        let title = metadata.title ?? "youtube-video"
        let formats = metadata.formats ?? []

        // 4. Sélection des flux : On privilégie H.264 (avc1) et AAC (mp4a) pour une fusion
        // sans perte et ultra-rapide via AVFoundation.
        
        // Meilleure vidéo H.264 seule
        let bestVideo = formats.filter { 
            $0.vcodec != "none" && $0.acodec == "none" && $0.ext == "mp4" &&
            ($0.vcodec?.hasPrefix("avc1") ?? false)
        }.sorted { 
            if $0.height != $1.height { return ($0.height ?? 0) > ($1.height ?? 0) }
            return ($0.tbr ?? 0) > ($1.tbr ?? 0)
        }.first

        // Meilleur audio AAC seul
        let bestAudio = formats.filter { 
            $0.vcodec == "none" && $0.acodec != "none" && ($0.ext == "m4a" || $0.ext == "mp4") &&
            ($0.acodec?.hasPrefix("mp4a") ?? false)
        }.sorted { return ($0.abr ?? 0) > ($1.abr ?? 0) }.first

        // Meilleur flux déjà combiné (muxed)
        let bestMuxed = formats.filter { 
            $0.vcodec != "none" && $0.acodec != "none" && $0.ext == "mp4"
        }.sorted { return ($0.height ?? 0) > ($1.height ?? 0) }.first

        // Si on a de l'adaptatif de meilleure (ou égale) qualité que le muxé, on le prend
        if let v = bestVideo, let vURL = URL(string: v.url ?? ""),
           let a = bestAudio, let aURL = URL(string: a.url ?? "") {
            
            let muxHeight = bestMuxed?.height ?? 0
            let adaptiveHeight = v.height ?? 0
            
            if adaptiveHeight >= muxHeight {
                return .adaptive(videoURL: vURL, audioURL: aURL, title: title)
            }
        }

        // Sinon, retour au meilleur flux muxé (déjà combiné)
        if let m = bestMuxed, let mURL = URL(string: m.url ?? "") {
            return .muxed(url: mURL, title: title)
        }

        throw YouTubeExtractorError.noSuitableStream
    }

    /// Exécute le processus yt-dlp de manière asynchrone pour éviter de bloquer l'interface.
    private static func runYtDlp(videoID: String) async throws -> Data {
        let process = Process()
        process.executableURL = BinaryManager.ytDlpURL
        process.arguments = [
            "--dump-json",
            "--no-playlist",
            "--no-check-certificates",
            "https://www.youtube.com/watch?v=\(videoID)"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var outputData = Data()
        var errorData = Data()

        try process.run()

        // Lecture concurrente des flux pour éviter les deadlocks de buffer
        await withTaskGroup(of: Void.self) { group in
            group.addTask { outputData = outputPipe.fileHandleForReading.readDataToEndOfFile() }
            group.addTask { errorData = errorPipe.fileHandleForReading.readDataToEndOfFile() }
        }

        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return outputData
        } else {
            let errorString = String(data: errorData, encoding: .utf8) ?? "Erreur inconnue"
            throw YouTubeExtractorError.apiError(errorString)
        }
    }

    // MARK: - Modèles de données internes (yt-dlp JSON)

    private struct YtDlpMetadata: Codable {
        let title: String?
        let formats: [YtDlpFormat]?
    }

    private struct YtDlpFormat: Codable {
        let url: String?
        let ext: String?
        let vcodec: String?
        let acodec: String?
        let height: Int?
        let abr: Double?
        let tbr: Double?
    }
}
