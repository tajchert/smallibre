import Foundation

public struct BookMetadata: Codable, Sendable, Equatable {
    public var title: String
    public var authors: [String]
    public var language: String
    public var identifier: String
    public var publisher: String
    public var description: String
    public var format: String
    public var cover: Data?
    /// Publication date as the book declares it. Read-only: Smallibre never rewrites it.
    /// Optional so library records saved before this field decode unchanged.
    public var published: String? = nil
    /// The year alone, when the declared date starts with one.
    public var publishedYear: String? {
        guard let published else { return nil }
        let digits = published.prefix(while: \.isNumber)
        return digits.count == 4 ? String(digits) : (published.isEmpty ? nil : published)
    }
    /// Only the fields Smallibre can write back into a book. Cover bytes and the declared
    /// publication date are read-only, so comparing them would make an untouched book look
    /// edited and cost it its byte-identical original. Compare these, never the whole value.
    public var writableFields: BookMetadata {
        var copy = self; copy.cover = nil; copy.published = nil; return copy
    }
}

public enum BookError: Error, LocalizedError, Sendable {
    case invalid(String)
    case unsupported(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message), .unsupported(let message): message }
    }
}

public enum BookInspector {
    public static func inspect(_ url: URL) throws -> BookMetadata {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= ZIPArchive.maximumSize else { throw BookError.invalid("Books must be smaller than 256 MB.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if data.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]) { return try EPUBBook(data: data).metadata }
        return try MOBIBook.inspect(data)
    }
}
