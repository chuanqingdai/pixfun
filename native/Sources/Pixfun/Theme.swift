import SwiftUI
import AppKit
import CoreText

// Pixfun design-system semantic colors. Dynamic providers also serve AppKit views.
extension Color {
    init(pixfunHex: UInt32) {
        self.init(.sRGB, red: Double((pixfunHex >> 16) & 255) / 255,
                  green: Double((pixfunHex >> 8) & 255) / 255,
                  blue: Double(pixfunHex & 255) / 255, opacity: 1)
    }
    static func pixfunAdaptive(light: UInt32, dark: UInt32, contrastLight: UInt32? = nil, contrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua])
            let hex: UInt32
            switch match {
            case .accessibilityHighContrastDarkAqua: hex = contrastDark ?? dark
            case .accessibilityHighContrastAqua: hex = contrastLight ?? light
            case .darkAqua: hex = dark
            default: hex = light
            }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let pixfunBackground = pixfunAdaptive(light: 0xffffff, dark: 0x151819)
    static let pixfunSidebar = pixfunSurface
    static let pixfunSurface = pixfunAdaptive(light: 0xf4f5f6, dark: 0x1d2123)
    static let pixfunRaised = pixfunAdaptive(light: 0xe9ecef, dark: 0x272c2f)
    static let pixfunHover = pixfunAdaptive(light: 0xe3e7ea, dark: 0x303639)
    static let pixfunInput = pixfunAdaptive(light: 0xffffff, dark: 0x272c2f)
    static let pixfunLine = pixfunAdaptive(light: 0xd4d9dd, dark: 0x363e42, contrastLight: 0x76818a, contrastDark: 0x9aa5aa)
    static let pixfunControlBorder = pixfunAdaptive(light: 0x76818a, dark: 0x748088, contrastLight: 0x1d2327, contrastDark: 0xe9ebe8)
    static let pixfunInk = pixfunAdaptive(light: 0x1d2327, dark: 0xe9ebe8)
    static let pixfunMuted = pixfunAdaptive(light: 0x59636b, dark: 0xb1b9bc)
    static let pixfunSubtle = pixfunAdaptive(light: 0x59636b, dark: 0x9aa5aa)
    static let pixfunPlaceholder = pixfunSubtle
    static let pixfunGold = Color(pixfunHex: 0xd7b581)
    static let pixfunGoldHover = Color(pixfunHex: 0xe5c796)
    static let pixfunGoldPressed = Color(pixfunHex: 0xc4a16c)
    static let pixfunGoldText = pixfunAdaptive(light: 0x7a541f, dark: 0xd7b581)
    static let pixfunSelectionBorder = pixfunAdaptive(light: 0x8a642e, dark: 0xd7b581)
    static let pixfunBrandSoft = pixfunAdaptive(light: 0xf5ecdc, dark: 0x343027)
    static let pixfunOnSelected = pixfunAdaptive(light: 0x6f4b1c, dark: 0xe9ebe8)
    static let pixfunOnAccent = Color(pixfunHex: 0x20221f)
    static let pixfunFocus = pixfunSelectionBorder
    static let pixfunDanger = pixfunAdaptive(light: 0xb43d3d, dark: 0xf0a2a2)
    static let pixfunWarning = pixfunMuted
    static let pixfunSuccess = pixfunAdaptive(light: 0x26734d, dark: 0x91cbaa)

    // Editing panes reuse the same surfaces as the rest of the app.
    // The actual video canvas retains its own dark surround.
    static let pixfunStoryChat = pixfunSurface
    static let pixfunStoryPreview = pixfunBackground
    static let pixfunStoryRail = pixfunRaised
    static let pixfunStoryCard = pixfunHover
    static let pixfunStoryInput = pixfunInput
    static let pixfunStoryInputLine = pixfunControlBorder
}

enum PixfunTypography {
    static func placeholder(_ title: LocalizedStringKey) -> Text { Text(title).foregroundColor(.pixfunPlaceholder) }
    static func register() {
        for name in ["dm-sans-regular", "dm-sans-semibold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Categories are identified by their labels and symbols, not decorative hues.
/// Gold is reserved for selected filters and actions across every category.
enum MediaTagPalette {
    static func facet(_ facet: MediaFacet) -> Color { .pixfunMuted }
    static let technique = Color.pixfunMuted
    static let story = Color.pixfunMuted
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
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 20)
                .foregroundStyle(prominent ? Color.pixfunGoldText : Color.pixfunMuted)
            Text(LocalizedStringKey(title)).font(.pixfun(14, semibold: prominent)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            Image(systemName: accessory).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(prominent ? Color.pixfunGoldText : Color.pixfunMuted)
                .frame(width: prominent ? 26 : 14, height: 26)
                .background(prominent ? Color.pixfunHover : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .foregroundStyle(Color.pixfunInk)
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: prominent ? 48 : 40)
        .background(hovered && enabled ? Color.pixfunHover : prominent ? .pixfunRaised : .pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : hovered && enabled ? .pixfunSelectionBorder : .pixfunControlBorder, lineWidth: focused ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .opacity(enabled ? 1 : 0.5).onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
    }
}

enum PixfunButtonKind { case secondary, primary, quiet, textAction }

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
            if !enabled { return (kind == .quiet || kind == .textAction) ? .clear : .pixfunRaised }
            if kind == .primary { return configuration.isPressed ? .pixfunGoldPressed : hovered ? .pixfunGoldHover : .pixfunGold }
            return hovered || configuration.isPressed ? .pixfunHover : (kind == .quiet || kind == .textAction) ? .clear : .pixfunSurface
        }
        var body: some View {
            configuration.label
                .font(.pixfun(14, semibold: true))
                .foregroundStyle(!enabled ? Color.pixfunSubtle : kind == .primary ? .pixfunOnAccent : kind == .textAction ? .pixfunGoldText : .pixfunInk)
                .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 40)
                .background(fill, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.pixfunFocus : kind == .secondary ? .pixfunControlBorder : .clear, lineWidth: focused ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 6))
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
            TextField(LocalizedStringKey(placeholder), text: $text, prompt: PixfunTypography.placeholder(LocalizedStringKey(placeholder))).textFieldStyle(.plain).font(.pixfun(14)).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { if let clear { clear() } else { text = "" } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.pixfunMuted)
                        .frame(width: 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 12).frame(minHeight: 40)
            .background(Color.pixfunInput, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.pixfunFocus : .pixfunControlBorder, lineWidth: focused ? 2 : 1))
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : hovered ? .pixfunSubtle : .pixfunLine, lineWidth: focused ? 2 : 1))
                .onHover { hovered = $0 }
        }
    }
}

enum PixfunSidebarMetrics {
    static let contentInset: CGFloat = 12
}

enum PixfunLayout {
    static let toolbarControlHeight: CGFloat = 40
    static let pageInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 24
}

struct PixfunNavigationButton: View {
    let page: WorkspacePage
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.symbol).font(.system(size: 16, weight: .regular)).frame(width: 20)
                Text(LocalizedStringKey(page.navigationTitle)).font(.pixfun(14, semibold: selected)).lineLimit(1)
                Spacer(minLength: 0)
            }.foregroundStyle(selected ? Color.pixfunOnSelected : hovered ? .pixfunInk : .pixfunMuted)
                .padding(.horizontal, PixfunSidebarMetrics.contentInset).frame(minHeight: 40)
                .background(selected ? Color.pixfunBrandSoft : hovered ? .pixfunRaised : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct PixfunLogo: View {
    // The same transparent, full-color artwork is used in both appearances.
    // Crop only transparent export margins; never tint or blend the logo.
    private let scale: CGFloat = 120.0 / 1811.0
    var body: some View {
        GeometryReader { _ in
            if let url = Bundle.main.url(forResource: "pixfun-lockup-transparent-v3", withExtension: "png", subdirectory: "Brand"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: 2172 * scale, height: 724 * scale)
                    .offset(x: -196 * scale, y: -153 * scale + 4)
            }
        }.frame(width: 120, height: 32).clipped()
            .padding(.horizontal, 8).padding(.vertical, 6)
            .accessibilityElement(children: .ignore).accessibilityLabel("Pixfun")
    }
}

/// Indeterminate activity, never a simulated percentage. Queued work stays still.
struct PixfunActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var queued = false
    var size: CGFloat = 22
    var tint: Color = .pixfunGoldText
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

// Keep native window chrome and AppKit surfaces in sync with the selected appearance.
struct PixfunWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AppearanceView() }
    func updateNSView(_ view: NSView, context: Context) { view.window?.backgroundColor = NSColor(Color.pixfunBackground) }
    private final class AppearanceView: NSView {
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            window?.backgroundColor = NSColor(Color.pixfunBackground)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.backgroundColor = NSColor(Color.pixfunBackground)
        }
    }
}
