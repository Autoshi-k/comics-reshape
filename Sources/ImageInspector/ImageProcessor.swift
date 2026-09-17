import Vision
import CoreGraphics
import AppKit

/// Detects square shapes in the image and fills each detected square with solid black.
/// Returns the modified image, or the original if no squares are found.
public func processImage(_ input: NSImage) -> NSImage {
    guard let cgInput = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return input
    }

    let width = cgInput.width
    let height = cgInput.height

    let squares = detectSquares(in: cgInput)

    guard !squares.isEmpty else { return input }

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return input }

    // Draw original image as base
    context.draw(cgInput, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Fill each detected square with black using its actual corner points
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

    for obs in squares {
        // Vision coordinates: normalized, origin at bottom-left — same as CGContext
        let tl = denormalize(obs.topLeft,     width: width, height: height)
        let tr = denormalize(obs.topRight,    width: width, height: height)
        let br = denormalize(obs.bottomRight, width: width, height: height)
        let bl = denormalize(obs.bottomLeft,  width: width, height: height)

        let path = CGMutablePath()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.closeSubpath()

        context.addPath(path)
        context.fillPath()
    }

    guard let result = context.makeImage() else { return input }
    return NSImage(cgImage: result, size: input.size)
}

// MARK: - Private helpers

private func detectSquares(in cgImage: CGImage) -> [VNRectangleObservation] {
    let request = VNDetectRectanglesRequest()
    // Accept shapes whose shorter side is at least 75% of longer side (near-square)
    request.minimumAspectRatio = 0.75
    request.maximumAspectRatio = 1.0
    // Ignore tiny shapes (less than 3% of image width/height)
    request.minimumSize = 0.03
    request.maximumObservations = 64
    request.minimumConfidence = 0.4
    request.quadratureTolerance = 20  // degrees of allowed corner deviation from 90°

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])

    return request.results ?? []
}

private func denormalize(_ point: CGPoint, width: Int, height: Int) -> CGPoint {
    CGPoint(x: point.x * CGFloat(width), y: point.y * CGFloat(height))
}
