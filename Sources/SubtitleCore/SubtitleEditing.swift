import Foundation

public enum SubtitleEditing {
    /// Splits the cue at `index` into two cues at `characterOffset` within its text.
    /// Time is divided proportionally to the number of non-whitespace characters on each side.
    /// Returns nil if either side would be empty.
    public static func split(_ cues: [SubtitleCue], at index: Int, characterOffset: Int) -> [SubtitleCue]? {
        guard cues.indices.contains(index) else { return nil }
        let cue = cues[index]
        let offset = min(max(0, characterOffset), cue.text.count)
        let splitIdx = cue.text.index(cue.text.startIndex, offsetBy: offset)
        let before = String(cue.text[..<splitIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(cue.text[splitIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !before.isEmpty, !after.isEmpty else { return nil }

        let weight: (String) -> Int = { $0.filter { !$0.isWhitespace }.count }
        let wb = weight(before), wa = weight(after)
        let total = wb + wa
        let mid = cue.startMs + Int((Double(cue.durationMs) * Double(wb) / Double(max(total, 1))).rounded())

        var result = cues
        result[index] = SubtitleCue(id: cue.id, startMs: cue.startMs, endMs: mid, text: before)
        result.insert(SubtitleCue(startMs: mid, endMs: cue.endMs, text: after), at: index + 1)
        return result
    }

    /// Merges the cue at `index` with the following cue. The result spans from the first start to the
    /// later end; texts are joined with a newline. Returns nil if there is no next cue.
    public static func mergeWithNext(_ cues: [SubtitleCue], at index: Int, separator: String = "\n") -> [SubtitleCue]? {
        guard cues.indices.contains(index), cues.indices.contains(index + 1) else { return nil }
        return merge(cues, range: index...(index + 1), separator: separator)
    }

    /// Merges a contiguous range of cues into one.
    public static func merge(_ cues: [SubtitleCue], range: ClosedRange<Int>, separator: String = "\n") -> [SubtitleCue]? {
        guard range.count >= 2, cues.indices.contains(range.lowerBound), cues.indices.contains(range.upperBound) else {
            return nil
        }
        let slice = cues[range]
        let first = slice.first!
        let texts = slice.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let merged = SubtitleCue(
            id: first.id,
            startMs: first.startMs,
            endMs: max(slice.last!.endMs, slice.map(\.endMs).max()!),
            text: texts.joined(separator: separator)
        )
        var result = cues
        result.replaceSubrange(range, with: [merged])
        return result
    }

    /// Index of the cue that is active at `ms`, if any.
    public static func activeIndex(in cues: [SubtitleCue], at ms: Int) -> Int? {
        cues.lastIndex { $0.startMs <= ms && ms < $0.endMs }
    }
}
