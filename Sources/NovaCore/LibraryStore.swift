import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public struct TypographySettings: Codable, Sendable, Equatable {
    public enum Font: String, Codable, Sendable, CaseIterable { case original, serif, sansSerif }
    public var enabled: Bool = false
    public var font: Font = .original
    public var lineHeight: Double = 1.6
    public var marginPercent: Double = 5
    public init(enabled: Bool = false, font: Font = .original, lineHeight: Double = 1.6, marginPercent: Double = 5) {
        self.enabled = enabled; self.font = font; self.lineHeight = lineHeight; self.marginPercent = marginPercent
    }
}

public struct LibraryBook: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var metadata: BookMetadata
    public var addedAt: Date
    public var byteCount: Int
    public var originalFilename: String
    public var hash: String
    public var typography: TypographySettings
}

public struct ImportResult: Sendable { public let book: LibraryBook; public let isDuplicate: Bool }

public actor LibraryStore {
    public nonisolated let root: URL
    private let database: Database
    public init(root: URL) throws {
        self.root = root
        for name in ["originals", "covers", "staging"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true) }
        database = try Database(url: root.appendingPathComponent("library.sqlite"))
    }
    public func importBook(from url: URL) throws -> ImportResult {
        let manager = FileManager.default
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, size > 0, size <= ZIPArchive.maximumSize else { throw BookError.invalid("Choose a regular EPUB or MOBI file smaller than 256 MB.") }
        let staged = root.appendingPathComponent("staging/\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: url, to: staged)
        let bytes = try Data(contentsOf: staged, options: .mappedIfSafe)
        let hash = Self.digest(bytes)
        if let existing = try database.book(column: "hash", value: hash) { return ImportResult(book: existing, isDuplicate: true) }
        var metadata = try BookInspector.inspect(staged)
        // Validate every resource once at import, so unchanged exports cannot propagate unchecked ZIP corruption.
        if metadata.format == "EPUB" {
            let archive = try ZIPArchive(data: bytes)
            for name in archive.names { _ = try archive.data(named: name) }
        }
        if let cover = metadata.cover { Self.writeThumbnail(cover, to: root.appendingPathComponent("covers/\(hash).png")) }
        metadata.cover = nil
        let book = LibraryBook(id: UUID(), metadata: metadata, addedAt: Date(), byteCount: bytes.count, originalFilename: url.lastPathComponent, hash: hash, typography: TypographySettings())
        let destination = originalLocation(book)
        if !manager.fileExists(atPath: destination.path) { try manager.moveItem(at: staged, to: destination) }
        // A crash before this insert can leave an unreferenced original, but never a missing referenced original.
        try database.save(book, insert: true)
        return ImportResult(book: book, isDuplicate: false)
    }
    public func books(search: String = "") throws -> [LibraryBook] { try database.books(matching: search) }
    public func update(_ book: LibraryBook) throws {
        var saved = try requireBook(book.id)
        guard !book.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BookError.invalid("A book needs a title.") }
        saved.metadata.title = book.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.metadata.authors = book.metadata.authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        saved.metadata.language = book.metadata.language
        saved.metadata.publisher = book.metadata.publisher
        saved.metadata.description = book.metadata.description
        saved.typography = book.typography
        if saved.metadata.format != "EPUB", saved.typography.enabled { throw BookError.unsupported("Typography editing currently supports EPUB. MOBI/AZW3 files export unchanged.") }
        if saved.typography.enabled {
            guard saved.typography.lineHeight.isFinite, (1...2.4).contains(saved.typography.lineHeight), saved.typography.marginPercent.isFinite, (0...12).contains(saved.typography.marginPercent) else { throw BookError.invalid("Typography values are outside the supported range.") }
            guard try EPUBBook(data: Data(contentsOf: originalLocation(saved))).allowsTypography else { throw BookError.unsupported("This book uses fixed layout, scripts or media overlays. Its original typography must be preserved.") }
        }
        try database.save(saved, insert: false)
    }
    public func originalURL(for id: UUID) throws -> URL { originalLocation(try requireBook(id)) }
    public func supportsTypography(for id: UUID) throws -> Bool {
        let book = try requireBook(id)
        guard book.metadata.format == "EPUB" else { return false }
        return try EPUBBook(data: Data(contentsOf: originalLocation(book))).allowsTypography
    }
    public func preparedData(for id: UUID) throws -> Data {
        let book = try requireBook(id)
        let original = try Data(contentsOf: originalLocation(book), options: .mappedIfSafe)
        guard Self.digest(original) == book.hash else { throw BookError.invalid("The original file failed its integrity check. Restore it from a backup.") }
        guard book.metadata.format == "EPUB" else { return original }
        let epub = try EPUBBook(data: original)
        var originalMetadata = epub.metadata; originalMetadata.cover = nil
        if originalMetadata == book.metadata && !book.typography.enabled { return original }
        return try EPUBEditor.prepare(epub, metadata: book.metadata, typography: book.typography)
    }
    public func export(_ id: UUID, to folder: URL) throws -> URL {
        let book = try requireBook(id), data = try preparedData(for: id)
        let manager = FileManager.default
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw BookError.invalid("Choose an existing export folder.") }
        let title = Self.safeFilename(book.metadata.title)
        let ext = book.metadata.format.lowercased()
        let staging = folder.appendingPathComponent(".nova-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: staging) }
        try data.write(to: staging, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: staging)
        try handle.synchronize(); try handle.close()
        guard Self.digest(try Data(contentsOf: staging)) == Self.digest(data) else { throw BookError.invalid("Export verification failed. The original is safe.") }
        for index in 0..<10_000 {
            let name = title + (index == 0 ? "" : " (\(index + 1))") + "." + ext
            let destination = folder.appendingPathComponent(name)
            if manager.fileExists(atPath: destination.path) { continue }
            do { try manager.moveItem(at: staging, to: destination); return destination }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
        }
        throw BookError.invalid("Too many files with this name in the destination folder.")
    }
    private func requireBook(_ id: UUID) throws -> LibraryBook {
        guard let result = try database.book(column: "id", value: id.uuidString) else { throw BookError.invalid("This book is no longer in the library.") }
        return result
    }
    private func originalLocation(_ book: LibraryBook) -> URL { root.appendingPathComponent("originals/\(book.hash).\(book.metadata.format.lowercased())") }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func safeFilename(_ input: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        let clean = input.components(separatedBy: banned).joined(separator: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return clean.isEmpty ? "Untitled" : String(clean.prefix(100))
    }
    private static func writeThumbnail(_ data: Data, to url: URL) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 50_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
    }
}
