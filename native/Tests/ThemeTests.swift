import SwiftUI
import AppKit

@main
struct ThemeTests {
    static func channels(_ color: Color, in appearance: NSAppearance) -> [CGFloat] {
        var result: [CGFloat] = []
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB)!
            result = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
        }
        return result
    }
    static func luminance(_ rgb: [CGFloat]) -> CGFloat {
        zip(rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
    }
    static func ratio(_ foreground: Color, _ background: Color, _ appearance: NSAppearance) -> CGFloat {
        let a = luminance(channels(foreground, in: appearance)), b = luminance(channels(background, in: appearance))
        return (max(a,b) + 0.05) / (min(a,b) + 0.05)
    }
    static func main() {
        _ = NSApplication.shared
        var count = 0
        for name: NSAppearance.Name in [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = NSAppearance(named: name)!
            for foreground: Color in [.pixfunInk, .pixfunMuted, .pixfunSubtle, .pixfunGoldText, .pixfunDanger] {
                for background: Color in [.pixfunBackground, .pixfunSurface, .pixfunInput, .pixfunHover, .pixfunBrandSoft] {
                    precondition(ratio(foreground, background, appearance) >= 4.5, "UI text contrast: \(name.rawValue), \(channels(foreground, in: appearance)) on \(channels(background, in: appearance)), ratio \(ratio(foreground, background, appearance))")
                    count += 1
                }
            }
            precondition(ratio(.pixfunOnAccent, .pixfunGold, appearance) >= 4.5, "Primary button labels keep a dark foreground")
            precondition(ratio(.pixfunControlBorder, .pixfunInput, appearance) >= 3, "Input boundaries remain visible")
            precondition(ratio(.pixfunOnSelected, .pixfunBrandSoft, appearance) >= 4.5, "Selected navigation remains readable")
            precondition(ratio(.pixfunSelectionBorder, .pixfunBrandSoft, appearance) >= 3, "Selection boundaries remain visible")
            for fill: Color in [.pixfunGoldHover, .pixfunGoldPressed] {
                precondition(ratio(.pixfunOnAccent, fill, appearance) >= 4.5, "Primary button interaction states remain readable")
                count += 1
            }
            for background: Color in [.pixfunBackground, .pixfunSurface, .pixfunInput, .pixfunHover] {
                precondition(ratio(.pixfunFocus, background, appearance) >= 3, "Brand focus ring remains visible on every control surface")
                count += 1
            }
            count += 4
        }
        let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
        precondition(channels(.pixfunBackground, in: light).allSatisfy { $0 > 0.99 }, "Light canvas is white")
        precondition(channels(.pixfunBackground, in: dark).allSatisfy { $0 < 0.11 }, "Dark canvas stays charcoal")
        precondition(channels(.pixfunGold, in: light) == channels(.pixfunGold, in: dark), "Brand button fill is stable across themes")
        print("Passed \(count + 3) native dynamic-palette and contrast checks.")
    }
}
