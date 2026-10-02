// Offline, measured typography for the bundled FFmpeg overlay renderer.
// No drawtext/FreeType or developer-installed Python packages are required.
import AppKit
import CoreText

struct Request: Decodable {
    let text: String
    let index: String
    let width: Int
    let height: Int
    let dark: Bool
}
do {
    guard CommandLine.arguments.count == 4 else { throw NSError(domain: "title arguments", code: 1) }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let request = try JSONDecoder().decode(Request.self, from: data)
    guard (100...4096).contains(request.width), (50...2048).contains(request.height),
          request.text.count <= 90 else { throw NSError(domain: "title bounds", code: 2) }
    let fontURL = URL(fileURLWithPath: CommandLine.arguments[3])
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
          let descriptor = descriptors.first else { throw NSError(domain: "missing bundled font", code: 3) }
    let w = CGFloat(request.width), h = CGFloat(request.height)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: request.width, pixelsHigh: request.height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let ink = request.dark ? NSColor(calibratedWhite: 0.94, alpha: 1) : NSColor(calibratedRed: 0.09, green: 0.18, blue: 0.15, alpha: 1)
    let accent = request.dark ? NSColor(calibratedRed: 0.84, green: 0.71, blue: 0.50, alpha: 1) : ink
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    var size = min(h * 0.40, w * 0.082)
    var title: NSAttributedString!
    var rect: NSRect = .zero
    repeat {
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        title = NSAttributedString(string: request.text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
        rect = title.boundingRect(with: NSSize(width: w - 4, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        if rect.height <= h * 0.68 { break }
        size -= 1
    } while size >= 18
    guard rect.height <= h * 0.68 else { throw NSError(domain: "title does not fit", code: 4) }
    title.draw(with: NSRect(x: 0, y: h * 0.68 - rect.height, width: w - 4, height: rect.height + 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let small = CTFontCreateWithFontDescriptor(descriptor, max(14, size * 0.29), nil)
    NSAttributedString(string: request.index, attributes: [.font: small, .foregroundColor: accent, .kern: 2])
        .draw(at: NSPoint(x: 0, y: h * 0.83))
    accent.setFill()
    NSRect(x: 0, y: h * 0.77, width: min(48, w * 0.08), height: 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "PNG export", code: 5) }
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Title rendering failed: \(error)\n".utf8))
    exit(1)
}
