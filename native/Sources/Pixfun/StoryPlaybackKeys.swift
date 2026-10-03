import SwiftUI

enum StoryKeyAction: Equatable {
    case toggle, replay, nudge(Int, Bool), select(Int), start, end
    case undo, redo, save, remove, clearSelection, collapse, help

    var repeats: Bool {
        switch self { case .nudge, .select: return true; default: return false }
    }

    static func resolve(_ event: NSEvent) -> StoryKeyAction? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let letter = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command {
            switch letter { case "z": return .undo; case "s": return .save; default: return nil }
        }
        if modifiers == [.command, .shift] {
            switch letter { case "z": return .redo; case "e": return .collapse; default: return nil }
        }
        if modifiers == .shift {
            switch event.keyCode {
            case 123: return .nudge(-1, true)
            case 124: return .nudge(1, true)
            default: return event.characters == "?" ? .help : nil
            }
        }
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case 49: return .toggle
        case 123: return .nudge(-1, false)
        case 124: return .nudge(1, false)
        case 125: return .select(1)
        case 126: return .select(-1)
        case 115: return .start
        case 119: return .end
        case 51, 117: return .remove
        case 53: return .clearSelection
        default: return letter == "r" ? .replay : nil
        }
    }
}

/// Editor-local routing. Text editing, focused controls and modal UI keep their keys.
struct StoryPlaybackKeys: NSViewRepresentable {
    let enabled: Bool
    let perform: (StoryKeyAction) -> Bool
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) {
        view.enabled = enabled; view.perform = perform
    }
    final class KeyView: NSView {
        var enabled = false
        var perform: ((StoryKeyAction) -> Bool)?
        var monitor: Any?

        static func protectsFocus(_ firstResponder: NSResponder?) -> Bool {
            if firstResponder is NSTextView || firstResponder is NSTextField { return true }
            var view = firstResponder as? NSView
            while let current = view {
                if current is NSControl { return true }
                view = current.superview
            }
            return false
        }

        func route(_ event: NSEvent, from eventWindow: NSWindow?) -> NSEvent? {
            guard enabled, let window, window.isKeyWindow, eventWindow === window,
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !Self.protectsFocus(window.firstResponder),
                  let action = StoryKeyAction.resolve(event) else { return event }
            // Holding Delete, Space, Undo or Save must never apply the action repeatedly.
            if event.isARepeat && !action.repeats { return nil }
            return perform?(action) == true ? nil : event
        }
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.route(event, from: event.window)
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct StoryKeyboardHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard shortcuts").font(.headline)
            row("Play / pause", "Space")
            row("Replay current clip", "R")
            row("Select previous / next clip", "↑ / ↓")
            row("Step one frame", "← / →")
            row("Step one second", "⇧ ← / →")
            row("Jump to start / end", "Home / End")
            Divider()
            row("Undo / redo edit", "⌘ Z / ⇧ ⌘ Z")
            row("Remove selected clips", "Delete")
            row("Update preview", "⌘ S")
            row("Clear selection", "Esc")
            row("Collapse editor", "⇧ ⌘ E")
            Text("Inactive while typing or using a control. Removing clips keeps the original media.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 330)
    }
    private func row(_ label: String, _ keys: String) -> some View {
        HStack { Text(label); Spacer(); Text(keys).foregroundStyle(.secondary) }.font(.system(size: 12))
    }
}
