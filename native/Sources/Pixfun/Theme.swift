import SwiftUI
import AppKit
import CoreText

// Keep these tokens aligned with public/palette.css, the original web workspace.
extension Color {
    init(pixfunHex: UInt32) {
        self.init(.sRGB, red: Double((pixfunHex >> 16) & 255) / 255,
                  green: Double((pixfunHex >> 8) & 255) / 255,
                  blue: Double(pixfunHex & 255) / 255, opacity: 1)
    }
    static let pixfunBackground = Color(pixfunHex: 0x151819)
    static let pixfunSidebar = Color(pixfunHex: 0x171b1d)
    static let pixfunSurface = Color(pixfunHex: 0x1d2123)
    static let pixfunRaised = Color(pixfunHex: 0x272c2f)
    static let pixfunHover = Color(pixfunHex: 0x303639)
    static let pixfunLine = Color(pixfunHex: 0x363e42)
    static let pixfunInk = Color(pixfunHex: 0xe9ebe8)
    static let pixfunMuted = Color(pixfunHex: 0xb1b9bc)
    static let pixfunSubtle = Color(pixfunHex: 0x9aa5aa)
    static let pixfunGold = Color(pixfunHex: 0xd7b581)
    static let pixfunGoldHover = Color(pixfunHex: 0xe5c796)
    static let pixfunBrandSoft = Color(pixfunHex: 0x343027)
    static let pixfunOnAccent = Color(pixfunHex: 0x20221f)
    static let pixfunFocus = Color(pixfunHex: 0x9bbfd9)
}

enum PixfunTypography {
    static func register() {
        for name in ["dm-sans-regular", "dm-sans-semibold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func pixfun(_ size: CGFloat = 14, semibold: Bool = false) -> Font {
        .custom(semibold ? "DMSans-SemiBold" : "DMSans-Regular", size: size)
    }
}

enum PixfunButtonKind { case secondary, primary, quiet }

struct PixfunButtonStyle: ButtonStyle {
    var kind: PixfunButtonKind = .secondary
    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind)
    }
    private struct StyledButton: View {
        let configuration: ButtonStyle.Configuration
        let kind: PixfunButtonKind
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @State private var hovered = false
        var fill: Color {
            if !enabled { return kind == .quiet ? .clear : .pixfunRaised }
            if kind == .primary { return hovered ? .pixfunGoldHover : .pixfunGold }
            return hovered ? .pixfunRaised : kind == .quiet ? .clear : .pixfunSurface
        }
        var body: some View {
            configuration.label
                .font(.pixfun(13, semibold: true))
                .foregroundStyle(!enabled ? Color.pixfunSubtle : kind == .primary ? .pixfunOnAccent : hovered ? .pixfunInk : .pixfunMuted)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(fill.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : kind == .secondary ? .pixfunLine : .clear, lineWidth: focused ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}

struct PixfunSearchField: View {
    var placeholder: String
    @Binding var text: String
    var clear: (() -> Void)?
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Color.pixfunSubtle)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundColor(.pixfunSubtle)).textFieldStyle(.plain).font(.pixfun(13)).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { if let clear { clear() } else { text = "" } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.pixfunMuted)
                        .frame(width: 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 11).frame(height: 36)
            .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunSubtle : .pixfunLine))
    }
}

struct PixfunCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Card(configuration: configuration) }
    private struct Card: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(hovered || configuration.isPressed ? Color.pixfunRaised : .pixfunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Color.pixfunFocus : hovered ? .pixfunSubtle : .pixfunLine))
                .onHover { hovered = $0 }
        }
    }
}

struct PixfunNavigationButton: View {
    let page: WorkspacePage
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.symbol).font(.system(size: 17, weight: .regular)).frame(width: 22)
                Text(page.rawValue).font(.pixfun(14, semibold: selected))
                Spacer(minLength: 0)
            }.foregroundStyle(selected ? Color.pixfunGold : hovered ? .pixfunInk : .pixfunMuted)
                .padding(.horizontal, 14).frame(height: 44)
                .background(selected ? Color.pixfunBrandSoft : hovered ? .pixfunRaised : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct PixfunLogo: View {
    var body: some View {
        // Exact approved web lockup. Its black matte is composited away just as
        // the website does; the symbol and lettering are not redrawn or retyped.
        GeometryReader { _ in
            if let url = Bundle.main.url(forResource: "pixfun-lockup-v2", withExtension: "png", subdirectory: "Brand"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: 218, height: 218 * 362 / 1086)
                    .offset(x: -31, y: -17)
            }
        }.frame(width: 156, height: 42).clipped().blendMode(.screen)
            .accessibilityElement(children: .ignore).accessibilityLabel("Pixfun")
    }
}

// Native window chrome remains draggable, but no longer introduces a light-gray toolbar.
struct PixfunWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AppearanceView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class AppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.backgroundColor = NSColor(Color.pixfunBackground)
        }
    }
}
