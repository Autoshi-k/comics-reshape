import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: HeaderFooterStore
    @State private var model: ImageModel?
    @State private var outputImage: NSImage?
    @State private var isProcessing = false
    @State private var isDragOver = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                columnA
                    .frame(width: geo.size.width * 0.40)
                Divider()
                columnB
                    .frame(width: geo.size.width * 0.28)
                Divider()
                columnC
            }
        }
        .frame(minWidth: 960, minHeight: 580)
        .onChange(of: store.layoutVersion) {
            if let m = model { runProcessor(on: m) }
        }
    }

    // MARK: - Column A: input + header/footer settings

    private var columnA: some View {
        VStack(spacing: 0) {
            headerFooterSection
            Divider()
            if let model {
                inputImageSection(model: model)
            } else {
                dropZone
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Column B: output image preview

    private var columnB: some View {
        ZStack {
            CheckerboardBackground()
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Detecting squares…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let img = outputImage {
                ScrollView(.vertical) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            } else {
                Text(model == nil ? "Load an image to see output" : "Processing…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Column C: output details + download

    private var columnC: some View {
        VStack(spacing: 0) {
            columnHeader("Output Details")
            Divider()
            if let img = outputImage, let m = model {
                ScrollView {
                    infoTable(rows: outputInfoRows(image: img, sourceModel: m))
                }
            } else {
                Spacer()
                Text("No output yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            Divider()
            downloadBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header & Footer section (top of column A)

    private var headerFooterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("Header & Footer")
            Divider()
            slotRow(
                label: "Header",
                image: store.headerImage,
                onSet:    { pickImage { store.setHeader($0) } },
                onRemove: { store.removeHeader() }
            )
            Divider().padding(.leading, 16)
            slotRow(
                label: "Footer",
                image: store.footerImage,
                onSet:    { pickImage { store.setFooter($0) } },
                onRemove: { store.removeFooter() }
            )
        }
    }

    private func slotRow(label: String, image: NSImage?, onSet: @escaping () -> Void, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 38)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 64, height: 38)
                    .overlay(Text("None").font(.caption2).foregroundStyle(.tertiary))
            }

            Spacer()
            Button("Set…", action: onSet).controlSize(.small).buttonStyle(.bordered)
            if image != nil {
                Button("Remove", action: onRemove).controlSize(.small).buttonStyle(.bordered).tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Input image section (column A, when image is loaded)

    private func inputImageSection(model: ImageModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Preview
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        CheckerboardBackground()
                        Image(nsImage: model.nsImage)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

                    Button {
                        self.model = nil
                        self.outputImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Clear image")
                }

                Divider()
                columnHeader("Image Details")
                Divider()
                infoTable(rows: inputInfoRows(model: model))
            }
        }
    }

    // MARK: - Drop zone (column A, when no image is loaded)

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDragOver ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDragOver ? Color.accentColor.opacity(0.07) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isDragOver)

            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(isDragOver ? Color.accentColor : Color.secondary)
                Text("Drop an image here")
                    .font(.title3)
                Text("PNG, JPEG, TIFF, WebP, HEIC…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Or choose a file…") { openPanel() }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragOver, perform: handleDrop)
    }

    // MARK: - Shared UI helpers

    private func columnHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func infoTable(rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                if idx > 0 { Divider().padding(.leading, 16) }
                HStack {
                    Text(row.0)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text(row.1)
                        .font(.callout.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
        }
        .padding(.vertical, 4)
    }

    private var downloadBar: some View {
        HStack {
            Spacer()
            Menu {
                Button("Save as PNG…")  { saveOutput(as: .png) }
                Button("Save as JPEG…") { saveOutput(as: .jpeg) }
            } label: {
                Label("Download Output", systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.medium))
            }
            .menuStyle(.borderedButton)
            .fixedSize()
            .disabled(outputImage == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Info row data

    private func inputInfoRows(model: ImageModel) -> [(String, String)] {[
        ("Filename",      model.filename),
        ("Format",        model.format),
        ("File Size",     model.fileSizeFormatted),
        ("Dimensions",    model.dimensionsFormatted),
        ("Resolution",    model.dpiFormatted),
        ("Color Space",   model.colorSpace),
        ("Bit Depth",     "\(model.bitsPerComponent) bpc · \(model.bitsPerPixel) bpp"),
        ("Alpha Channel", model.hasAlpha ? "Yes" : "No"),
    ]}

    private func outputInfoRows(image: NSImage, sourceModel: ImageModel) -> [(String, String)] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let csName: String = {
            guard let cs = cg.colorSpace else { return "sRGB" }
            if let name = cs.name { return (name as String).components(separatedBy: "/").last ?? (name as String) }
            switch cs.model {
            case .rgb:        return "RGB"
            case .cmyk:       return "CMYK"
            case .monochrome: return "Grayscale"
            default:          return "Unknown"
            }
        }()
        let hasAlpha = cg.alphaInfo != .none && cg.alphaInfo != .noneSkipFirst && cg.alphaInfo != .noneSkipLast
        let base = (sourceModel.filename as NSString).deletingPathExtension
        return [
            ("Filename",      "\(base)_output.png"),
            ("Format",        "PNG"),
            ("File Size",     "—"),
            ("Dimensions",    "\(cg.width) × \(cg.height) px"),
            ("Resolution",    "72 DPI"),
            ("Color Space",   csName),
            ("Bit Depth",     "\(cg.bitsPerComponent) bpc · \(cg.bitsPerPixel) bpp"),
            ("Alpha Channel", hasAlpha ? "Yes" : "No"),
        ]
    }

    // MARK: - Download

    private func saveOutput(as format: SaveFormat) {
        guard let img = outputImage, let m = model else { return }
        let panel = NSSavePanel()
        let base = (m.filename as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base)_output.\(format == .png ? "png" : "jpg")"
        panel.allowedContentTypes = [format == .png ? .png : .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data? = format == .png ? img.pngData() : img.jpegData(compressionQuality: 0.92)
        try? data?.write(to: url)
    }

    // MARK: - Image loading & processing

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { loadAndProcess(url: url) }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url: URL? = {
                        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                        if let u = item as? URL { return u }
                        return nil
                    }()
                    guard let url else { return }
                    DispatchQueue.main.async { loadAndProcess(url: url) }
                }
                return true
            }
        }
        return false
    }

    private func pickImage(then assign: @escaping (NSImage) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        assign(image)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            loadAndProcess(url: url)
        }
    }

    private func loadAndProcess(url: URL) {
        model = loadImageModel(from: url)
        if let m = model { runProcessor(on: m) }
    }

    private func runProcessor(on m: ImageModel) {
        isProcessing = true
        outputImage = nil
        let header = store.headerImage
        let footer = store.footerImage
        DispatchQueue.global(qos: .userInitiated).async {
            let result = processImage(m.nsImage, header: header, footer: footer)
            DispatchQueue.main.async {
                outputImage = result
                isProcessing = false
            }
        }
    }
}

private enum SaveFormat { case png, jpeg }
