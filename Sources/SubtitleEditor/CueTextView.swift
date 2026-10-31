import AppKit
import SwiftUI

/// Plain-text NSTextView for one cue. Return splits the cue at the caret, Backspace at the start
/// merges with the previous cue, Forward-Delete at the end merges with the next, Shift-Return (or Option-Return)
/// inserts a line break, and Tab / Shift-Tab move between cues.
struct CueTextView: NSViewRepresentable {
    var text: String
    var focusCaret: Int?
    var onChange: (String) -> Void
    var onActivate: () -> Void
    var onSplit: (Int) -> Void
    var onMergePrevious: () -> Void
    var onMergeNext: () -> Void
    var onMove: (Int) -> Void
    var onFocusHandled: () -> Void

    static let inset = NSSize(width: 0, height: 1)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let tv = ClickableTextView()
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = false // undo is handled by the document model
        tv.font = .systemFont(ofSize: 14)
        tv.drawsBackground = false
        tv.textContainerInset = Self.inset
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.string = text
        tv.delegate = context.coordinator
        tv.onMouseDown = { [weak coordinator = context.coordinator] in coordinator?.parent.onActivate() }
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        context.coordinator.parent = self
        if tv.string != text && !tv.hasMarkedText() {
            let sel = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
        if let caret = focusCaret {
            context.coordinator.focus(tv, caret: caret, attempts: 10)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: NSTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 300, 60)
        guard let container = tv.textContainer, let layout = tv.layoutManager else { return nil }
        container.containerSize = NSSize(width: width - Self.inset.width * 2, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let lineHeight = layout.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 14))
        return CGSize(width: width, height: ceil(max(used, lineHeight) + Self.inset.height * 2))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CueTextView
        private var pendingFocus = false

        init(_ parent: CueTextView) { self.parent = parent }

        func focus(_ tv: NSTextView, caret: Int, attempts: Int) {
            guard !pendingFocus else { return }
            pendingFocus = true
            DispatchQueue.main.async { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.pendingFocus = false
                guard let window = tv.window else {
                    if attempts > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focus(tv, caret: caret, attempts: attempts - 1) }
                    }
                    return
                }
                window.makeFirstResponder(tv)
                let s = tv.string
                let idx = s.index(s.startIndex, offsetBy: min(max(0, caret), s.count))
                tv.setSelectedRange(NSRange(location: idx.utf16Offset(in: s), length: 0))
                tv.scrollRangeToVisible(tv.selectedRange())
                self.parent.onFocusHandled()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, !tv.hasMarkedText() else { return }
            parent.onChange(tv.string)
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            if tv.hasMarkedText() { return false }
            let sel = tv.selectedRange()
            let length = (tv.string as NSString).length
            switch selector {
            case #selector(NSResponder.insertNewline(_:)) where NSApp.currentEvent?.modifierFlags.contains(.shift) == true:
                tv.insertText("\n", replacementRange: sel)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onChange(tv.string)
                let s = tv.string
                let utf16 = min(sel.location, length)
                let offset = s.distance(from: s.startIndex, to: String.Index(utf16Offset: utf16, in: s))
                parent.onSplit(offset)
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                tv.insertText("\n", replacementRange: sel)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where sel.location == 0 && sel.length == 0:
                parent.onChange(tv.string)
                parent.onMergePrevious()
                return true
            case #selector(NSResponder.deleteForward(_:)) where sel.location == length && sel.length == 0:
                parent.onChange(tv.string)
                parent.onMergeNext()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onMove(-1)
                return true
            default:
                return false
            }
        }
    }
}

/// Reports every click so tapping a cue's text seeks the video to that cue.
final class ClickableTextView: NSTextView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}
