import SwiftUI
import AppKit

// MARK: - Shared views

struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 10
            var row = 0; var y: CGFloat = 0
            while y < size.height {
                var col = 0; var x: CGFloat = 0
                while x < size.width {
                    let color: Color = (row + col) % 2 == 0 ? .white : Color(white: 0.82)
                    ctx.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)), with: .color(color))
                    x += tile; col += 1
                }
                y += tile; row += 1
            }
        }
    }
}

// MARK: - NSImage helpers

extension NSImage {
    func pngData() -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: Double) -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
