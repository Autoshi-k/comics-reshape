import SwiftUI
import AppKit

struct ImagePanel: View {
    let label: String
    let model: ImageModel
    let displayImage: NSImage
    let isOutput: Bool
    var isProcessing: Bool = false
    var onClear: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            imagePreview
            Divider()
            infoTable
            if isOutput {
                Divider()
                downloadBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelHeader: some View {
        HStack {
            Text(label)
                .font(.headline)
                .foregroundStyle(isOutput ? Color.accentColor : .primary)
            Spacer()
            if isOutput && isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 2)
            }
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Clear image")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var imagePreview: some View {
        ZStack {
            CheckerboardBackground()
            Image(nsImage: displayImage)
                .resizable()
                .scaledToFit()
                .padding(12)
                .opacity(isOutput && isProcessing ? 0.4 : 1)
            if isOutput && isProcessing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Detecting squares…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
    }

    // Info sourced from displayImage when showing output, from model when showing original.
    private var currentInfo: PanelInfo {
        if isOutput, let cg = displayImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let csName: String = {
                guard let cs = cg.colorSpace else { return "sRGB" }
                if let name = cs.name { return (name as String).components(separatedBy: "/").last ?? (name as String) }
                switch cs.model {
                case .rgb: return "RGB"
                case .cmyk: return "CMYK"
                case .monochrome: return "Grayscale"
                default: return "Unknown"
                }
            }()
            let hasAlpha = cg.alphaInfo != .none && cg.alphaInfo != .noneSkipFirst && cg.alphaInfo != .noneSkipLast
            let base = (model.filename as NSString).deletingPathExtension
            return PanelInfo(
                filename: "\(base)_output.png",
                format: "PNG",
                fileSize: "—",
                dimensions: "\(cg.width) × \(cg.height) px",
                dpi: "72 DPI",
                colorSpace: csName,
                bitDepth: "\(cg.bitsPerComponent) bpc · \(cg.bitsPerPixel) bpp",
                hasAlpha: hasAlpha
            )
        }
        return PanelInfo(
            filename: model.filename,
            format: model.format,
            fileSize: model.fileSizeFormatted,
            dimensions: model.dimensionsFormatted,
            dpi: model.dpiFormatted,
            colorSpace: model.colorSpace,
            bitDepth: "\(model.bitsPerComponent) bpc · \(model.bitsPerPixel) bpp",
            hasAlpha: model.hasAlpha
        )
    }

    private var infoTable: some View {
        let i = currentInfo
        return VStack(alignment: .leading, spacing: 0) {
            infoRow("Filename", i.filename)
            Divider().padding(.leading, 16)
            infoRow("Format", i.format)
            Divider().padding(.leading, 16)
            infoRow("File Size", i.fileSize)
            Divider().padding(.leading, 16)
            infoRow("Dimensions", i.dimensions)
            Divider().padding(.leading, 16)
            infoRow("Resolution", i.dpi)
            Divider().padding(.leading, 16)
            infoRow("Color Space", i.colorSpace)
            Divider().padding(.leading, 16)
            infoRow("Bit Depth", i.bitDepth)
            Divider().padding(.leading, 16)
            infoRow("Alpha Channel", i.hasAlpha ? "Yes" : "No")
        }
        .padding(.vertical, 4)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var downloadBar: some View {
        HStack {
            Spacer()
            Menu {
                Button("Save as PNG…") { saveImage(as: .png) }
                Button("Save as JPEG…") { saveImage(as: .jpeg) }
                Button("Save as Original Format…") { saveOriginal() }
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.medium))
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func saveImage(as format: ImageFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = outputFilename(for: format)
        panel.allowedContentTypes = [format == .png ? .png : .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data? = switch format {
        case .png: displayImage.pngData()
        case .jpeg: displayImage.jpegData(compressionQuality: 0.92)
        }
        guard let data else { return }
        try? data.write(to: url)
    }

    private func saveOriginal() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.originalData.write(to: url)
    }

    private func outputFilename(for format: ImageFormat) -> String {
        let base = (model.filename as NSString).deletingPathExtension
        return "\(base)_output.\(format == .png ? "png" : "jpg")"
    }
}

private enum ImageFormat { case png, jpeg }

private struct PanelInfo {
    var filename: String
    var format: String
    var fileSize: String
    var dimensions: String
    var dpi: String
    var colorSpace: String
    var bitDepth: String
    var hasAlpha: Bool
}

extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: Double) -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tileSize: CGFloat = 10
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    let color: Color = (row + col) % 2 == 0 ? .white : Color(white: 0.82)
                    ctx.fill(Path(CGRect(x: x, y: y, width: tileSize, height: tileSize)), with: .color(color))
                    x += tileSize
                    col += 1
                }
                y += tileSize
                row += 1
            }
        }
    }
}
