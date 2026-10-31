import AppKit
import AVFoundation
import Combine
import SubtitleCore
import UniformTypeIdentifiers

struct FocusRequest: Equatable {
    let cueID: UUID
    let caret: Int
    let token = UUID()
}

/// Lightweight clock published separately so the cue list doesn't re-render on every tick.
final class PlaybackClock: ObservableObject {
    @Published var currentMs: Int = 0
    @Published var isPlaying = false
}

@MainActor
final class EditorModel: ObservableObject {
    static let videoExtensions = ["mp4", "mov", "m4v"]
    static let subtitleExtensions = SubtitleFiles.subtitleExtensions

    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var subtitleURL: URL?
    @Published private(set) var sourceFormat: SubtitleFormat = .srt
    @Published private(set) var videoURL: URL?
    @Published private(set) var isDirty = false
    @Published private(set) var activeCueID: UUID?
    @Published var selectedCueID: UUID?
    @Published var focusRequest: FocusRequest?
    @Published var followPlayback = true
    @Published var showOverlay = true
    @Published var alertMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let player = AVPlayer()
    let clock = PlaybackClock()

    private var undoStack: [[SubtitleCue]] = []
    private var redoStack: [[SubtitleCue]] = []
    private var lastTextEditCueID: UUID?
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.playbackTick(time) }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate != 0
            DispatchQueue.main.async { self?.clock.isPlaying = playing }
        }
    }

    // MARK: - Derived

    var windowTitle: String {
        let name = subtitleURL?.lastPathComponent ?? videoURL?.lastPathComponent ?? "字幕编辑器"
        return isDirty ? "\(name) — 已编辑" : name
    }

    var activeCueText: String? {
        guard let id = activeCueID else { return nil }
        return cues.first { $0.id == id }?.text
    }

    func index(of id: UUID) -> Int? { cues.firstIndex { $0.id == id } }

    var selectedIndex: Int? { selectedCueID.flatMap(index(of:)) }

    // MARK: - Playback

    private func playbackTick(_ time: CMTime) {
        let ms = time.isNumeric ? Int((time.seconds * 1000).rounded()) : 0
        if clock.currentMs != ms { clock.currentMs = ms }
        let newActive = SubtitleEditing.activeIndex(in: cues, at: ms).map { cues[$0].id }
        if newActive != activeCueID { activeCueID = newActive }
    }

    func seek(toMs ms: Int) {
        player.seek(to: CMTime(value: CMTimeValue(max(0, ms)), timescale: 1000),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        clock.currentMs = ms
        activeCueID = SubtitleEditing.activeIndex(in: cues, at: ms).map { cues[$0].id }
    }

    func select(_ id: UUID, seek shouldSeek: Bool = true) {
        selectedCueID = id
        if shouldSeek, let cue = cues.first(where: { $0.id == id }) { seek(toMs: cue.startMs) }
    }

    func togglePlay() {
        guard player.currentItem != nil else { return }
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func skip(seconds: Double) {
        seek(toMs: clock.currentMs + Int(seconds * 1000))
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(cues)
        if undoStack.count > 500 { undoStack.removeFirst() }
        redoStack.removeAll()
        updateUndoState()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func commit(_ newCues: [SubtitleCue]) {
        pushUndo()
        lastTextEditCueID = nil
        cues = newCues
        isDirty = true
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(cues)
        cues = prev
        lastTextEditCueID = nil
        isDirty = true
        updateUndoState()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(cues)
        cues = next
        lastTextEditCueID = nil
        isDirty = true
        updateUndoState()
    }

    // MARK: - Editing

    func updateText(_ id: UUID, _ text: String) {
        guard let i = index(of: id), cues[i].text != text else { return }
        // Consecutive typing in the same cue is coalesced into a single undo step.
        if lastTextEditCueID != id { pushUndo(); lastTextEditCueID = id }
        cues[i].text = text
        isDirty = true
    }

    func split(_ id: UUID, atCharacter offset: Int) {
        guard let i = index(of: id) else { return }
        guard let result = SubtitleEditing.split(cues, at: i, characterOffset: offset) else {
            NSSound.beep()
            return
        }
        commit(result)
        selectedCueID = result[i + 1].id
        focusRequest = FocusRequest(cueID: result[i + 1].id, caret: 0)
    }

    func mergeWithNext(_ id: UUID) {
        guard let i = index(of: id), let result = SubtitleEditing.mergeWithNext(cues, at: i) else {
            NSSound.beep()
            return
        }
        let caret = cues[i].text.trimmingCharacters(in: .whitespacesAndNewlines).count
        commit(result)
        selectedCueID = result[i].id
        focusRequest = FocusRequest(cueID: result[i].id, caret: caret)
    }

    func mergeWithPrevious(_ id: UUID) {
        guard let i = index(of: id), i > 0 else { NSSound.beep(); return }
        mergeWithNext(cues[i - 1].id)
    }

    func mergeSelectedWithNext() {
        if let id = selectedCueID { mergeWithNext(id) }
    }

    func deleteCue(_ id: UUID) {
        guard let i = index(of: id) else { return }
        var result = cues
        result.remove(at: i)
        commit(result)
        selectedCueID = result.indices.contains(i) ? result[i].id : result.last?.id
    }

    func deleteSelected() {
        if let id = selectedCueID { deleteCue(id) }
    }

    /// Inserts an empty cue after `id` (or at the playhead if nothing is selected).
    func insertCue(after id: UUID?) {
        var result = cues
        let newCue: SubtitleCue
        let insertAt: Int
        if let id, let i = index(of: id) {
            let start = cues[i].endMs
            let nextStart = cues.indices.contains(i + 1) ? cues[i + 1].startMs : start + 2000
            newCue = SubtitleCue(startMs: start, endMs: max(start + 500, min(start + 2000, nextStart)), text: "")
            insertAt = i + 1
        } else {
            let start = clock.currentMs
            newCue = SubtitleCue(startMs: start, endMs: start + 2000, text: "")
            insertAt = cues.firstIndex { $0.startMs > start } ?? cues.count
        }
        result.insert(newCue, at: insertAt)
        commit(result)
        selectedCueID = newCue.id
        focusRequest = FocusRequest(cueID: newCue.id, caret: 0)
    }

    func setTime(_ id: UUID, startMs: Int? = nil, endMs: Int? = nil) {
        guard let i = index(of: id) else { return }
        var cue = cues[i]
        if let startMs { cue.startMs = max(0, startMs) }
        if let endMs { cue.endMs = max(0, endMs) }
        if cue.endMs < cue.startMs {
            if startMs != nil { cue.endMs = cue.startMs } else { cue.startMs = cue.endMs }
        }
        guard cue != cues[i] else { return }
        var result = cues
        result[i] = cue
        commit(result)
    }

    func setSelectedStartToPlayhead() {
        if let id = selectedCueID { setTime(id, startMs: clock.currentMs) }
    }

    func setSelectedEndToPlayhead() {
        if let id = selectedCueID { setTime(id, endMs: clock.currentMs) }
    }

    func focusAdjacent(to id: UUID, delta: Int) {
        guard let i = index(of: id), cues.indices.contains(i + delta) else { return }
        let target = cues[i + delta]
        select(target.id)
        focusRequest = FocusRequest(cueID: target.id, caret: delta > 0 ? 0 : target.text.count)
    }

    // MARK: - Opening

    func presentOpenPanel(kinds: [String]? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let exts = kinds ?? (Self.subtitleExtensions + Self.videoExtensions)
        panel.allowedContentTypes = exts.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func open(_ urls: [URL]) {
        // Open videos first so an explicitly chosen subtitle wins over the auto-detected one.
        let videos = urls.filter { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
        let subs = urls.filter { Self.subtitleExtensions.contains($0.pathExtension.lowercased()) }
        if videos.isEmpty && subs.isEmpty, let first = urls.first {
            alertMessage = "不支持的文件类型：\(first.lastPathComponent)\n支持 SRT、VTT 字幕和 MP4、MOV、M4V 视频。"
            return
        }
        if let video = videos.first { openVideo(video, autoLoadSubtitle: subs.isEmpty) }
        if let sub = subs.first { openSubtitle(sub) }
    }

    func openVideo(_ url: URL, autoLoadSubtitle: Bool = true) {
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        videoURL = url
        seek(toMs: 0)
        if autoLoadSubtitle, let sub = SubtitleFiles.sibling(for: url), sub != subtitleURL {
            openSubtitle(sub)
        }
    }

    func openSubtitle(_ url: URL) {
        guard confirmDiscardChanges() else { return }
        do {
            let parsed = try SubtitleParser.parse(data: Data(contentsOf: url))
            cues = parsed
            subtitleURL = url
            sourceFormat = url.pathExtension.lowercased() == "vtt" ? .vtt : .srt
            isDirty = false
            undoStack.removeAll()
            redoStack.removeAll()
            lastTextEditCueID = nil
            updateUndoState()
            selectedCueID = nil
            activeCueID = SubtitleEditing.activeIndex(in: cues, at: clock.currentMs).map { cues[$0].id }
        } catch {
            alertMessage = "无法打开字幕 \(url.lastPathComponent)：\(error.localizedDescription)"
        }
    }

    /// Returns true if it is OK to discard the current subtitles.
    func confirmDiscardChanges() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "字幕已修改，是否保存？"
        alert.informativeText = "如果不保存，你的修改将会丢失。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: - Saving / exporting

    private var baseName: String {
        (subtitleURL ?? videoURL)?.deletingPathExtension().lastPathComponent ?? "字幕"
    }

    @discardableResult
    func save() -> Bool {
        guard let url = subtitleURL else { return export(.srt) }
        return write(sourceFormat, to: url, markClean: true)
    }

    @discardableResult
    func export(_ format: SubtitleFormat) -> Bool {
        guard !cues.isEmpty else { alertMessage = "没有可导出的字幕。"; return false }
        let panel = NSSavePanel()
        panel.title = "导出 \(format.rawValue.uppercased())"
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        if let dir = (subtitleURL ?? videoURL)?.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        // Exporting to SRT/VTT with no current file adopts it as the document.
        let adopt = subtitleURL == nil && (format == .srt || format == .vtt)
        let ok = write(format, to: url, markClean: adopt)
        if ok && adopt { subtitleURL = url; sourceFormat = format }
        return ok
    }

    private func write(_ format: SubtitleFormat, to url: URL, markClean: Bool) -> Bool {
        do {
            let data = SubtitleExporter.data(cues, format: format, title: baseName)
            try data.write(to: url, options: .atomic)
            if markClean { isDirty = false }
            return true
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }
}
