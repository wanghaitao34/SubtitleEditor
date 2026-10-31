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
                VStack(spacing: 8) {
                    Image(systemName: "captions.bubble").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("还没有字幕").font(.headline)
                    Text("打开 SRT / VTT 字幕文件，或点击 + 新建一条").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.cues.enumerated()), id: \.element.id) { index, cue in
                                CueRow(model: model, cue: cue, number: index + 1)
                                    .id(cue.id)
                                Divider()
                            }
                        }
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
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text(model.subtitleURL?.lastPathComponent ?? "未保存的字幕")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(Timecode.format(clock.currentMs, separator: "."))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.cues.count) 条字幕").foregroundStyle(.secondary)
            Spacer()
            Toggle("跟随播放", isOn: $model.followPlayback)
            Toggle("视频叠加字幕", isOn: $model.showOverlay)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .help("回车：在光标处拆分为两条 · ⌥回车：条内换行 · 行首退格：与上一条合并 · 行尾 Delete：与下一条合并 · Tab：下一条")
    }
}

struct CueRow: View {
    @ObservedObject var model: EditorModel
    let cue: SubtitleCue
    let number: Int

    private var isActive: Bool { model.activeCueID == cue.id }
    private var isSelected: Bool { model.selectedCueID == cue.id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                TimecodeField(ms: cue.startMs) { model.setTime(cue.id, startMs: $0) }
                TimecodeField(ms: cue.endMs) { model.setTime(cue.id, endMs: $0) }
                Text(String(format: "%.2f 秒", Double(cue.durationMs) / 1000))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.select(cue.id) }

            CueTextView(
                text: cue.text,
                focusCaret: model.focusRequest?.cueID == cue.id ? model.focusRequest?.caret : nil,
                onChange: { model.updateText(cue.id, $0) },
                onBeginEditing: { if model.selectedCueID != cue.id { model.select(cue.id) } },
                onSplit: { model.split(cue.id, atCharacter: $0) },
                onMergePrevious: { model.mergeWithPrevious(cue.id) },
                onMergeNext: { model.mergeWithNext(cue.id) },
                onMove: { model.focusAdjacent(to: cue.id, delta: $0) },
                onFocusHandled: { model.focusRequest = nil }
            )
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2))
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.16) : (isSelected ? Color.secondary.opacity(0.08) : .clear))
        .contextMenu {
            Button("跳转到此处") { model.select(cue.id) }
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
}

/// Editable `HH:MM:SS.mmm` field; commits on Return or focus loss, reverts on invalid input.
struct TimecodeField: NSViewRepresentable {
    let ms: Int
    let onCommit: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: Timecode.format(ms, separator: "."))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
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
