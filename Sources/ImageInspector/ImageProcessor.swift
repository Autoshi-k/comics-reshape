import Vision
import CoreGraphics
import AppKit

/// Detects square shapes in the image, crops each one, and returns a new image
/// with the squares stacked in a vertical column (top-to-bottom order) with padding between them.
/// Returns the original image if no squares are found.
public func processImage(_ input: NSImage) -> NSImage {
    guard let cgInput = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return input
    }

    let imgWidth = cgInput.width
    let imgHeight = cgInput.height

    let squares = detectSquares(in: cgInput)
    guard !squares.isEmpty else { return input }

    // Sort top-to-bottom by vertical center in the original image.
    // Vision Y=0 is bottom-left, so higher midY = higher on screen → comes first.
    let sorted = squares.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

    // Crop each square from the original image.
    // Vision bounding box: normalized, origin bottom-left.
    // CGImage.cropping: pixel coords, origin top-left → flip Y.
    let crops: [CGImage] = sorted.compactMap { obs in
        let box = obs.boundingBox
        let rect = CGRect(
            x:      box.minX              * CGFloat(imgWidth),
            y:      (1 - box.maxY)        * CGFloat(imgHeight),
            width:  box.width             * CGFloat(imgWidth),
            height: box.height            * CGFloat(imgHeight)
        )
        return cgInput.cropping(to: rect)
    }

    guard !crops.isEmpty else { return input }

    let padding = 24
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

    // White background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

    // Draw squares top-to-bottom.
    // CGContext origin is bottom-left, so track offset from the bottom.
    var bottomY = outputHeight
    for crop in crops {
        bottomY -= crop.height
        let x = (outputWidth - crop.width) / 2  // center horizontally
        context.draw(crop, in: CGRect(x: x, y: bottomY, width: crop.width, height: crop.height))
        bottomY -= padding
    }

    guard let result = context.makeImage() else { return input }
    let outputSize = NSSize(width: outputWidth, height: outputHeight)
    return NSImage(cgImage: result, size: outputSize)
}

// MARK: - Private helpers

private func detectSquares(in cgImage: CGImage) -> [VNRectangleObservation] {
    let request = VNDetectRectanglesRequest()
    request.minimumAspectRatio = 0.75
    request.maximumAspectRatio = 1.0
    request.minimumSize = 0.03
    request.maximumObservations = 64
    request.minimumConfidence = 0.4
    request.quadratureTolerance = 20

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])

    return request.results ?? []
}
