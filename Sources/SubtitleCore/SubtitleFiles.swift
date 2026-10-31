import Foundation

public enum SubtitleFiles {
    public static let subtitleExtensions = ["srt", "vtt"]

    /// Finds a subtitle next to `video` with the same base name (`movie.srt`, `movie.vtt`),
    /// falling back to language-suffixed names such as `movie.zh.srt`.
    public static func sibling(for video: URL, fileManager: FileManager = .default) -> URL? {
        let dir = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        for ext in subtitleExtensions {
            let candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { subtitleExtensions.contains($0.pathExtension.lowercased()) && $0.lastPathComponent.hasPrefix(base + ".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }
}
