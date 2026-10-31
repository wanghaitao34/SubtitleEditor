import Foundation

/// A single subtitle entry. Times are stored as integer milliseconds to avoid rounding drift.
public struct SubtitleCue: Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var startMs: Int
    public var endMs: Int
    public var text: String

    public init(id: UUID = UUID(), startMs: Int, endMs: Int, text: String) {
        self.id = id
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
    }

    public var start: TimeInterval { TimeInterval(startMs) / 1000 }
    public var end: TimeInterval { TimeInterval(endMs) / 1000 }
    public var durationMs: Int { max(0, endMs - startMs) }
}

public enum SubtitleFormat: String, CaseIterable, Sendable {
    case srt, vtt, txt, md

    public var fileExtension: String { rawValue }

    public init?(fileExtension ext: String) {
        self.init(rawValue: ext.lowercased())
    }
}

public enum Timecode {
    /// Formats milliseconds as `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm` (VTT).
    public static func format(_ ms: Int, separator: Character = ",") -> String {
        let ms = max(0, ms)
        let h = ms / 3_600_000
        let m = (ms / 60_000) % 60
        let s = (ms / 1000) % 60
        let f = ms % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, String(separator), f)
    }

    /// Parses `HH:MM:SS,mmm`, `HH:MM:SS.mmm`, `MM:SS.mmm` (hours optional), fraction of 1–3+ digits.
    public static func parse(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var main = s
        var fracMs = 0
        if let sepIdx = s.lastIndex(where: { $0 == "," || $0 == "." }) {
            main = String(s[..<sepIdx])
            let frac = String(s[s.index(after: sepIdx)...])
            guard !frac.isEmpty, frac.allSatisfy(\.isNumber) else { return nil }
            let digits = String((frac + "00").prefix(3))
            fracMs = Int(digits) ?? 0
        }
        let parts = main.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        let nums = parts.compactMap { Int($0) }
        var total = 0
        for n in nums { total = total * 60 + n }
        return total * 1000 + fracMs
    }
}
