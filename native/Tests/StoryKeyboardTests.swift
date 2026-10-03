import AppKit

private final class KeyboardTestWindow: NSWindow {
    var key = true
    var focus: NSResponder?
    var testSheet: NSWindow?
    override var isKeyWindow: Bool { key }
    override var firstResponder: NSResponder? { focus }
    override var attachedSheet: NSWindow? { testSheet }
}

@main
struct StoryKeyboardTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message); checks += 1
        }
        let window = KeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        let view = StoryPlaybackKeys.KeyView()
        window.contentView = view
        view.enabled = true
        var actions: [StoryKeyAction] = []
        view.perform = { actions.append($0); return true }
        func event(_ code: UInt16, _ text: String = "", _ modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false, in target: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: (target ?? window).windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: repeatKey, keyCode: code)!
        }
        // Offscreen sandbox windows have number zero, so inject the event's window
        // identity while exercising the same AppKit event/focus routing as production.
        func route(_ event: NSEvent) -> NSEvent? { view.route(event, from: window) }
        let mappings: [(UInt16, String, NSEvent.ModifierFlags, StoryKeyAction)] = [
            (49, " ", [], .toggle), (15, "r", [], .replay),
            (123, "", [], .nudge(-1, false)), (124, "", [], .nudge(1, false)),
            (123, "", .shift, .nudge(-1, true)), (124, "", .shift, .nudge(1, true)),
            (126, "", [], .select(-1)), (125, "", [], .select(1)),
            (115, "", [], .start), (119, "", [], .end),
            (6, "z", .command, .undo), (6, "Z", [.command, .shift], .redo),
            (1, "s", .command, .save), (51, "", [], .remove), (117, "", [], .remove),
            (53, "", [], .clearSelection), (14, "E", [.command, .shift], .collapse),
            (44, "?", .shift, .help)
        ]
        for (code, text, flags, expected) in mappings {
            actions = []
            let keyEvent = event(code, text, flags)
            check(route(keyEvent) == nil && actions == [expected], "Route \(expected)")
            actions = []
            _ = route(event(code, text, flags, repeatKey: true))
            check(actions == (expected.repeats ? [expected] : []), "Repeat safety \(expected)")
        }
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, [.command, .shift], [.control, .shift]] {
            check(route(event(51, "", flags)) != nil, "Modified Delete stays native")
            check(route(event(49, " ", flags)) != nil, "Modified Space stays native")
        }
        check(route(event(0, "a", .command)) != nil, "Select all stays native")
        check(route(event(48, "\t")) != nil, "Tab stays native")
        check(route(event(36, "\r")) != nil, "Return stays native")
        check(route(event(15, "r", .control)) != nil, "Control-R stays native")
        for responder: NSResponder in [NSTextView(), NSTextField(), NSSlider(), NSStepper(), NSPopUpButton(), NSButton()] {
            window.focus = responder; actions = []
            for (code, text, flags, _) in mappings {
                check(route(event(code, text, flags)) != nil, "Focused control owns its keys")
            }
            check(actions.isEmpty, "No editor actions while typing or adjusting control")
        }
        let slider = NSSlider(), child = NSView()
        slider.addSubview(child); window.focus = child
        check(route(event(123)) != nil, "Nested native control owns arrows")
        window.focus = nil
        window.key = false
        check(route(event(49)) != nil, "Inactive window")
        window.key = true
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        check(view.route(event(49), from: other) != nil, "Other window")
        check(view.route(event(49), from: nil) != nil, "No event window")
        window.testSheet = other
        check(route(event(49)) != nil, "Sheet isolation")
        window.testSheet = nil
        view.enabled = false
        check(route(event(51)) != nil, "Trim, popover and picker isolation")
        view.enabled = true
        view.perform = { _ in false }
        check(route(event(53)) != nil, "Unhandled Escape is forwarded")
        window.contentView = nil
        check(view.monitor == nil, "Detached view removes event monitor")
        print("Passed \(checks) editor keyboard checks.")
    }
}
