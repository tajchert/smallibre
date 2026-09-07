import Foundation

enum MOBIBook {
    static func inspect(_ data: Data) throws -> BookMetadata {
        guard data.count >= 86, data.subdata(in: 60..<68) == Data("BOOKMOBI".utf8) else { throw BookError.invalid("This file is not a supported EPUB or MOBI book.") }
        let count = Int(data.be16(76))
        guard count > 0, 78 + count * 8 <= data.count else { throw BookError.invalid("Invalid MOBI record table.") }
        let offsets = (0..<count).map { Int(data.be32(78 + $0 * 8)) } + [data.count]
        guard offsets[0] >= 78 + count * 8, zip(offsets, offsets.dropFirst()).allSatisfy({ $0 < $1 }), offsets.allSatisfy({ $0 <= data.count }) else { throw BookError.invalid("Damaged MOBI records.") }
        let record = data.subdata(in: offsets[0]..<offsets[1])
        guard record.count >= 132, record.subdata(in: 16..<20) == Data("MOBI".utf8) else { throw BookError.invalid("Missing MOBI header.") }
        guard record.be16(12) == 0 else { throw BookError.unsupported("This MOBI is protected. Nova supports DRM-free books.") }
        let length = Int(record.be32(20)), version = record.be32(36)
        guard length >= 116, 16 + length <= record.count else { throw BookError.invalid("Invalid MOBI header length.") }
        let encoding: String.Encoding = record.be32(28) == 65001 ? .utf8 : .windowsCP1252
        func text(_ bytes: Data) -> String { (String(data: bytes, encoding: encoding) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let titleOffset = Int(record.be32(84)), titleLength = Int(record.be32(88))
        guard titleOffset + titleLength <= record.count else { throw BookError.invalid("Invalid MOBI title reference.") }
        var title = text(record.subdata(in: titleOffset..<titleOffset + titleLength))
        var authors: [String] = [], publisher = "", description = "", identifier = "", language = ""
        var coverOffset: Int?
        if record.be32(128) & 0x40 != 0 {
            let start = 16 + length
            guard start + 12 <= record.count, record.subdata(in: start..<start + 4) == Data("EXTH".utf8) else { throw BookError.invalid("Invalid MOBI metadata header.") }
            let end = start + Int(record.be32(start + 4)), fields = Int(record.be32(start + 8))
            guard end <= record.count, end >= start + 12, fields <= 10_000 else { throw BookError.invalid("Invalid MOBI metadata length.") }
            var cursor = start + 12
            for _ in 0..<fields {
                guard cursor + 8 <= end else { throw BookError.invalid("Truncated MOBI metadata.") }
                let type = record.be32(cursor), size = Int(record.be32(cursor + 4))
                guard size >= 8, cursor + size <= end else { throw BookError.invalid("Invalid MOBI metadata record.") }
                let value = record.subdata(in: cursor + 8..<cursor + size)
                switch type {
                case 100: authors.append(text(value))
                case 101: publisher = text(value)
                case 103: description = text(value)
                case 104: identifier = text(value)
                case 503: title = text(value)
                case 524: language = text(value)
                case 201: if value.count == 4 { coverOffset = Int(value.be32(0)) }
                default: break
                }
                cursor += size
            }
        }
        var cover: Data?
        if let coverOffset {
            let index = Int(record.be32(108)) + coverOffset
            if index >= 0, index < count, offsets[index + 1] - offsets[index] < 12 * 1024 * 1024 { cover = data.subdata(in: offsets[index]..<offsets[index + 1]) }
        }
        return BookMetadata(title: title.isEmpty ? "Untitled" : title, authors: authors, language: language, identifier: identifier, publisher: publisher, description: description, format: version >= 8 ? "AZW3" : "MOBI", cover: cover)
    }
}
