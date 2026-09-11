import Foundation

/// nil means leave the field alone; an explicitly empty value clears it.
public struct BulkMetadataEdit: Sendable {
    public enum Tags: Sendable { case add([String]), remove([String]), replace([String]) }
    public struct Series: Sendable {
        public var name: String
        public var number: Double?
        public init(name: String, number: Double?) { self.name = name; self.number = number }
    }
    public var authors: [String]?
    public var publisher: String?
    public var language: String?
    public var tags: Tags?
    public var series: Series?
    public var isRead: Bool?
    public init() {}

    func applying(to source: LibraryBook) throws -> LibraryBook {
        var book = source
        if let authors { book.metadata.authors = authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        if let publisher { book.metadata.publisher = publisher.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let language { book.metadata.language = language.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let tags {
            switch tags {
            case .add(let values): book.organization.tags += values
            case .replace(let values): book.organization.tags = values
            case .remove(let values):
                let values = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                book.organization.tags.removeAll { tag in values.contains { tag.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } }
            }
        }
        if let series { book.organization.series = series.name; book.organization.seriesNumber = series.number }
        if let isRead { book.organization.isRead = isRead }
        book.organization = try book.organization.normalized()
        return book
    }
}
