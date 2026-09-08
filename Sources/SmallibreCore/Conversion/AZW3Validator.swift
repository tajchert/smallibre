import Foundation
import CryptoKit
import ImageIO

/// Decoder for the deliberately narrow native writer profile. No writer encoding helpers are used.
enum AZW3Validator {
    private struct Entry { let label: String; let values: [Int] }
    private static func failure() -> BookError { .invalid("Invalid native AZW3 structure.") }
    private static func require(_ condition: Bool) throws { if !condition { throw failure() } }
    private static func variable(_ bytes: Data, _ cursor: inout Int, end: Int) throws -> Int {
        var value = 0
        for index in 0..<5 {
            try require(cursor < end)
            let byte = bytes[cursor]; cursor += 1
            try require(index != 0 || byte != 0)
            value = value * 128 + Int(byte & 127)
            try require(value <= Int(UInt32.max))
            if byte & 128 != 0 { return value }
        }
        throw failure()
    }
    private static func string(_ bytes: Data, at offset: Int) throws -> String {
        var cursor = offset
        try require(cursor >= 0 && cursor < bytes.count)
        let length = try variable(bytes, &cursor, end: bytes.count)
        try require(length <= bytes.count - cursor)
        guard let string = String(data: bytes.subdata(in: cursor..<cursor + length), encoding: .utf8) else { throw failure() }
        return string
    }
    private static func index(_ master: Data, _ block: Data, tags: [UInt8], control: UInt8, values: Int, hasStrings: Bool) throws -> [Entry] {
        try require(master.count >= 192 && block.count >= 192)
        try require(master.starts(with: Data("INDX".utf8)) && block.starts(with: Data("INDX".utf8)))
        let count = Int(block.be32(24)), table = Int(block.be32(20))
        try require(count > 0 && count <= 512 && table >= 192 && table + 4 + count * 2 <= block.count)
        try require(block.subdata(in: table..<table + 4) == Data("IDXT".utf8))
        try require(master.be32(4) == 192 && master.be32(24) == 1 && master.be32(36) == count && master.be32(180) == 192)
        try require(master.be32(52) == (hasStrings ? 1 : 0))
        let tagEnd = 204 + tags.count
        try require(tagEnd <= master.count && master.subdata(in: 192..<196) == Data("TAGX".utf8))
        try require(master.be32(196) == 12 + tags.count && master.be32(200) == 1)
        try require(master.subdata(in: 204..<tagEnd) == Data(tags))
        let starts = (0..<count).map { Int(block.be16(table + 4 + $0 * 2)) }
        try require(starts[0] == 192 && zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 } && starts.last! < table)
        var result: [Entry] = []
        for number in 0..<count {
            try Task.checkCancellation()
            var cursor = starts[number]
            let end = number + 1 < count ? starts[number + 1] : table
            let length = Int(block[cursor]); cursor += 1
            try require(cursor + length < end)
            guard let label = String(data: block.subdata(in: cursor..<cursor + length), encoding: .utf8) else { throw failure() }
            cursor += length
            try require(block[cursor] == control); cursor += 1
            var decoded: [Int] = []
            for _ in 0..<values { decoded.append(try variable(block, &cursor, end: end)) }
            if number + 1 < count { try require(cursor == end) }
            else { try require(end - cursor < 4 && block[cursor..<end].allSatisfy { $0 == 0 }) }
            result.append(Entry(label: label, values: decoded))
        }
        // The master geometry points to the last entry label and declares the same count.
        let geometryTable = Int(master.be32(20))
        try require(geometryTable >= tagEnd && geometryTable + 6 <= master.count)
        try require(master.subdata(in: geometryTable..<geometryTable + 4) == Data("IDXT".utf8))
        let geometry = Int(master.be16(geometryTable + 4))
        try require(geometry >= tagEnd && geometry < geometryTable)
        let labelCount = Int(master[geometry])
        try require(geometry + 1 + labelCount + 2 <= geometryTable)
        try require(String(data: master.subdata(in: geometry + 1..<geometry + 1 + labelCount), encoding: .utf8) == result.last!.label)
        try require(master.be16(geometry + 1 + labelCount) == count)
        return result
    }

    static func validate(_ data: Data) throws {
        try Task.checkCancellation()
        try require(data.count >= 78 && data.count <= 32 * 1024 * 1024)
        try require(data.subdata(in: 60..<68) == Data("BOOKMOBI".utf8))
        let count = Int(data.be16(76)), tableEnd = 78 + count * 8 + 2
        try require(count > 8 && tableEnd < data.count)
        var offsets = (0..<count).map { Int(data.be32(78 + $0 * 8)) }
        try require(offsets[0] == tableEnd && offsets.allSatisfy { $0 >= tableEnd && $0 < data.count })
        try require(zip(offsets, offsets.dropFirst()).allSatisfy { $0 < $1 })
        offsets.append(data.count)
        func record(_ index: Int) throws -> Data {
            try require(index >= 0 && index < count)
            return data.subdata(in: offsets[index]..<offsets[index + 1])
        }
        let header = try record(0)
        try require(header.count >= 292 && header.be16(0) == 1 && header.be16(12) == 0)
        try require(header.subdata(in: 16..<20) == Data("MOBI".utf8) && header.be32(20) == 264 && header.be32(36) == 8 && header.be32(28) == 65001)
        let textCount = Int(header.be16(8))
        try require(textCount > 0 && textCount < count && header.be16(10) == 4096)
        var text = Data()
        for number in 1...textCount {
            try Task.checkCancellation()
            let bytes = try record(number)
            try require(bytes.count <= 4096 && String(data: bytes, encoding: .utf8) != nil)
            text.append(bytes)
        }
        try require(text.count == Int(header.be32(4)))
        let chunkIndex = Int(header.be32(248)), skeletonIndex = Int(header.be32(252)), navigationIndex = Int(header.be32(244))
        try require(chunkIndex == textCount + 1 && skeletonIndex == chunkIndex + 3 && navigationIndex == skeletonIndex + 2)
        let chunks = try index(record(chunkIndex), record(chunkIndex + 1), tags: [2,1,1,0,3,1,2,0,4,1,4,0,6,2,8,0,0,0,0,1], control: 15, values: 5, hasStrings: true)
        let skeletons = try index(record(skeletonIndex), record(skeletonIndex + 1), tags: [1,1,3,0,6,2,12,0,0,0,0,1], control: 10, values: 6, hasStrings: false)
        let navigation = try index(record(navigationIndex), record(navigationIndex + 1), tags: [1,1,1,0,2,1,2,0,3,1,4,0,4,1,8,0,21,1,16,0,22,1,32,0,23,1,64,0,6,2,128,0,0,0,0,1], control: 143, values: 6, hasStrings: true)
        try require(chunks.count == skeletons.count)
        let selectors = try record(chunkIndex + 2), labels = try record(navigationIndex + 2)
        var end = 0, insertions: [Int] = []
        for number in chunks.indices {
            let chunk = chunks[number], skeleton = skeletons[number], c = chunk.values, s = skeleton.values
            try require(skeleton.label == String(format: "SKEL%010d", number) && s[0] == 1 && s[1] == 1 && s[2] == end && s[4] == s[2] && s[5] == s[3])
            try require(c[1] == number && c[2] == number && c[3] == 0 && c[4] > 0 && c[4] <= 1024 * 1024)
            guard let insertion = Int(chunk.label) else { throw failure() }
            try require(chunk.label == String(format: "%010d", insertion))
            try require(s[3] > 13 && insertion > s[2] && insertion == s[2] + s[3] - 14)
            end = s[2] + s[3] + c[4]
            try require(end <= text.count)
            try require(text.subdata(in: insertion..<s[2] + s[3]) == Data("</body></html>".utf8))
            try require(try string(selectors, at: c[0]) == "P-//*[@aid='B\(number)']")
            insertions.append(insertion)
        }
        try require(end == text.count)
        for number in navigation.indices {
            let entry = navigation[number], v = entry.values
            try require(entry.label == String(format: "%0*X", max(2, String(navigation.count - 1, radix: 16).count), number) && v[3] == 0 && v[4] < chunks.count)
            try require(v[5] <= chunks[v[4]].values[4] && v[0] == insertions[v[4]] + v[5])
            let next = number + 1 < navigation.count ? navigation[number + 1].values[0] : text.count
            try require(next >= v[0] && v[1] == next - v[0])
            _ = try string(labels, at: v[2])
        }
        let flowIndex = Int(header.be32(192)), firstResource = Int(header.be32(108))
        let resources = flowIndex - (navigationIndex + 3)
        try require(resources >= 0 && resources <= 10_000 && flowIndex + 4 == count)
        try require(firstResource == (resources == 0 ? Int(UInt32.max) : navigationIndex + 3))
        var imageTypes: [String] = [], imageBytes = 0
        if resources > 0 {
            for number in 0..<resources {
                try Task.checkCancellation()
                let image = try record(firstResource + number)
                imageBytes += image.count
                try require(image.count <= 4 * 1024 * 1024 && imageBytes <= 16 * 1024 * 1024)
                let mime: String
                if image.starts(with: [137,80,78,71,13,10,26,10]) { mime = "image/png" }
                else if image.starts(with: [255,216,255]) { mime = "image/jpeg" }
                else { throw failure() }
                guard let source = CGImageSourceCreateWithData(image as CFData, nil), CGImageSourceGetCount(source) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw failure() }
                try require(width > 0 && height > 0 && width <= 8192 && height <= 8192 && width * height <= 16_000_000)
                imageTypes.append(mime)
            }
        }
        // Attribute values are escaped by the serializer; visible literal text cannot forge these quotes.
        let html = String(decoding: text, as: UTF8.self) as NSString
        let references = try NSRegularExpression(pattern: #"\s(href|src)="([^"]*)""#)
        for match in references.matches(in: html as String, range: NSRange(location: 0, length: html.length)) {
            try Task.checkCancellation()
            let kind = html.substring(with: match.range(at: 1)), value = html.substring(with: match.range(at: 2))
            if kind == "href" {
                let parts = value.components(separatedBy: ":")
                try require(parts.count == 6)
                try require(parts[0] == "kindle" && parts[1] == "pos" && parts[2] == "fid" && parts[4] == "off")
                guard let fragment = Int(parts[3], radix: 32), let offset = Int(parts[5], radix: 32) else { throw failure() }
                try require(parts[3].count == 4 && parts[5].count == 10 && fragment >= 0 && fragment < chunks.count && offset >= 0 && offset <= chunks[fragment].values[4])
            } else {
                let parts = value.components(separatedBy: "?mime=")
                try require(parts.count == 2 && parts[0].hasPrefix("kindle:embed:"))
                guard let resource = Int(parts[0].dropFirst(13), radix: 32) else { throw failure() }
                try require(resource > 0 && resource <= resources && parts[1] == imageTypes[resource - 1])
            }
        }
        let flow = try record(flowIndex)
        try require(flow.count == 20 && flow.starts(with: Data("FDST".utf8)) && flow.be32(4) == 12 && flow.be32(8) == 1 && flow.be32(12) == 0 && flow.be32(16) == text.count)
        try require(header.be32(196) == 1 && header.be32(200) == flowIndex + 2 && header.be32(204) == 1 && header.be32(208) == flowIndex + 1 && header.be32(212) == 1)
        let flis = try record(flowIndex + 1), fcis = try record(flowIndex + 2)
        let flisFields: [UInt32] = [8,0x00410000,0,UInt32.max,0x00010003,3,1,UInt32.max]
        let fcisFields: [UInt32] = [20,16,2,0,UInt32(text.count),0,40,0,40,8,0x00010001,0]
        try require(flis.count == 36 && flis.starts(with: Data("FLIS".utf8)) && fcis.count == 52 && fcis.starts(with: Data("FCIS".utf8)))
        for (position, value) in flisFields.enumerated() { try require(flis.be32(4 + position * 4) == value) }
        for (position, value) in fcisFields.enumerated() { try require(fcis.be32(4 + position * 4) == value) }
        try require(try record(count - 1) == Data([0xe9,0x8e,0x0d,0x0a]))
        // Validate bounded EXTH fields and the native document identity/reference fields.
        try require(header.subdata(in: 280..<284) == Data("EXTH".utf8))
        let exthEnd = 280 + Int(header.be32(284)), fields = Int(header.be32(288))
        try require(exthEnd >= 292 && exthEnd <= header.count && fields <= (exthEnd - 292) / 8)
        var cursor = 292, exth: [UInt32: [Data]] = [:]
        for _ in 0..<fields {
            try require(cursor + 8 <= exthEnd)
            let tag = header.be32(cursor), length = Int(header.be32(cursor + 4))
            try require(length >= 8 && length <= exthEnd - cursor)
            exth[tag, default: []].append(header.subdata(in: cursor + 8..<cursor + length)); cursor += length
        }
        try require(cursor == exthEnd)
        func field(_ tag: UInt32) throws -> Data { guard let values = exth[tag], values.count == 1 else { throw failure() }; return values[0] }
        let identifier = try field(113), source = try field(112), start = try field(116), resourceCount = try field(125)
        guard let uuid = String(data: identifier, encoding: .utf8), UUID(uuidString: uuid) != nil,
              let sourceString = String(data: source, encoding: .utf8), sourceString.hasPrefix("smallibre:") else { throw failure() }
        let sourceHash = try SHA256Digest(String(sourceString.dropFirst(10)))
        // Earlier immutable artifacts and receipts remain valid after converter upgrades.
        let validIdentity = ["1", AZW3Converter.version].contains { version in
            var identityInput = Data([0x6b,0xa7,0xb8,0x11,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8])
            identityInput.append(Data(("urn:smallibre:azw3:" + AZW3Converter.profile + ":" + version + ":sha256:" + sourceHash.value).utf8))
            var identityBytes = Array(Insecure.SHA1.hash(data: identityInput).prefix(16))
            identityBytes[6] = (identityBytes[6] & 15) | 80
            identityBytes[8] = (identityBytes[8] & 63) | 128
            let expected = identityBytes.map { String(format: "%02x", $0) }.joined()
            return uuid.replacingOccurrences(of: "-", with: "").lowercased() == expected
        }
        try require(validIdentity)
        try require(start.count == 4 && start.be32(0) == insertions[0] && resourceCount.count == 4 && resourceCount.be32(0) == resources)
        if exth[201] != nil { let cover = try field(201); try require(cover.count == 4 && cover.be32(0) < resources) }
        _ = try MOBIBook.inspect(data)
    }
}
