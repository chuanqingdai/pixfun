import SwiftUI
import AppKit

// A plain native text view, with explicit insets and overlay scrolling. SwiftUI's
// TextEditor can reserve a legacy scroller gutter even for an empty document.
struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var requestFocus: Bool
    var minimumHeight: CGFloat = 120
    var maximumHeight: CGFloat = 220
    var placeholder = "Describe your story, length, and style…"
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PromptScrollView {
        let scroll = PromptScrollView()
        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = NSFont(name: "DMSans-Regular", size: 16) ?? .systemFont(ofSize: 16)
        editor.textColor = NSColor(Color.pixfunInk)
        editor.insertionPointColor = NSColor(Color.pixfunGold)
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineBreakMode = .byWordWrapping
        editor.textContainer?.maximumNumberOfLines = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        editor.defaultParagraphStyle = paragraph
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.setAccessibilityLabel("Video requirements")
        editor.delegate = context.coordinator
        editor.placeholder = placeholder
        editor.string = text
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        let coordinator = context.coordinator
        scroll.onLayout = { [weak editor, weak coordinator] in
            if let editor { coordinator?.measure(editor) }
        }
        scroll.synchronizeEditorLayout()
        return scroll
    }
    func updateNSView(_ scroll: PromptScrollView, context: Context) {
        guard let editor = scroll.documentView as? PromptTextView else { return }
        context.coordinator.parent = self
        editor.placeholder = placeholder
        scroll.synchronizeEditorLayout()
        // Do not replace text while the user is composing with a Chinese/Japanese IME.
        if editor.string != text && !editor.hasMarkedText() {
            editor.string = text
            editor.undoManager?.removeAllActions()
            editor.needsDisplay = true
            scroll.synchronizeEditorLayout()
            context.coordinator.measure(editor)
        }
        if requestFocus && !context.coordinator.focusing {
            context.coordinator.focusing = true
            DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
                guard let coordinator else { return }
                if let editor, let window = editor.window { window.makeFirstResponder(editor) }
                coordinator.parent.requestFocus = false
                coordinator.focusing = false
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        var focusing = false
        private var measuredHeight: CGFloat = 120
        init(_ parent: PromptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? PromptTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
            (editor.enclosingScrollView as? PromptScrollView)?.synchronizeEditorLayout()
            measure(editor)
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  !textView.hasMarkedText(), let submit = parent.onSubmit,
                  !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) else { return false }
            submit()
            return true
        }
        func measure(_ editor: NSTextView) {
            guard let layout = editor.layoutManager, let container = editor.textContainer else { return }
            layout.ensureLayout(for: container)
            let next = min(parent.maximumHeight, max(parent.minimumHeight, ceil(layout.usedRect(for: container).height + 16)))
            guard abs(next - measuredHeight) > 0.5 else { return }
            measuredHeight = next
            DispatchQueue.main.async { [weak self] in
                guard let self, self.measuredHeight == next else { return }
                self.parent.height = next
            }
        }
    }
}

final class PromptScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        synchronizeEditorLayout()
        onLayout?()
    }

    // SwiftUI can resize the clip view without resizing NSTextView's document.
    // Pin both document and text-container width to the viewport before measuring.
    // A hidden horizontal scroller alone does not make a text view wrap.
    func synchronizeEditorLayout() {
        guard let editor = documentView as? NSTextView,
              let container = editor.textContainer, let layout = editor.layoutManager else { return }
        let width = contentSize.width
        guard width > 0 else { return }
        editor.minSize = NSSize(width: width, height: 0)
        editor.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        if abs(editor.frame.width - width) > 0.5 {
            editor.setFrameSize(NSSize(width: width, height: editor.frame.height))
        }
        let textWidth = max(1, width - editor.textContainerInset.width * 2)
        if abs(container.containerSize.width - textWidth) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        let height = max(contentSize.height, ceil(layout.usedRect(for: container).height + editor.textContainerInset.height * 2))
        if abs(editor.frame.height - height) > 0.5 {
            editor.setFrameSize(NSSize(width: width, height: height))
        }
    }
}

final class PromptTextView: NSTextView {
    var placeholder = "Describe your story, length, and style…" { didSet { if oldValue != placeholder { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = textContainerOrigin
        let rect = NSRect(x: origin.x, y: origin.y, width: max(0, bounds.width - origin.x * 2), height: bounds.height - origin.y)
        (placeholder as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(Color.pixfunSubtle)
        ])
    }
}
