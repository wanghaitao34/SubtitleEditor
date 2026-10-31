import AppKit
import SubtitleCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = EditorModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (not inside an .app bundle).
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let urls = CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty { model.open(urls) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.open(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.confirmDiscardChanges() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SubtitleEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("字幕编辑器", id: "main") {
            ContentView(model: appDelegate.model)
        }
        .defaultSize(width: 1280, height: 760)
        .commands { EditorCommands(model: appDelegate.model) }
    }
}

struct EditorCommands: Commands {
    @ObservedObject var model: EditorModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开…") { model.presentOpenPanel() }
                .keyboardShortcut("o")
            Button("打开视频…") { model.presentOpenPanel(kinds: EditorModel.videoExtensions) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("打开字幕…") { model.presentOpenPanel(kinds: EditorModel.subtitleExtensions) }
                .keyboardShortcut("o", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存") { model.save() }
                .keyboardShortcut("s")
                .disabled(model.cues.isEmpty)
            Menu("导出") {
                Button("SRT（Windows 格式）…") { model.export(.srt) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("VTT…") { model.export(.vtt) }
                Divider()
                Button("纯文本 TXT（无时间码）…") { model.export(.txt) }
                Button("Markdown MD（无时间码）…") { model.export(.md) }
            }
            .disabled(model.cues.isEmpty)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { model.undo() }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
            Button("重做") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }
        CommandMenu("字幕") {
            Button("与下一条合并") { model.mergeSelectedWithNext() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model.selectedCueID == nil)
            Button("在后面插入新字幕") { model.insertCue(after: model.selectedCueID) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("删除选中字幕") { model.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.selectedCueID == nil)
            Divider()
            Button("开始时间设为当前位置") { model.setSelectedStartToPlayhead() }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(model.selectedCueID == nil)
            Button("结束时间设为当前位置") { model.setSelectedEndToPlayhead() }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(model.selectedCueID == nil)
        }
        CommandMenu("播放") {
            Button("播放 / 暂停") { model.togglePlay() }
                .keyboardShortcut(.return, modifiers: [.command])
            Button("后退 2 秒") { model.skip(seconds: -2) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("前进 2 秒") { model.skip(seconds: 2) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
    }
}
