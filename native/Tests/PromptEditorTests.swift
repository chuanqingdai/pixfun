import AppKit
import SwiftUI

@main
struct PromptEditorTests {
    static func main() {
        _ = NSApplication.shared
        let scroll = PromptScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 1400, height: 120))
        editor.isRichText = false
        editor.font = .systemFont(ofSize: 16)
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineBreakMode = .byWordWrapping
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        scroll.documentView = editor
        let samples = [
            "Suggest a travel story using these videos. Explain the shot order and suggested durations. Give me a plan before creating anything.",
            String(repeating: "请用这些旅行照片和视频规划一个短片，保留完整人物和重要细节。", count: 4),
            "https://example.com/" + String(repeating: "long-path-without-spaces", count: 12),
            "First paragraph.\n" + String(repeating: "A longer second paragraph. ", count: 30)
        ]
        var checks = 0
        for text in samples {
            editor.string = text
            for width: CGFloat in [760, 280, 480] {
                scroll.setFrameSize(NSSize(width: width, height: 80))
                scroll.layoutSubtreeIfNeeded()
                scroll.synchronizeEditorLayout()
                let container = editor.textContainer!, layout = editor.layoutManager!
                layout.ensureLayout(for: container)
                precondition(abs(editor.frame.width - scroll.contentSize.width) < 1, "Document must track viewport")
                precondition(abs(container.containerSize.width - scroll.contentSize.width) < 1, "Text must track viewport")
                var lines = 0
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, used, _, _, _ in
                    lines += 1
                    precondition(used.maxX <= container.containerSize.width + 1, "Text must not overflow horizontally")
                }
                precondition(lines > 1, "Long input must wrap, including unbroken URLs")
                precondition(editor.string == text, "Reflow must preserve draft text")
                precondition(editor.frame.height >= layout.usedRect(for: container).height + 16, "Long content stays vertically reachable")
                checks += 1
            }
        }
        editor.string = String(repeating: "wrap this sentence naturally ", count: 30)
        scroll.setFrameSize(NSSize(width: 760, height: 80))
        scroll.layoutSubtreeIfNeeded(); scroll.synchronizeEditorLayout()
        let wideHeight = editor.frame.height
        scroll.setFrameSize(NSSize(width: 280, height: 80))
        scroll.layoutSubtreeIfNeeded(); scroll.synchronizeEditorLayout()
        precondition(editor.frame.height > wideHeight, "Narrowing the editor adds lines")
        print("Passed \(checks + 1) prompt wrapping and resize checks.")
    }
}
