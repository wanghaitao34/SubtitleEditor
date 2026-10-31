import Foundation

public enum SubtitleExporter {
    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Windows-style SRT: CRLF line endings, renumbered from 1, `HH:MM:SS,mmm` timecodes.
    public static func srt(_ cues: [SubtitleCue]) -> String {
        var out = ""
        for (i, cue) in cues.enumerated() {
            out += "\(i + 1)\r\n"
            out += "\(Timecode.format(cue.startMs, separator: ",")) --> \(Timecode.format(cue.endMs, separator: ","))\r\n"
            out += lines(cue.text).joined(separator: "\r\n") + "\r\n\r\n"
        }
        return out
    }

    public static func vtt(_ cues: [SubtitleCue]) -> String {
        var out = "WEBVTT\n\n"
        for cue in cues {
            out += "\(Timecode.format(cue.startMs, separator: ".")) --> \(Timecode.format(cue.endMs, separator: "."))\n"
            // A blank line would terminate the cue in VTT, so drop empty lines.
            out += lines(cue.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n") + "\n\n"
        }
        return out
    }

    /// Plain text without timecodes: one cue per line (multi-line cues keep their line breaks).
    public static func txt(_ cues: [SubtitleCue]) -> String {
        cues.map { lines($0.text).joined(separator: "\n") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n") + "\n"
    }

    /// Markdown without timecodes: optional title heading, one paragraph per cue.
    public static func markdown(_ cues: [SubtitleCue], title: String? = nil) -> String {
        var out = ""
        if let title, !title.isEmpty { out += "# \(title)\n\n" }
        let paragraphs = cues
            .map { lines($0.text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: "  \n") } // Markdown hard line break inside a cue
        out += paragraphs.joined(separator: "\n\n") + "\n"
        return out
    }

    public static func string(_ cues: [SubtitleCue], format: SubtitleFormat, title: String? = nil) -> String {
        switch format {
        case .srt: return srt(cues)
        case .vtt: return vtt(cues)
        case .txt: return txt(cues)
        case .md: return markdown(cues, title: title)
        }
    }

    /// File bytes for a format. SRT is written as UTF-8 with BOM for best compatibility with Windows players.
    public static func data(_ cues: [SubtitleCue], format: SubtitleFormat, title: String? = nil) -> Data {
        var data = Data()
        if format == .srt { data.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        data.append(Data(string(cues, format: format, title: title).utf8))
        return data
    }
}
