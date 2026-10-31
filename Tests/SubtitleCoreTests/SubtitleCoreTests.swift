import Foundation
import Testing
@testable import SubtitleCore

@Suite struct TimecodeTests {
    @Test func formatsSrtAndVtt() {
        #expect(Timecode.format(3_723_045) == "01:02:03,045")
        #expect(Timecode.format(3_723_045, separator: ".") == "01:02:03.045")
        #expect(Timecode.format(-5) == "00:00:00,000")
    }

    @Test func parsesVariants() {
        #expect(Timecode.parse("01:02:03,045") == 3_723_045)
        #expect(Timecode.parse("01:02:03.045") == 3_723_045)
        #expect(Timecode.parse("02:03.5") == 123_500)
        #expect(Timecode.parse("00:00:01,12") == 1_120)
        #expect(Timecode.parse("abc") == nil)
        #expect(Timecode.parse("") == nil)
    }
}

@Suite struct ParserTests {
    @Test func parsesSrtWithCRLFAndBOM() {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\n你好\r\n世界\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nSecond\r\n"
        let cues = SubtitleParser.parse(srt)
        #expect(cues.count == 2)
        #expect(cues[0].startMs == 1000 && cues[0].endMs == 2500)
        #expect(cues[0].text == "你好\n世界")
        #expect(cues[1].text == "Second")
    }

    @Test func parsesSrtWithExtraBlankLines() {
        let srt = "\n\n1\n00:00:01,000 --> 00:00:02,000\nA\n\n\n\n2\n00:00:02,000 --> 00:00:03,000\nB"
        #expect(SubtitleParser.parse(srt).map(\.text) == ["A", "B"])
    }

    @Test func parsesVttWithHeaderNotesIdentifiersAndSettings() {
        let vtt = """
        WEBVTT - Title
        Kind: captions

        NOTE this is a comment
        spanning lines

        STYLE
        ::cue { color: red }

        intro
        00:01.000 --> 00:02.000 align:start position:10%
        Hello

        01:00:00.000 --> 01:00:01.250
        Hour cue
        """
        let cues = SubtitleParser.parse(vtt)
        #expect(cues.count == 2)
        #expect(cues[0].startMs == 1000 && cues[0].endMs == 2000 && cues[0].text == "Hello")
        #expect(cues[1].startMs == 3_600_000 && cues[1].endMs == 3_601_250)
    }

    @Test func decodesGB18030() throws {
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let data = "1\n00:00:01,000 --> 00:00:02,000\n中文字幕\n".data(using: String.Encoding(rawValue: gb))!
        let cues = try SubtitleParser.parse(data: data)
        #expect(cues.first?.text == "中文字幕")
    }

    @Test func emptyInputThrows() {
        #expect(throws: SubtitleParseError.self) { try SubtitleParser.parse(data: Data("hello".utf8)) }
    }
}

@Suite struct EditingTests {
    let cues = [
        SubtitleCue(startMs: 0, endMs: 1000, text: "AAAABBBBBBBB"),
        SubtitleCue(startMs: 1000, endMs: 3000, text: "Next"),
    ]

    @Test func splitDistributesTimeByCharacters() throws {
        let result = try #require(SubtitleEditing.split(cues, at: 0, characterOffset: 4))
        #expect(result.count == 3)
        #expect(result[0].text == "AAAA" && result[0].startMs == 0 && result[0].endMs == 333)
        #expect(result[1].text == "BBBBBBBB" && result[1].startMs == 333 && result[1].endMs == 1000)
        #expect(result[0].id == cues[0].id)
        #expect(result[2] == cues[1])
    }

    @Test func splitIgnoresWhitespaceWhenWeighting() throws {
        let c = [SubtitleCue(startMs: 1000, endMs: 2000, text: "ab\ncd")]
        let r = try #require(SubtitleEditing.split(c, at: 0, characterOffset: 2))
        #expect(r.map(\.text) == ["ab", "cd"])
        #expect(r[0].endMs == 1500 && r[1].startMs == 1500)
    }

    @Test func splitAtEdgesIsRejected() {
        #expect(SubtitleEditing.split(cues, at: 0, characterOffset: 0) == nil)
        #expect(SubtitleEditing.split(cues, at: 0, characterOffset: 12) == nil)
        #expect(SubtitleEditing.split(cues, at: 5, characterOffset: 1) == nil)
    }

    @Test func mergeTakesFirstStartAndLastEnd() throws {
        let r = try #require(SubtitleEditing.mergeWithNext(cues, at: 0))
        #expect(r.count == 1)
        #expect(r[0].startMs == 0 && r[0].endMs == 3000)
        #expect(r[0].text == "AAAABBBBBBBB Next")
        #expect(SubtitleEditing.mergeWithNext(cues, at: 1) == nil)
    }

    @Test func splitThenMergeRoundTrips() throws {
        let s = try #require(SubtitleEditing.split(cues, at: 0, characterOffset: 4))
        let m = try #require(SubtitleEditing.mergeWithNext(s, at: 0, separator: ""))
        #expect(m[0].startMs == 0 && m[0].endMs == 1000 && m[0].text == "AAAABBBBBBBB")
    }

    @Test func mergeJoinsOnOneLine() throws {
        let zh = [SubtitleCue(startMs: 0, endMs: 1000, text: "你好，"), SubtitleCue(startMs: 1000, endMs: 2000, text: "世界")]
        #expect(try #require(SubtitleEditing.mergeWithNext(zh, at: 0))[0].text == "你好，世界")
        #expect(SubtitleEditing.joinSeparator("Hello", "world") == " ")
        #expect(SubtitleEditing.joinSeparator("Hello", "世界") == "")
        #expect(SubtitleEditing.joinSeparator("Hi ", "x") == "")
    }

    @Test func activeIndex() {
        #expect(SubtitleEditing.activeIndex(in: cues, at: 500) == 0)
        #expect(SubtitleEditing.activeIndex(in: cues, at: 1000) == 1)
        #expect(SubtitleEditing.activeIndex(in: cues, at: 5000) == nil)
    }
}

@Suite struct ExporterTests {
    let cues = [
        SubtitleCue(startMs: 1000, endMs: 2500, text: "第一行\n第二行"),
        SubtitleCue(startMs: 3_600_000, endMs: 3_601_000, text: "Second"),
    ]

    @Test func srtUsesCRLFAndRenumbers() {
        let s = SubtitleExporter.srt(cues)
        #expect(s == "1\r\n00:00:01,000 --> 00:00:02,500\r\n第一行\r\n第二行\r\n\r\n2\r\n01:00:00,000 --> 01:00:01,000\r\nSecond\r\n\r\n")
        #expect(!s.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        let data = SubtitleExporter.data(cues, format: .srt)
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test func dataPreservesLineEndingAndBOM() {
        let unix = SubtitleExporter.data(cues, format: .srt, lineEnding: .lf, bom: false)
        #expect(!unix.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(!unix.contains(0x0D))
        #expect(String(decoding: unix, as: UTF8.self) == SubtitleExporter.srt(cues).replacingOccurrences(of: "\r\n", with: "\n"))
        let vttCRLF = SubtitleExporter.data(cues, format: .vtt, lineEnding: .crlf, bom: true)
        #expect(vttCRLF.starts(with: [0xEF, 0xBB, 0xBF, 0x57]))
        #expect(LineEnding.detect(in: String(decoding: vttCRLF, as: UTF8.self)) == .crlf)
        #expect(!SubtitleExporter.data(cues, format: .vtt).contains(0x0D))
    }

    @Test func vtt() {
        #expect(SubtitleExporter.vtt(cues) == "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\n第一行\n第二行\n\n01:00:00.000 --> 01:00:01.000\nSecond\n\n")
    }

    @Test func txtAndMarkdownHaveNoTimecodes() {
        #expect(SubtitleExporter.txt(cues) == "第一行\n第二行\nSecond\n")
        #expect(SubtitleExporter.markdown(cues, title: "Demo") == "# Demo\n\n第一行  \n第二行\n\nSecond\n")
        #expect(!SubtitleExporter.markdown(cues).contains("-->"))
    }

    @Test func roundTrip() {
        for format in [SubtitleFormat.srt, .vtt] {
            let parsed = SubtitleParser.parse(SubtitleExporter.string(cues, format: format))
            #expect(parsed.map(\.text) == cues.map(\.text))
            #expect(parsed.map(\.startMs) == cues.map(\.startMs))
            #expect(parsed.map(\.endMs) == cues.map(\.endMs))
        }
    }
}

@Suite struct SiblingTests {
    @Test func findsSameNamedSubtitle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("movie.mp4")
        #expect(SubtitleFiles.sibling(for: video) == nil)
        try Data().write(to: dir.appendingPathComponent("movie.zh.vtt"))
        #expect(SubtitleFiles.sibling(for: video)?.lastPathComponent == "movie.zh.vtt")
        try Data().write(to: dir.appendingPathComponent("movie.srt"))
        #expect(SubtitleFiles.sibling(for: video)?.lastPathComponent == "movie.srt")
    }
}

@Suite struct LineEndingTests {
    @Test func detectsLineEndings() {
        #expect(LineEnding.detect(in: "1\r\n00:00:01,000 --> 00:00:02,000\r\nHi\r\n") == .crlf)
        #expect(LineEnding.detect(in: "1\n00:00:01,000 --> 00:00:02,000\nHi\n") == .lf)
        #expect(LineEnding.detect(in: "1\r00:00:01,000 --> 00:00:02,000\rHi\r") == .cr)
        #expect(LineEnding.detect(in: "no breaks") == .lf)
    }
}
