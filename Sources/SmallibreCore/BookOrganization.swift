import Foundation

/// Personal library fields. These never participate in ebook rewriting or conversion identity.
public struct BookOrganization: Codable, Sendable, Equatable {
    public var tags: [String]
    public var series: String
    public var seriesNumber: Double?
    public var isRead: Bool

    public init(tags: [String] = [], series: String = "", seriesNumber: Double? = nil, isRead: Bool = false) {
        self.tags = tags; self.series = series; self.seriesNumber = seriesNumber; self.isRead = isRead
    }

    public func normalized() throws -> Self {
        if let seriesNumber, !seriesNumber.isFinite || seriesNumber < 0 {
            throw BookError.invalid("Series number must be a finite number of zero or greater.")
        }
        let series = series.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !series.isEmpty || seriesNumber == nil else {
            throw BookError.invalid("Enter a series name before assigning a number.")
        }
        var tags: [String] = []
        for tag in self.tags {
            let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty && !tags.contains(where: { $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                tags.append(tag)
            }
        }
        return Self(tags: tags, series: series, seriesNumber: seriesNumber, isRead: isRead)
    }

    public var seriesLabel: String {
        guard let seriesNumber else { return series }
        return "\(series) · \(seriesNumber.formatted(.number.precision(.fractionLength(0...6))))"
    }
}
