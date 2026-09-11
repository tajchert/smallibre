import Foundation

public struct LibraryQuery: Codable, Sendable, Equatable {
    public enum ReadState: String, Codable, Sendable, CaseIterable { case any, unread, read }
    public var text: String
    public var collection: String
    public var readState: ReadState
    public var tag: String
    public var series: String
    public init(text: String = "", collection: String = "all", readState: ReadState = .any, tag: String = "", series: String = "") {
        self.text = text; self.collection = collection; self.readState = readState; self.tag = tag; self.series = series
    }
    public func matches(_ book: LibraryBook) -> Bool {
        guard collection == "all" || (collection == "prepared" ? book.typography.enabled : book.metadata.format == collection) else { return false }
        if readState == .read && !book.organization.isRead { return false }
        if readState == .unread && book.organization.isRead { return false }
        if !tag.isEmpty && !book.organization.tags.contains(where: { Self.equal($0, tag) }) { return false }
        if !series.isEmpty && !Self.equal(book.organization.series, series) { return false }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let m = book.metadata
        let text = ([m.title, m.publisher, m.description, m.identifier, book.organization.series] + m.authors + book.organization.tags).joined(separator: " ")
        return words.allSatisfy { text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    private static func equal(_ left: String, _ right: String) -> Bool {
        left.compare(right, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

public struct SavedLibraryFilter: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var query: LibraryQuery
    public init(id: UUID = UUID(), name: String, query: LibraryQuery) { self.id = id; self.name = name; self.query = query }
}
