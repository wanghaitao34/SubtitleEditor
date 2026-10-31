import Foundation

public enum SubtitleParseError: Error, LocalizedError {
    case unreadableEncoding
    case noCuesFound

    public var errorDescription: String? {
        switch self {
        case .unreadableEncoding: return "无法识别字幕文件的文本编码。"
        case .noCuesFound: return "文件中没有找到有效的字幕条目。"
        }
    }
}

public enum SubtitleParser {
    /// Decodes subtitle file bytes, trying UTF-8 (with/without BOM), UTF-16 (BOM), GB18030 and Latin-1.
    public static func decode(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) {
            return s
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw SubtitleParseError.unreadableEncoding
    }

    public static func parse(data: Data) throws -> [SubtitleCue] {
        let cues = parse(try decode(data))
        if cues.isEmpty { throw SubtitleParseError.noCuesFound }
        return cues
    }

    /// Parses SRT or WebVTT text. Format is handled uniformly: each blank-line separated block
    /// that contains a `-->` timing line becomes a cue; WEBVTT headers and NOTE/STYLE/REGION blocks are skipped.
    public static func parse(_ content: String) -> [SubtitleCue] {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        var blocks: [[String]] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var cues: [SubtitleCue] = []
        for block in blocks {
            let first = block[0].trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first == "STYLE" || first == "REGION" {
                // A WEBVTT header block may (invalidly) be followed directly by a cue; handle that.
                if first.hasPrefix("WEBVTT"), let idx = block.firstIndex(where: { $0.contains("-->") }) {
                    if let cue = makeCue(timing: block[idx], textLines: Array(block[(idx + 1)...])) { cues.append(cue) }
                }
                continue
            }
            // Timing line is either the first or second line (after a numeric/identifier line).
            guard let idx = block.prefix(2).firstIndex(where: { $0.contains("-->") }) else { continue }
            if let cue = makeCue(timing: block[idx], textLines: Array(block[(idx + 1)...])) {
                cues.append(cue)
            }
        }
        return cues
    }

    private static func makeCue(timing: String, textLines: [String]) -> SubtitleCue? {
        let parts = timing.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let startRaw = parts[0].trimmingCharacters(in: .whitespaces)
        // VTT cue settings (e.g. "align:start") follow the end time; SRT may have X1:.. coords.
        let endRaw = parts[1].trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        guard let start = Timecode.parse(startRaw), let end = Timecode.parse(endRaw) else { return nil }
        let body = textLines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        return SubtitleCue(startMs: start, endMs: max(start, end), text: body)
    }
}
