import SubtitleCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HSplitView {
            VideoPane(model: model)
                .frame(minWidth: 420, minHeight: 300)
            CueListPane(model: model, clock: model.clock)
                .frame(minWidth: 380, idealWidth: 460)
        }
        .frame(minWidth: 900, minHeight: 520)
        .navigationTitle(model.windowTitle)
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls)
            return true
        }
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("好") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .background(WindowEditedMarker(isEdited: model.isDirty))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.presentOpenPanel(kinds: EditorModel.videoExtensions) } label: {
                Label("打开视频", systemImage: "film")
            }.help("打开视频（自动加载同名字幕）")
            Button { model.presentOpenPanel(kinds: EditorModel.subtitleExtensions) } label: {
                Label("打开字幕", systemImage: "captions.bubble")
            }.help("打开 SRT / VTT 字幕")
        }
        ToolbarItemGroup {
            PlayPauseButton(model: model, clock: model.clock)
            Button { model.mergeSelectedWithNext() } label: {
                Label("与下一条合并", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .help("将选中字幕与下一条合并（⇧⌘M）")
            .disabled(model.selectedCueID == nil)
            Button { model.insertCue(after: model.selectedCueID) } label: {
                Label("插入字幕", systemImage: "plus")
            }.help("在选中字幕后插入新字幕")
            Menu {
                Button("SRT（Windows 格式）…") { model.export(.srt) }
                Button("VTT…") { model.export(.vtt) }
                Divider()
                Button("纯文本 TXT（无时间码）…") { model.export(.txt) }
                Button("Markdown MD（无时间码）…") { model.export(.md) }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("导出字幕")
            .disabled(model.cues.isEmpty)
        }
    }
}

private struct PlayPauseButton: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        Button { model.togglePlay() } label: {
            Label("播放/暂停", systemImage: clock.isPlaying ? "pause.fill" : "play.fill")
        }
        .help("播放 / 暂停（⌘↩）")
        .disabled(model.videoURL == nil)
    }
}

/// Shows the "edited" dot in the window's close button.
private struct WindowEditedMarker: NSViewRepresentable {
    var isEdited: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.isDocumentEdited = isEdited }
    }
}

struct CueListPane: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.cues.isEmpty {
                VStack(spacing: 6) {
                    Text("还没有字幕").font(.headline)
                    Text("打开 SRT / VTT 文件，或拖到窗口中").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.cues.enumerated()), id: \.element.id) { index, cue in
                                CueRow(model: model, cue: cue, number: index + 1)
                                    .id(cue.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: model.activeCueID) { _, id in
                        guard model.followPlayback, clock.isPlaying, let id else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.focusRequest) { _, request in
                        guard let request else { return }
                        proxy.scrollTo(request.cueID)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.cues.isEmpty ? "字幕" : "\(model.cues.count) 条字幕")
                .font(.callout.weight(.medium))
            Spacer()
            Text(CueRow.shortTime(clock.currentMs))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Menu {
                Toggle("播放时自动滚动", isOn: $model.followPlayback)
                Toggle("在视频上显示字幕", isOn: $model.showOverlay)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .help("单击：跳转视频 · 回车：拆分 · ⌥回车：条内换行 · 行首⌫ / 行尾Delete：合并 · 双击时间码：编辑时间")
    }
}

struct CueRow: View {
    @ObservedObject var model: EditorModel
    let cue: SubtitleCue
    let number: Int

    private var isActive: Bool { model.activeCueID == cue.id }
    private var isSelected: Bool { model.selectedCueID == cue.id }

    /// `MM:SS.mmm`, with hours only when needed.
    static func shortTime(_ ms: Int) -> String {
        let full = Timecode.format(ms, separator: ".")
        return ms < 3_600_000 ? String(full.dropFirst(3)) : full
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Self.shortTime(cue.startMs))  →  \(Self.shortTime(cue.endMs))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .onTapGesture(count: 2) { model.timeEditCueID = cue.id }
                    .popover(isPresented: Binding(
                        get: { model.timeEditCueID == cue.id },
                        set: { if !$0 { model.timeEditCueID = nil } }
                    )) {
                        timeEditor
                    }
                CueTextView(
                    text: cue.text,
                    focusCaret: model.focusRequest?.cueID == cue.id ? model.focusRequest?.caret : nil,
                    onChange: { model.updateText(cue.id, $0) },
                    onActivate: { model.select(cue.id) },
                    onSplit: { model.split(cue.id, atCharacter: $0) },
                    onMergePrevious: { model.mergeWithPrevious(cue.id) },
                    onMergeNext: { model.mergeWithNext(cue.id) },
                    onMove: { model.focusAdjacent(to: cue.id, delta: $0) },
                    onFocusHandled: { model.focusRequest = nil }
                )
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive { Rectangle().fill(Color.accentColor).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(cue.id) }
        .contextMenu {
            Button("跳转到此处") { model.select(cue.id) }
            Button("编辑时间…") { model.timeEditCueID = cue.id }
            Divider()
            Button("与上一条合并") { model.mergeWithPrevious(cue.id) }
            Button("与下一条合并") { model.mergeWithNext(cue.id) }
            Button("在后面插入新字幕") { model.insertCue(after: cue.id) }
            Divider()
            Button("开始时间设为当前播放位置") { model.setTime(cue.id, startMs: model.clock.currentMs) }
            Button("结束时间设为当前播放位置") { model.setTime(cue.id, endMs: model.clock.currentMs) }
            Divider()
            Button("删除此条", role: .destructive) { model.deleteCue(cue.id) }
        }
    }

    private var rowBackground: Color {
        if isActive { return Color.accentColor.opacity(0.12) }
        if isSelected { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var timeEditor: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("开始").foregroundStyle(.secondary)
                TimecodeField(ms: cue.startMs) { model.setTime(cue.id, startMs: $0) }.frame(width: 110)
            }
            GridRow {
                Text("结束").foregroundStyle(.secondary)
                TimecodeField(ms: cue.endMs) { model.setTime(cue.id, endMs: $0) }.frame(width: 110)
            }
        }
        .font(.callout)
        .padding(12)
    }
}

/// Editable `HH:MM:SS.mmm` field; commits on Return or focus loss, reverts on invalid input.
struct TimecodeField: NSViewRepresentable {
    let ms: Int
    let onCommit: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: Timecode.format(ms, separator: "."))
        field.isBezeled = true
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commitAction(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil {
            field.stringValue = Timecode.format(ms, separator: ".")
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimecodeField
        init(_ parent: TimecodeField) { self.parent = parent }

        @objc func commitAction(_ sender: NSTextField) { commit(sender) }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField { commit(field) }
        }

        private func commit(_ field: NSTextField) {
            if let value = Timecode.parse(field.stringValue), value != parent.ms {
                parent.onCommit(value)
            } else {
                field.stringValue = Timecode.format(parent.ms, separator: ".")
            }
        }
    }
}
