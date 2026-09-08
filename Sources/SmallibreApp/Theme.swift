import SwiftUI
import AppKit
import SmallibreCore

extension NSColor {
    /// Design tokens are authored as sRGB hex so they stay comparable with the source design.
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, alpha: alpha)
    }
}
extension Color {
    init(light: NSColor, dark: NSColor) { self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }) }
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(light: NSColor(hex: light, alpha: lightAlpha), dark: NSColor(hex: dark, alpha: darkAlpha))
    }
}

struct CoverPalette: Sendable { let background: Color; let ink: Color }

enum SmallibreTheme {
    // Surfaces
    static let sidebar = Color(light: 0xe6e6e8, dark: 0x2a2a2c)
    static let content = Color(light: 0xffffff, dark: 0x1e1e20)
    static let inspector = Color(light: 0xf6f6f7, dark: 0x242426)
    static let sheet = Color(light: 0xf1f1f3, dark: 0x2a2a2c)
    static let group = Color(light: NSColor(hex: 0xffffff), dark: NSColor(white: 1, alpha: 0.055))
    /// Compatibility aliases for screens that predate the design system.
    static let canvas = content
    static let panel = sidebar

    // Text
    static let text = Color(light: 0x1d1d1f, dark: 0xf2f2f2)
    static let text2 = Color(light: NSColor(white: 0, alpha: 0.58), dark: NSColor(white: 1, alpha: 0.60))
    static let text3 = Color(light: NSColor(white: 0, alpha: 0.42), dark: NSColor(white: 1, alpha: 0.40))

    // Lines and fills
    static let separator = Color(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.09))
    static let fill = Color(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.08))
    static let fill2 = Color(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.14))
    static let field = Color(light: NSColor(white: 0, alpha: 0.045), dark: NSColor(white: 1, alpha: 0.07))
    static let control = Color(light: NSColor(hex: 0xffffff), dark: NSColor(hex: 0x3a3a3c))
    static let controlBorder = Color(light: NSColor(white: 0, alpha: 0.13), dark: NSColor(white: 1, alpha: 0.10))

    // Accents
    static let accent = Color(light: 0x4f7d5c, dark: 0x86b092)
    static let onAccent = Color(light: 0xffffff, dark: 0x0e1a12)
    static let accentSoft = Color(light: NSColor(hex: 0x4f7d5c, alpha: 0.14), dark: NSColor(hex: 0x86b092, alpha: 0.20))
    static let destructive = Color(nsColor: NSColor(hex: 0xe5484d))
    static let online = Color(nsColor: NSColor(hex: 0x34c759))

    // Covers keep literal colours in both appearances, the way printed jackets do.
    static let covers: [CoverPalette] = [
        CoverPalette(background: Color(nsColor: NSColor(hex: 0x10233a)), ink: Color(nsColor: NSColor(hex: 0xd9e7f4))),
        CoverPalette(background: Color(nsColor: NSColor(hex: 0x5a7666)), ink: Color(nsColor: NSColor(hex: 0xeef3ee))),
        CoverPalette(background: Color(nsColor: NSColor(hex: 0x4d6a74)), ink: Color(nsColor: NSColor(hex: 0xe9f0f2))),
        CoverPalette(background: Color(nsColor: NSColor(hex: 0x8a6f5a)), ink: Color(nsColor: NSColor(hex: 0xf5ede5))),
        CoverPalette(background: Color(nsColor: NSColor(hex: 0x676c8e)), ink: Color(nsColor: NSColor(hex: 0xeceef7)))
    ]
    static let coverShadow = Color(light: NSColor(white: 0, alpha: 0.22), dark: NSColor(white: 0, alpha: 0.50))

    /// Iowan Old Style ships with macOS; the serif system face is a safe fallback if it is ever absent.
    static func serif(_ size: CGFloat) -> Font {
        NSFont(name: "IowanOldStyle-Roman", size: size) != nil ? .custom("IowanOldStyle-Roman", size: size) : .system(size: size, design: .serif)
    }
    static func palette(for hash: String) -> CoverPalette {
        covers[(Int(hash.prefix(2), radix: 16) ?? 0) % covers.count]
    }
}

/// A window appearance override. `system` follows macOS, matching the platform default.
enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark
    var appearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}

@MainActor enum Appearance {
    static let key = "appearance"
    static var mode: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }
    static func set(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        apply()
    }
    static func apply() { NSApplication.shared.appearance = mode.appearance }
}

@MainActor
enum CoverCache {
    static let images: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.totalCostLimit = 32 * 1024 * 1024; return cache }()
    static func image(_ url: URL) -> NSImage? {
        let key = url.path as NSString
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key, cost: 512 * 512 * 4)
        return image
    }
}

/// A printed jacket: imprint above, serif title in the middle, author set small at the foot.
struct BookCoverArt: View {
    let title: String
    let author: String
    let imprint: String
    let palette: CoverPalette
    var image: NSImage?
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: width, height: proxy.size.height).clipped()
                } else {
                    palette.background
                    VStack(spacing: 0) {
                        Text(imprint).font(.system(size: max(6, width * 0.054), weight: .semibold)).tracking(width * 0.0108).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(title).font(SmallibreTheme.serif(max(11, width * 0.142))).lineSpacing(width * 0.021).multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        Text(author.uppercased()).font(.system(size: max(6, width * 0.054), weight: .semibold)).tracking(width * 0.0086).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .padding(.horizontal, width * 0.095).padding(.top, width * 0.122).padding(.bottom, width * 0.108)
                    .foregroundStyle(palette.ink)
                }
                HStack(spacing: 0) { Rectangle().fill(.white.opacity(0.14)).frame(width: 3); Spacer(minLength: 0) }
            }
            .clipShape(.rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 7, topTrailingRadius: 7))
            .shadow(color: SmallibreTheme.coverShadow, radius: 9, x: 0, y: 8)
        }
        .aspectRatio(148.0 / 222.0, contentMode: .fit)
    }
}

struct BookCover: View {
    let book: LibraryBook
    let root: URL
    var body: some View {
        BookCoverArt(
            title: book.metadata.title,
            author: book.metadata.authors.isEmpty ? "Unknown author" : book.metadata.authors.joined(separator: " & "),
            imprint: book.metadata.publisher.isEmpty ? "NOVA LIBRARY" : book.metadata.publisher.uppercased(),
            palette: SmallibreTheme.palette(for: book.hash),
            image: CoverCache.image(root.appendingPathComponent("covers/\(book.hash).png"))
        )
        .accessibilityLabel("Cover of \(book.metadata.title)")
    }
}
