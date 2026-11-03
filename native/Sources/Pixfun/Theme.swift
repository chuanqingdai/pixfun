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

    // Cool chat, recessed preview, lighter neutral story rail. Keep card and input
    // surfaces distinct without changing the rest of the app's dark palette.
    static let pixfunStoryChat = Color(pixfunHex: 0x1e262c)
    static let pixfunStoryPreview = Color(pixfunHex: 0x101314)
    static let pixfunStoryRail = Color(pixfunHex: 0x282c2c)
    static let pixfunStoryCard = Color(pixfunHex: 0x303637)
    static let pixfunStoryInput = Color(pixfunHex: 0x2c3438)
    static let pixfunStoryInputLine = Color(pixfunHex: 0x526168)
}

enum PixfunTypography {
    static func register() {
        for name in ["dm-sans-regular", "dm-sans-semibold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// One semantic palette for toolbar categories, card chips and detail groups.
/// Labels/icons remain visible so color is never the only category cue.
enum MediaTagPalette {
    static func facet(_ facet: MediaFacet) -> Color {
        switch facet {
        case .location: return Color(pixfunHex: 0x9EC9EE)
        case .scene: return Color(pixfunHex: 0x9DD4BC)
        case .subject: return Color(pixfunHex: 0xCEBAED)
        case .activity: return .pixfunGold
        }
    }
    static let technique = Color(pixfunHex: 0xA9C5D3)
    static let story = Color(pixfunHex: 0xE3B6B4)
    static let detail = Color.pixfunMuted
}

extension Font {
    static func pixfun(_ size: CGFloat = 14, semibold: Bool = false) -> Font {
        // Native UI typography: SF for Latin and the system's Chinese fallback.
        .system(size: size, weight: semibold ? .semibold : .regular)
    }
}

/// A shared selection surface for source selection and advanced settings.
struct SyncSelectionLabel: View {
    let title: String
    let symbol: String
    var accessory = "chevron.down"
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 20)
                .foregroundStyle(prominent ? Color.pixfunGold : Color.pixfunMuted)
            Text(LocalizedStringKey(title)).font(.pixfun(13, semibold: prominent)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            Image(systemName: accessory).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(prominent ? Color.pixfunGold : Color.pixfunMuted)
                .frame(width: prominent ? 26 : 14, height: 26)
                .background(prominent ? Color.pixfunHover : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .foregroundStyle(Color.pixfunInk)
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: prominent ? 48 : 40)
        .background(hovered && enabled ? Color.pixfunHover : prominent ? .pixfunRaised : .pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : hovered && enabled ? .pixfunGold : .pixfunLine, lineWidth: focused ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .opacity(enabled ? 1 : 0.5).onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
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
                .padding(.horizontal, 12).frame(minHeight: 30)
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
            TextField(LocalizedStringKey(placeholder), text: $text, prompt: Text(LocalizedStringKey(placeholder)).foregroundColor(.pixfunSubtle)).textFieldStyle(.plain).font(.pixfun(13)).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { if let clear { clear() } else { text = "" } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.pixfunMuted)
                        .frame(width: 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 11).frame(height: 30)
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

enum PixfunSidebarMetrics {
    static let contentInset: CGFloat = 10
}

enum PixfunLayout {
    static let pageInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
}

struct PixfunNavigationButton: View {
    let page: WorkspacePage
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 16, weight: .regular)).frame(width: 20)
                Text(LocalizedStringKey(page.navigationTitle)).font(.pixfun(13, semibold: selected)).lineLimit(1)
                Spacer(minLength: 0)
            }.foregroundStyle(selected ? Color.pixfunGold : hovered ? .pixfunInk : .pixfunMuted)
                .padding(.horizontal, PixfunSidebarMetrics.contentInset).frame(height: 34)
                .background(selected ? Color.pixfunBrandSoft : hovered ? .pixfunRaised : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct PixfunLogo: View {
    private let scale: CGFloat = 120.0 / 156.0
    var body: some View {
        // Exact approved web lockup. Its black matte is composited away just as
        // the website does; the symbol and lettering are not redrawn or retyped.
        GeometryReader { _ in
            if let url = Bundle.main.url(forResource: "pixfun-lockup-v2", withExtension: "png", subdirectory: "Brand"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: 218 * scale, height: 218 * 362 / 1086 * scale)
                    .offset(x: -31 * scale, y: -17 * scale)
            }
        }.frame(width: 120, height: 42 * scale).clipped().blendMode(.screen)
            .accessibilityElement(children: .ignore).accessibilityLabel("Pixfun")
    }
}

/// Indeterminate activity, never a simulated percentage. Queued work stays still.
struct PixfunActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var queued = false
    var size: CGFloat = 22
    var tint: Color = .pixfunGold
    var body: some View {
        Group {
            if queued {
                Image(systemName: "clock").font(.system(size: size, weight: .medium))
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                    ZStack {
                        Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
                        Circle().trim(from: 0, to: 0.72)
                            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(reduceMotion ? -90 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
                    }.padding(2)
                }
            }
        }.foregroundStyle(tint).frame(width: size, height: size).accessibilityHidden(true)
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
