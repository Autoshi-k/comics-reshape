import AppKit
import Foundation

@MainActor
final class HeaderFooterStore: ObservableObject {
    @Published private(set) var headerImage: NSImage?
    @Published private(set) var footerImage: NSImage?
    /// Increments whenever header or footer changes — observe this to re-run processing.
    @Published private(set) var layoutVersion: Int = 0

    private let headerURL: URL
    private let footerURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageInspector", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        headerURL = dir.appendingPathComponent("header.png")
        footerURL = dir.appendingPathComponent("footer.png")
        headerImage = NSImage(contentsOf: headerURL)
        footerImage = NSImage(contentsOf: footerURL)
    }

    func setHeader(_ image: NSImage) {
        headerImage = image
        persist(image, to: headerURL)
        layoutVersion += 1
    }

    func setFooter(_ image: NSImage) {
        footerImage = image
        persist(image, to: footerURL)
        layoutVersion += 1
    }

    func removeHeader() {
        headerImage = nil
        try? FileManager.default.removeItem(at: headerURL)
        layoutVersion += 1
    }

    func removeFooter() {
        footerImage = nil
        try? FileManager.default.removeItem(at: footerURL)
        layoutVersion += 1
    }

    private func persist(_ image: NSImage, to url: URL) {
        guard let data = image.pngData() else { return }
        try? data.write(to: url)
    }
}
