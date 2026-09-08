import SwiftUI
import NovaCore

enum NovaTheme {
    static let accent = Color(light: NSColor(red: 0.25, green: 0.39, blue: 0.32, alpha: 1), dark: NSColor(red: 0.60, green: 0.76, blue: 0.64, alpha: 1))
    static let canvas = Color(light: NSColor(red: 0.975, green: 0.970, blue: 0.954, alpha: 1), dark: NSColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1))
    static let panel = Color(light: NSColor(red: 0.955, green: 0.948, blue: 0.929, alpha: 1), dark: NSColor(red: 0.15, green: 0.16, blue: 0.16, alpha: 1))
    static let covers: [Color] = [.init(red: 0.29, green: 0.41, blue: 0.35), .init(red: 0.62, green: 0.36, blue: 0.26), .init(red: 0.33, green: 0.40, blue: 0.53), .init(red: 0.53, green: 0.43, blue: 0.34), .init(red: 0.43, green: 0.35, blue: 0.46)]
}
extension Color {
    init(light: NSColor, dark: NSColor) { self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }) }
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

struct BookCover: View {
    let book: LibraryBook
    let root: URL
    var large = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = CoverCache.image(root.appendingPathComponent("covers/\(book.hash).png")) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let index = (Int(book.hash.prefix(2), radix: 16) ?? 0) % NovaTheme.covers.count
                    Rectangle().fill(NovaTheme.covers[index].gradient)
                    VStack(spacing: 0) {
                        Text("N O V A  L I B R A R Y").font(.system(size: max(7, proxy.size.width * 0.047), weight: .medium)).opacity(0.65)
                        Spacer(minLength: 12)
                        Text(book.metadata.title).font(.system(size: proxy.size.width * 0.135, weight: .regular, design: .serif)).multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.65)
                        Rectangle().frame(width: 30, height: 1).opacity(0.45).padding(.top, 18)
                        Spacer(minLength: 12)
                        Text(book.metadata.authors.joined(separator: " & ").uppercased()).font(.system(size: max(8, proxy.size.width * 0.05), weight: .medium)).tracking(1).lineLimit(2).multilineTextAlignment(.center).opacity(0.8)
                    }.padding(proxy.size.width * 0.13).foregroundStyle(.white)
                    HStack(spacing: 0) { Rectangle().fill(.black.opacity(0.12)).frame(width: 6); Rectangle().fill(.white.opacity(0.1)).frame(width: 1); Spacer() }
                }
            }
            .clipShape(.rect(cornerRadius: 4))
            .shadow(color: .black.opacity(0.15), radius: large ? 12 : 6, x: 2, y: 5)
        }.aspectRatio(0.67, contentMode: .fit)
        .accessibilityLabel("Cover of \(book.metadata.title)")
    }
}
