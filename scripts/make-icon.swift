import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 215, yRadius: 215)
        NSGradient(starting: NSColor(red: 0.31, green: 0.46, blue: 0.37, alpha: 1), ending: NSColor(red: 0.16, green: 0.29, blue: 0.23, alpha: 1))!.draw(in: background, angle: -75)
        let colors = [NSColor(red: 0.92, green: 0.86, blue: 0.69, alpha: 1), NSColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1), NSColor(red: 0.71, green: 0.78, blue: 0.61, alpha: 1)]
        for i in 0..<3 {
            let x = CGFloat(240 + i * 190), height = CGFloat(i == 1 ? 505 : 440)
            colors[i].setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 260, width: 145, height: height), xRadius: 20, yRadius: 20).fill()
            NSColor.black.withAlphaComponent(0.11).setFill()
            NSBezierPath(rect: NSRect(x: x + 17, y: 280, width: 5, height: height - 40)).fill()
            NSColor(red: 0.25, green: 0.38, blue: 0.29, alpha: 0.35).setFill()
            NSBezierPath(rect: NSRect(x: x + 38, y: 305, width: 70, height: 8)).fill()
            NSBezierPath(rect: NSRect(x: x + 38, y: 260 + height - 65, width: 70, height: 8)).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
