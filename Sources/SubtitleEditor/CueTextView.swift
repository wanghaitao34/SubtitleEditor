import AppKit
import SwiftUI

/// Plain-text NSTextView for one cue. Return splits the cue at the caret, Backspace at the start
/// merges with the previous cue, Forward-Delete at the end merges with the next, Shift-Return (or Option-Return)
/// inserts a line break, and Tab / Shift-Tab move between cues.
struct CueTextView: NSViewRepresentable {
    var text: String
    var focusRequest: FocusRequest?
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
        let coordinator = context.coordinator
        coordinator.parent = self
        if tv.string != text && !tv.hasMarkedText() {
            if text == coordinator.syncedText {
                // The model hasn't changed since our last sync, so the text view holds newer local
                // edits (e.g. a just-committed IME composition). Push them instead of reverting.
                DispatchQueue.main.async { [weak tv] in if let tv { coordinator.sync(tv) } }
            } else {
                // External change (undo/redo, merge): replace the text, keeping the caret at the end if it was there.
                let sel = tv.selectedRange()
                let wasAtEnd = sel.location >= (tv.string as NSString).length
                tv.string = text
                let len = (text as NSString).length
                tv.setSelectedRange(NSRange(location: wasAtEnd ? len : min(sel.location, len), length: 0))
                coordinator.syncedText = text
            }
        } else if tv.string == text {
            coordinator.syncedText = text
        }
        if let focus = focusRequest, focus.token != coordinator.handledFocusToken {
            coordinator.focus(tv, request: focus, attempts: 10)
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
        /// Last text known to be identical in the model and the text view.
        var syncedText: String
        var handledFocusToken: UUID?
        private var pendingFocus = false

        init(_ parent: CueTextView) {
            self.parent = parent
            self.syncedText = parent.text
        }

        func focus(_ tv: NSTextView, request: FocusRequest, attempts: Int) {
            guard !pendingFocus else { return }
            pendingFocus = true
            DispatchQueue.main.async { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.pendingFocus = false
                guard self.handledFocusToken != request.token else { return }
                guard let window = tv.window else {
                    if attempts > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focus(tv, request: request, attempts: attempts - 1) }
                    }
                    return
                }
                self.handledFocusToken = request.token
                window.makeFirstResponder(tv)
                let s = tv.string
                let idx = s.index(s.startIndex, offsetBy: min(max(0, request.caret), s.count))
                tv.setSelectedRange(NSRange(location: idx.utf16Offset(in: s), length: 0))
                tv.scrollRangeToVisible(tv.selectedRange())
                self.parent.onFocusHandled()
            }
        }

        /// Sends the text view's current text to the model.
        func sync(_ tv: NSTextView) {
            guard !tv.hasMarkedText() else { return }
            let s = tv.string
            syncedText = s
            parent.onChange(s)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            sync(tv)
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
                sync(tv)
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
                sync(tv)
                parent.onMergePrevious()
                return true
            case #selector(NSResponder.deleteForward(_:)) where sel.location == length && sel.length == 0:
                sync(tv)
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

    // Committing an IME composition can post textDidChange while the marked text is still set,
    // so make sure the committed text reaches the model.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        (delegate as? CueTextView.Coordinator)?.sync(self)
    }

    override func unmarkText() {
        super.unmarkText()
        (delegate as? CueTextView.Coordinator)?.sync(self)
    }
}
