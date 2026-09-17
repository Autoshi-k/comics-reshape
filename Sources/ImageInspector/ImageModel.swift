import Foundation
import AppKit
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct ImageModel {
    let filename: String
    let fileSize: Int64
    let width: Int
    let height: Int
    let format: String
    let colorSpace: String
    let bitsPerComponent: Int
    let bitsPerPixel: Int
    let dpiX: Double
    let dpiY: Double
    let hasAlpha: Bool
    let nsImage: NSImage
    let originalData: Data

    var fileSizeFormatted: String {
        let bytes = Double(fileSize)
        if bytes < 1024 { return "\(fileSize) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", bytes / 1024) }
        return String(format: "%.2f MB", bytes / (1024 * 1024))
    }

    var dimensionsFormatted: String { "\(width) × \(height) px" }

    var dpiFormatted: String {
        if dpiX == dpiY { return String(format: "%.0f DPI", dpiX) }
        return String(format: "%.0f × %.0f DPI", dpiX, dpiY)
    }
}

func loadImageModel(from url: URL) -> ImageModel? {
    guard
        let data = try? Data(contentsOf: url),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let nsImage = NSImage(data: data)
    else { return nil }

    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? Int64(data.count)

    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let dpiX = (props[kCGImagePropertyDPIWidth] as? Double) ?? 72
    let dpiY = (props[kCGImagePropertyDPIHeight] as? Double) ?? 72

    let colorSpaceName: String = {
        guard let cs = cgImage.colorSpace else { return "Unknown" }
        if let name = cs.name { return (name as String).components(separatedBy: "/").last ?? (name as String) }
        switch cs.model {
        case .rgb: return "RGB"
        case .cmyk: return "CMYK"
        case .monochrome: return "Grayscale"
        case .lab: return "Lab"
        default: return "Unknown"
        }
    }()

    let hasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipFirst && cgImage.alphaInfo != .noneSkipLast

    let uti = CGImageSourceGetType(source).map { UTType($0 as String) }
    let format = uti??.preferredFilenameExtension?.uppercased() ?? url.pathExtension.uppercased().ifEmpty("Unknown")

    return ImageModel(
        filename: url.lastPathComponent,
        fileSize: fileSize,
        width: cgImage.width,
        height: cgImage.height,
        format: format,
        colorSpace: colorSpaceName,
        bitsPerComponent: cgImage.bitsPerComponent,
        bitsPerPixel: cgImage.bitsPerPixel,
        dpiX: dpiX,
        dpiY: dpiY,
        hasAlpha: hasAlpha,
        nsImage: nsImage,
        originalData: data
    )
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
