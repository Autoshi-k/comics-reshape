// Fits artwork into the standard macOS icon shape: an 824×824 rounded square centred on a
// transparent 1024×1024 canvas. Artwork whose top-left corner is already transparent is
// assumed to be shaped and is only resized.
// Usage: swift scripts/make-icon.swift <input.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3,
      let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: make-icon.swift <input.png> <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let canvas = 1024
let ctx = CGContext(
    data: nil, width: canvas, height: canvas,
    bitsPerComponent: 8, bytesPerRow: canvas * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.interpolationQuality = .high

func alphaAtTopLeft(_ image: CGImage) -> UInt8 {
    let probe = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Draw so that the image's top-left pixel lands on the 1×1 canvas.
    probe.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
    return probe.data!.load(fromByteOffset: 3, as: UInt8.self)
}

if alphaAtTopLeft(cg) < 16 {
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
} else {
    let size: CGFloat = 824
    let inset = (CGFloat(canvas) - size) / 2
    let rect = CGRect(x: inset, y: inset, width: size, height: size)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: size * 0.225, cornerHeight: size * 0.225, transform: nil))
    ctx.clip()
    ctx.draw(cg, in: rect)
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
