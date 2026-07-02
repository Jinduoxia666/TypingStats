// Generates the TypingStats app icon (1024×1024 PNG) headlessly via Core Graphics.
// Concept: deep-blue rounded-rect plate + three ascending white bars + a typing caret.
// Usage: swiftc tools/GenerateIcon.swift -o /tmp/genicon && /tmp/genicon out.png
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size = 1024
let S = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: genicon <out.png>\n".utf8)); exit(1)
}

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}
func roundRect(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// macOS-style plate: rounded rect with transparent margins + soft drop shadow.
let margin: CGFloat = 92
let plate = CGRect(x: margin, y: margin, width: S - margin * 2, height: S - margin * 2)
let radius = plate.width * 0.2237

// Drop shadow (cast by a solid fill, then we paint the gradient on top).
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 48, color: rgb(0, 0, 0, 0.35))
ctx.addPath(roundRect(plate, radius))
ctx.setFillColor(rgb(28, 46, 138))
ctx.fillPath()
ctx.restoreGState()

// Deep-blue diagonal gradient.
ctx.saveGState()
ctx.addPath(roundRect(plate, radius))
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(84, 140, 255), rgb(26, 46, 138)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: plate.minX, y: plate.maxY), end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
// Subtle top highlight for depth.
let hi = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 0.16), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(hi, start: CGPoint(x: plate.minX, y: plate.maxY), end: CGPoint(x: plate.minX, y: plate.midY), options: [])
ctx.restoreGState()

// Ascending bars + caret, horizontally centered.
func bar(_ x: CGFloat, height: CGFloat, width: CGFloat, baseline: CGFloat, corner: CGFloat, _ color: CGColor) {
    ctx.addPath(roundRect(CGRect(x: x, y: baseline, width: width, height: height), corner))
    ctx.setFillColor(color)
    ctx.fillPath()
}

let baseline: CGFloat = 312
let bw: CGFloat = 118
let gap: CGFloat = 46
let corner: CGFloat = 40
let caretW: CGFloat = 46
let white = rgb(255, 255, 255)
let dim = rgb(255, 255, 255, 0.9)

let groupW = bw * 3 + gap * 2 + gap + caretW
let startX = (S - groupW) / 2

bar(startX,                 height: 232, width: bw, baseline: baseline, corner: corner, dim)
bar(startX + (bw + gap),    height: 330, width: bw, baseline: baseline, corner: corner, dim)
bar(startX + 2 * (bw + gap),height: 430, width: bw, baseline: baseline, corner: corner, white)

let caretX = startX + 3 * bw + 2 * gap + gap
bar(caretX, height: 462, width: caretW, baseline: baseline, corner: caretW / 2, white)

// Write PNG.
guard let img = ctx.makeImage() else { fatalError("image") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("dest") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
