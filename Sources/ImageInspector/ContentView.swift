import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: HeaderFooterStore
    @State private var model: ImageModel?
    @State private var outputImage: NSImage?
    @State private var isProcessing = false
    @State private var isDragOver = false

    var body: some View {
        Group {
            if let model {
                mainLayout(model: model)
            } else {
                dropZone
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model != nil)
        .onChange(of: store.layoutVersion) {
            if let m = model { runProcessor(on: m) }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isDragOver ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isDragOver ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isDragOver)

            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(isDragOver ? Color.accentColor : Color.secondary)
                Text("Drop an image here")
                    .font(.title2)
                    .foregroundStyle(.primary)
                Text("PNG, JPEG, TIFF, GIF, WebP, HEIC and more")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Or choose a file…") { openPanel() }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
    }

    private func mainLayout(model: ImageModel) -> some View {
        HStack(spacing: 0) {
            ImagePanel(label: "Original", model: model, displayImage: model.nsImage, isOutput: false) {
                self.model = nil
                self.outputImage = nil
            }
            Divider()
            ImagePanel(
                label: "Output",
                model: model,
                displayImage: outputImage ?? model.nsImage,
                isOutput: true,
                isProcessing: isProcessing
            )
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        model = loadImageModel(from: url)
                        if let m = model { runProcessor(on: m) }
                    }
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
                    DispatchQueue.main.async {
                        model = loadImageModel(from: url)
                        if let m = model { runProcessor(on: m) }
                    }
                }
                return true
            }
        }
        return false
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model = loadImageModel(from: url)
            if let m = model { runProcessor(on: m) }
        }
    }

    private func runProcessor(on m: ImageModel) {
        isProcessing = true
        outputImage = nil
        // Capture current header/footer on the main thread before jumping to background.
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
