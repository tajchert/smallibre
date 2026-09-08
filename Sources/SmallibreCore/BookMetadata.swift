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
