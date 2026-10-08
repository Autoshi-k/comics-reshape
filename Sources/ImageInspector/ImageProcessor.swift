import CoreGraphics
import AppKit

public struct ProcessedComic {
    /// All panels stacked vertically, with optional header/footer.
    public let comics: NSImage
    /// Each detected panel on its own, in reading order (empty if no panels were detected).
    public let panels: [NSImage]
}

/// Detects comic panels via white gutter bands, sorts into reading order,
/// then stacks the cropped panels in a vertical column with optional header/footer.
public func processImage(_ input: NSImage, header: NSImage? = nil, footer: NSImage? = nil) -> ProcessedComic {
    guard let cgInput = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return ProcessedComic(comics: input, panels: [])
    }

    let panelCrops: [CGImage] = detectPanels(in: cgInput).compactMap { cgInput.cropping(to: $0) }
    guard !panelCrops.isEmpty else { return ProcessedComic(comics: input, panels: []) }
    let panels = panelCrops.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }

    let padding     = 24
    let columnWidth = panelCrops.map(\.width).max()!

    let headerCrop = header.flatMap { scaledToWidth($0, width: columnWidth) }
    let footerCrop = footer.flatMap { scaledToWidth($0, width: columnWidth) }

    var allCrops: [CGImage] = []
    if let h = headerCrop { allCrops.append(h) }
    allCrops.append(contentsOf: panelCrops)
    if let f = footerCrop { allCrops.append(f) }

    let outputWidth  = allCrops.map(\.width).max()!
    let outputHeight = allCrops.map(\.height).reduce(0, +) + padding * (allCrops.count - 1)

    guard let context = CGContext(
        data: nil,
        width: outputWidth,
        height: outputHeight,
        bitsPerComponent: 8,
        bytesPerRow: outputWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return ProcessedComic(comics: input, panels: panels) }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

    var bottomY = outputHeight
    for crop in allCrops {
        bottomY -= crop.height
        let x = (outputWidth - crop.width) / 2
        context.draw(crop, in: CGRect(x: x, y: bottomY, width: crop.width, height: crop.height))
        bottomY -= padding
    }

    guard let result = context.makeImage() else { return ProcessedComic(comics: input, panels: panels) }
    return ProcessedComic(
        comics: NSImage(cgImage: result, size: NSSize(width: outputWidth, height: outputHeight)),
        panels: panels
    )
}

// MARK: - Border-based panel detection

/// Finds panels as black-bordered boxes on a white page.
/// The white page background is flood-filled inward from the image edges; panel interiors
/// are walled off by their borders, so whatever they contain is never reached. Everything
/// left over is grouped into connected blobs, and each large-enough blob's bounding box is a panel.
/// Returns rects in reading order, in CGImage coordinates (y=0 at top).
private func detectPanels(in image: CGImage) -> [CGRect] {
    // Analyse a downscaled copy of very large pages for speed; rects are scaled back up at the end.
    let maxSide = 2000
    let scale   = min(1.0, Double(maxSide) / Double(max(image.width, image.height)))
    let width   = max(1, Int((Double(image.width)  * scale).rounded()))
    let height  = max(1, Int((Double(image.height) * scale).rounded()))

    guard let ctx = CGContext(
        data: nil,
        width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return [] }
    // Transparent areas count as white page, not black.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else { return [] }

    // Buffer row 0 is the TOP of the image, so buffer coordinates match CGImage coordinates.
    let pixels      = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * height)
    let bytesPerRow = ctx.bytesPerRow
    let count       = width * height

    // Per-pixel state. Raw buffers keep the fills fast even in unoptimized debug builds.
    let ink: UInt8 = 0, white: UInt8 = 1, claimed: UInt8 = 2   // claimed = page background or already in a blob
    let state = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    let stack = UnsafeMutablePointer<Int>.allocate(capacity: count)   // a pixel is pushed at most once
    defer { state.deallocate(); stack.deallocate() }
    var top = 0

    let whiteThreshold = Int(0.80 * 3 * 255)   // pixel is page-white if R+G+B is above this
    for y in 0..<height {
        for x in 0..<width {
            let i = y * bytesPerRow + x * 4
            state[y * width + x] = Int(pixels[i]) + Int(pixels[i+1]) + Int(pixels[i+2]) > whiteThreshold ? white : ink
        }
    }

    // 1. Flood-fill the white page background, starting from every white pixel on the image edge.
    var edge: [Int] = []
    for x in 0..<width  { edge.append(x); edge.append((height - 1) * width + x) }
    for y in 0..<height { edge.append(y * width); edge.append(y * width + width - 1) }
    for i in edge where state[i] == white { state[i] = claimed; stack[top] = i; top += 1 }
    while top > 0 {
        top -= 1
        let i = stack[top], x = i % width, y = i / width
        if x > 0,          state[i - 1] == white     { state[i - 1] = claimed;     stack[top] = i - 1;     top += 1 }
        if x < width - 1,  state[i + 1] == white     { state[i + 1] = claimed;     stack[top] = i + 1;     top += 1 }
        if y > 0,          state[i - width] == white { state[i - width] = claimed; stack[top] = i - width; top += 1 }
        if y < height - 1, state[i + width] == white { state[i + width] = claimed; stack[top] = i + width; top += 1 }
    }

    // 2. Group the remaining pixels (borders + panel contents) into 8-connected blobs.
    var boxes: [CGRect] = []
    for start in 0..<count where state[start] != claimed {
        var minX = width, minY = height, maxX = 0, maxY = 0
        state[start] = claimed; stack[top] = start; top += 1
        while top > 0 {
            top -= 1
            let i = stack[top], x = i % width, y = i / width
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
            // Unrolled 8-neighbour visit (range loops are very slow in debug builds).
            let l = x > 0, r = x < width - 1, u = y > 0, d = y < height - 1
            if l      { let n = i - 1;         if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if r      { let n = i + 1;         if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if u      { let n = i - width;     if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if d      { let n = i + width;     if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if u && l { let n = i - width - 1; if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if u && r { let n = i - width + 1; if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if d && l { let n = i + width - 1; if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
            if d && r { let n = i + width + 1; if state[n] != claimed { state[n] = claimed; stack[top] = n; top += 1 } }
        }
        boxes.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    // 3. Drop small blobs (page numbers, stray marks) and boxes nested inside another box.
    let minPanelPixels = CGFloat(min(width, height)) / 12
    let large = boxes.filter { $0.width >= minPanelPixels && $0.height >= minPanelPixels }
    let panels = large.filter { box in !large.contains { $0 != box && $0.contains(box) } }

    // Scale back to full-resolution coordinates, padding by one source pixel to keep the border intact.
    let pad    = ceil(1 / scale)
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let fullRes = panels.map { box in
        CGRect(x: box.minX / scale, y: box.minY / scale, width: box.width / scale, height: box.height / scale)
            .insetBy(dx: -pad, dy: -pad)
            .integral
            .intersection(bounds)
    }
    return sortedInReadingOrder(fullRes)
}

/// Orders panels row by row (top to bottom), left to right within a row.
/// A panel joins the current row if it starts above the bottom of every panel already in it,
/// so a tall panel spanning two rows is read before the stacked panels beside it.
private func sortedInReadingOrder(_ rects: [CGRect]) -> [CGRect] {
    var rows: [[CGRect]] = []
    for rect in rects.sorted(by: { $0.minY < $1.minY }) {
        if let row = rows.last, rect.minY < row.map(\.maxY).min()! {
            rows[rows.count - 1].append(rect)
        } else {
            rows.append([rect])
        }
    }
    return rows.flatMap { $0.sorted { $0.minX < $1.minX } }
}

// MARK: - Scaling

/// Scales an NSImage to exactly `width` pixels wide, maintaining aspect ratio.
private func scaledToWidth(_ image: NSImage, width: Int) -> CGImage? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    guard cg.width != width else { return cg }
    let scale     = CGFloat(width) / CGFloat(cg.width)
    let newHeight = max(1, Int(CGFloat(cg.height) * scale))
    guard let ctx = CGContext(
        data: nil, width: width, height: newHeight,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: newHeight))
    return ctx.makeImage()
}
