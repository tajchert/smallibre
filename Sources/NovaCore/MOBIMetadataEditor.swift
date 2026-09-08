import Foundation

/// Rewrites record-zero metadata only; text/image/navigation records remain byte-identical.
public enum MOBIMetadataEditor {
    public static func prepare(_ data: Data, metadata: BookMetadata) throws -> Data {
        _ = try MOBIBook.inspect(data)
        guard !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BookError.invalid("A book needs a title.") }
        guard data.be32(52) == 0, data.be32(56) == 0, data.be32(72) == 0 else { throw BookError.unsupported("This Palm database layout is not supported for metadata editing.") }
        let count = Int(data.be16(76)), start = Int(data.be32(78))
        let end = count > 1 ? Int(data.be32(86)) : data.count
        let record = data.subdata(in: start..<end), headerEnd = 16 + Int(record.be32(20))
        let version = record.be32(36), encodingID = record.be32(28)
        guard [6, 8].contains(version), [65001, 1252].contains(encodingID) else { throw BookError.unsupported("Metadata editing supports standalone MOBI 6 and AZW3 with UTF-8 or Windows-1252 text.") }
        let encoding: String.Encoding = encodingID == 65001 ? .utf8 : .windowsCP1252
        func encoded(_ string: String) throws -> Data {
            guard let bytes = string.data(using: encoding, allowLossyConversion: false), bytes.count <= 1024 * 1024 else { throw BookError.invalid("Metadata is too long or contains characters this book's encoding cannot represent.") }
            return bytes
        }
        var fields: [(UInt32, Data)] = [], exthEnd = headerEnd
        if record.be32(128) & 0x40 != 0 {
            exthEnd = headerEnd + Int(record.be32(headerEnd + 4))
            var cursor = headerEnd + 12
            for _ in 0..<Int(record.be32(headerEnd + 8)) {
                let type = record.be32(cursor), length = Int(record.be32(cursor + 4))
                let value = record.subdata(in: cursor + 8..<cursor + length)
                if type == 121, value.count == 4, value.be32(0) != UInt32.max { throw BookError.unsupported("Hybrid MOBI/KF8 metadata editing is not supported yet.") }
                if ![100,101,103,503,524].contains(type) { fields.append((type,value)) }
                cursor += length
            }
        }
        for author in metadata.authors { fields.append((100, try encoded(author))) }
        for (type, text): (UInt32, String) in [(101, metadata.publisher), (103, metadata.description), (503, metadata.title), (524, metadata.language)] where !text.isEmpty { fields.append((type, try encoded(text))) }
        var exth = Data("EXTH".utf8); exth.append(contentsOf: big(0)); exth.append(contentsOf: big(fields.count))
        for (type, value) in fields { exth.append(contentsOf: big(Int(type))); exth.append(contentsOf: big(value.count + 8)); exth.append(value) }
        while exth.count % 4 != 0 { exth.append(0) }
        exth.replaceSubrange(4..<8, with: big(exth.count))
        let oldTitle = Int(record.be32(84)), oldLength = Int(record.be32(88))
        guard oldTitle >= exthEnd, oldTitle + oldLength <= record.count else { throw BookError.unsupported("Unusual MOBI title layout; original preserved.") }
        let title = try encoded(metadata.title)
        var updated = Data(record.prefix(headerEnd)); updated.append(exth)
        updated.append(record.subdata(in: exthEnd..<oldTitle))
        let titleOffset = updated.count
        updated.append(title); updated.append(record.subdata(in: oldTitle + oldLength..<record.count))
        updated.replaceSubrange(84..<88, with: big(titleOffset)); updated.replaceSubrange(88..<92, with: big(title.count))
        updated.replaceSubrange(128..<132, with: big(Int(record.be32(128) | 0x40)))
        let delta = updated.count - record.count
        var output = Data(data.prefix(start)); output.append(updated); output.append(data.suffix(from: end))
        guard output.count <= ZIPArchive.maximumSize else { throw BookError.invalid("Edited book exceeds the size limit.") }
        for index in 1..<count { output.replaceSubrange(78 + index * 8..<82 + index * 8, with: big(Int(data.be32(78 + index * 8)) + delta)) }
        let result = try MOBIBook.inspect(output)
        guard result.title == metadata.title, result.authors == metadata.authors else { throw BookError.invalid("Metadata verification failed.") }
        return output
    }
    private static func big(_ value: Int) -> [UInt8] { [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)] }
}
