import AppKit
import CoreText

@main
struct FontTests {
    static func main() {
        for (file, name) in [("dm-sans-regular", "DMSans-Regular"), ("dm-sans-semibold", "DMSans-SemiBold")] {
            let url = URL(fileURLWithPath: "public/fonts/\(file).ttf")
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil),
                  let font = NSFont(name: name, size: 14), font.fontName == name else {
                fatalError("Web font must load natively without system-font fallback: \(name)")
            }
        }
        print("Passed 2 native web-font registration checks.")
    }
}
