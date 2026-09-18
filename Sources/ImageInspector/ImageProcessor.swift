import CoreGraphics
import AppKit

/// Detects comic panels via white gutter bands, sorts into reading order,
/// then stacks the cropped panels in a vertical column with optional header/footer.
public func processImage(_ input: NSImage, header: NSImage? = nil, footer: NSImage? = nil) -> NSImage {
    guard let cgInput = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return input
    }

    let panelCrops: [CGImage] = detectPanels(in: cgInput).compactMap { cgInput.cropping(to: $0) }
    guard !panelCrops.isEmpty else { return input }

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
    ) else { return input }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

    var bottomY = outputHeight
    for crop in allCrops {
        bottomY -= crop.height
        let x = (outputWidth - crop.width) / 2
        context.draw(crop, in: CGRect(x: x, y: bottomY, width: crop.width, height: crop.height))
        bottomY -= padding
    }

    guard let result = context.makeImage() else { return input }
    return NSImage(cgImage: result, size: NSSize(width: outputWidth, height: outputHeight))
}

// MARK: - Gutter-based panel detection

/// Finds panels by locating horizontal and vertical white gutter bands.
/// Returns rects in reading order (top-to-bottom, left-to-right).
/// Rects are in CGImage coordinate space (y=0 at top-left).
private func detectPanels(in image: CGImage) -> [CGRect] {
    let width  = image.width
    let height = image.height

    // Render into a pixel buffer without any transform.
    // In a macOS CGContext, the default coordinate system has y=0 at the bottom,
    // so a CGImage (whose y=0 is at the top) is rendered upside-down in memory —
    // meaning buffer row 0 = BOTTOM of image, buffer row (height-1) = TOP of image.
    // We handle this by reversing hRanges and converting y-coordinates explicitly.
    guard let ctx = CGContext(
        data: nil,
        width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return [] }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else { return [] }

    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    let bytesPerRow = ctx.bytesPerRow   // use actual stride, not assumed width * 4

    let pixelThreshold   = 0.85   // pixel is "white" if average brightness exceeds this
    let whiteRowFraction = 0.88   // row/col is a gutter candidate if this fraction is white
    let darkPixelCutoff  = 0.15   // pixel is "very dark" (black border) if below this
    let darkRowFraction  = 0.40   // row/col has a border if 40%+ pixels are very dark
    let minGutterPixels  = 8      // ignore white bands thinner than this
    let borderWindow     = 25     // pixels to look before/after a white band for dark borders
    let minPanelPixels   = min(width, height) / 8

    // --- Per-row whiteness + darkness ---
    var rowWhiteness = [Double](repeating: 0, count: height)
    var rowDarkness  = [Double](repeating: 0, count: height)
    for y in 0..<height {
        var white = 0, dark = 0
        for x in 0..<width {
            let i = y * bytesPerRow + x * 4
            let b = (Double(pixels[i]) + Double(pixels[i+1]) + Double(pixels[i+2])) / (3 * 255)
            if b > pixelThreshold  { white += 1 }
            if b < darkPixelCutoff { dark  += 1 }
        }
        rowWhiteness[y] = Double(white) / Double(width)
        rowDarkness[y]  = Double(dark)  / Double(width)
    }

    // --- Per-column whiteness + darkness ---
    var colWhiteness = [Double](repeating: 0, count: width)
    var colDarkness  = [Double](repeating: 0, count: width)
    for x in 0..<width {
        var white = 0, dark = 0
        for y in 0..<height {
            let i = y * bytesPerRow + x * 4
            let b = (Double(pixels[i]) + Double(pixels[i+1]) + Double(pixels[i+2])) / (3 * 255)
            if b > pixelThreshold  { white += 1 }
            if b < darkPixelCutoff { dark  += 1 }
        }
        colWhiteness[x] = Double(white) / Double(height)
        colDarkness[x]  = Double(dark)  / Double(height)
    }

    // Candidate white bands → keep only those flanked by dark (border) rows or image edge.
    // This rejects bright content areas (e.g. moon landscape) which have no black border next to them.
    let candidateHBands = gutterBands(in: rowWhiteness, threshold: whiteRowFraction, minThickness: minGutterPixels)
    let hGutterBands = candidateHBands.filter { (start, end) in
        let prevRange = max(0, start - borderWindow)..<start
        let nextRange = end..<min(height, end + borderWindow)
        let prevDark = start == 0 || prevRange.contains { rowDarkness[$0] >= darkRowFraction }
        let nextDark = end == height || nextRange.contains { rowDarkness[$0] >= darkRowFraction }
        return prevDark && nextDark
    }

    let candidateVBands = gutterBands(in: colWhiteness, threshold: whiteRowFraction, minThickness: minGutterPixels)
    let vGutterBands = candidateVBands.filter { (start, end) in
        let prevRange = max(0, start - borderWindow)..<start
        let nextRange = end..<min(width, end + borderWindow)
        let prevDark = start == 0 || prevRange.contains { colDarkness[$0] >= darkRowFraction }
        let nextDark = end == width || nextRange.contains { colDarkness[$0] >= darkRowFraction }
        return prevDark && nextDark
    }

    // Panel regions sit between gutter bands.
    let hRanges = regions(between: hGutterBands, total: height).filter { $0.1 - $0.0 >= minPanelPixels }
    let vRanges = regions(between: vGutterBands, total: width).filter  { $0.1 - $0.0 >= minPanelPixels }

    // hRanges are in buffer order (bottom→top of image). Reversing gives top→bottom (reading order).
    // Convert buffer y-coords to CGImage coords (y=0 at top): cgY = height - bufferEnd.
    var panels: [CGRect] = []
    for (rowStart, rowEnd) in hRanges.reversed() {
        let cgY = height - rowEnd
        let rowH = rowEnd - rowStart
        for (colStart, colEnd) in vRanges {
            panels.append(CGRect(x: colStart, y: cgY, width: colEnd - colStart, height: rowH))
        }
    }
    return panels
}

/// Finds contiguous runs of values >= threshold that are at least minThickness wide.
private func gutterBands(in values: [Double], threshold: Double, minThickness: Int) -> [(Int, Int)] {
    var bands: [(Int, Int)] = []
    var start: Int? = nil
    for i in 0..<values.count {
        if values[i] >= threshold {
            if start == nil { start = i }
        } else if let s = start {
            if i - s >= minThickness { bands.append((s, i)) }
            start = nil
        }
    }
    if let s = start, values.count - s >= minThickness {
        bands.append((s, values.count))
    }
    return bands
}

/// Returns the gaps between gutter bands — these are the panel regions.
private func regions(between gutters: [(Int, Int)], total: Int) -> [(Int, Int)] {
    var ranges: [(Int, Int)] = []
    var cursor = 0
    for (start, end) in gutters {
        if start > cursor { ranges.append((cursor, start)) }
        cursor = end
    }
    if cursor < total { ranges.append((cursor, total)) }
    return ranges
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
