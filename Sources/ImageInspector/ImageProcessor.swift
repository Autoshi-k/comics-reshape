import Vision
import CoreGraphics
import AppKit

/// Detects comic panel squares, removes nested detections, sorts into reading order,
/// then stacks the cropped panels in a vertical column.
public func processImage(_ input: NSImage) -> NSImage {
    guard let cgInput = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return input
    }

    let imgWidth  = cgInput.width
    let imgHeight = cgInput.height

    let raw     = detectSquares(in: cgInput)
    let panels  = sortInReadingOrder(filterNested(raw))

    guard !panels.isEmpty else { return input }

    // Crop each panel using Vision's bounding box.
    // Vision: normalized coords, origin bottom-left.
    // CGImage.cropping: pixel coords, origin top-left → flip Y.
    let crops: [CGImage] = panels.compactMap { obs in
        let box = obs.boundingBox
        let rect = CGRect(
            x:      box.minX         * CGFloat(imgWidth),
            y:      (1 - box.maxY)   * CGFloat(imgHeight),
            width:  box.width        * CGFloat(imgWidth),
            height: box.height       * CGFloat(imgHeight)
        )
        return cgInput.cropping(to: rect)
    }

    guard !crops.isEmpty else { return input }

    let padding      = 24
    let outputWidth  = crops.map(\.width).max()!
    let outputHeight = crops.map(\.height).reduce(0, +) + padding * (crops.count - 1)

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

    // CGContext origin is bottom-left; draw panels top-to-bottom visually.
    var bottomY = outputHeight
    for crop in crops {
        bottomY -= crop.height
        let x = (outputWidth - crop.width) / 2
        context.draw(crop, in: CGRect(x: x, y: bottomY, width: crop.width, height: crop.height))
        bottomY -= padding
    }

    guard let result = context.makeImage() else { return input }
    return NSImage(cgImage: result, size: NSSize(width: outputWidth, height: outputHeight))
}

// MARK: - Detection

private func detectSquares(in cgImage: CGImage) -> [VNRectangleObservation] {
    let request = VNDetectRectanglesRequest()
    request.minimumAspectRatio  = 0.75
    request.maximumAspectRatio  = 1.0
    // Panels are large — require at least 10% of the shorter image dimension.
    // This helps skip small shapes inside panels.
    request.minimumSize         = 0.10
    request.maximumObservations = 64
    request.minimumConfidence   = 0.5
    request.quadratureTolerance = 20

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])

    return request.results ?? []
}

// MARK: - Nested rectangle filtering

/// Keeps only the outermost rectangles.
/// If more than 50% of a candidate's area is covered by a larger rectangle, it is discarded.
private func filterNested(_ observations: [VNRectangleObservation]) -> [VNRectangleObservation] {
    // Process largest-first so outer panels are accepted before inner shapes.
    let byArea = observations.sorted {
        ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height)
    }

    var accepted: [VNRectangleObservation] = []

    for candidate in byArea {
        let cBox  = candidate.boundingBox
        let cArea = cBox.width * cBox.height
        guard cArea > 0 else { continue }

        let isNested = accepted.contains { parent in
            let intersection = cBox.intersection(parent.boundingBox)
            guard !intersection.isNull, !intersection.isEmpty else { return false }
            let overlapRatio = (intersection.width * intersection.height) / cArea
            return overlapRatio > 0.5
        }

        if !isNested {
            accepted.append(candidate)
        }
    }

    return accepted
}

// MARK: - Reading-order sort

/// Groups panels into rows by vertical proximity, then sorts each row left-to-right.
/// Vision Y=0 is bottom of image, so higher midY = higher on the page = read first.
private func sortInReadingOrder(_ observations: [VNRectangleObservation]) -> [VNRectangleObservation] {
    guard observations.count > 1 else { return observations }

    let avgHeight    = observations.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(observations.count)
    let rowTolerance = avgHeight * 0.5

    // Sort top-to-bottom to seed the row builder in the right sequence.
    let byY = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

    var rows: [[VNRectangleObservation]] = []

    for obs in byY {
        // Find an existing row whose average center Y is within tolerance.
        if let idx = rows.indices.first(where: { i in
            let rowMidY = rows[i].map { $0.boundingBox.midY }.reduce(0, +) / CGFloat(rows[i].count)
            return abs(obs.boundingBox.midY - rowMidY) < rowTolerance
        }) {
            rows[idx].append(obs)
        } else {
            rows.append([obs])
        }
    }

    // Sort rows top-to-bottom by their average center Y.
    let sortedRows = rows.sorted { rowA, rowB in
        let a = rowA.map { $0.boundingBox.midY }.reduce(0, +) / CGFloat(rowA.count)
        let b = rowB.map { $0.boundingBox.midY }.reduce(0, +) / CGFloat(rowB.count)
        return a > b
    }

    // Within each row, sort left-to-right.
    return sortedRows.flatMap { $0.sorted { $0.boundingBox.midX < $1.boundingBox.midX } }
}
