import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Expected output PNG path") }
let path = CommandLine.arguments[1]
let dim = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: dim, pixelsHigh: dim,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Cannot create icon bitmap") }
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot draw icon") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: dim, height: dim).fill()
let rect = NSRect(x: 90, y: 90, width: 844, height: 844)
NSColor(calibratedRed: 0.04, green: 0.14, blue: 0.20, alpha: 0.93).setFill()
NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210).fill()
let text = "DL" as NSString
let style = NSMutableParagraphStyle()
style.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 390, weight: .heavy),
    .foregroundColor: NSColor(calibratedRed: 0.26, green: 0.97, blue: 0.82, alpha: 1),
    .paragraphStyle: style
]
text.draw(in: NSRect(x: 130, y: 266, width: 764, height: 510), withAttributes: attrs)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
try png.write(to: URL(fileURLWithPath: path))
print("DLSIGN icon PNG created")
