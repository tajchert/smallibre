import Foundation
import CryptoKit

/// Isolated C1 serializer, not enabled in export/send UI. Uncompressed standalone KF8, one bounded
/// fragment per chapter. Format evidence and missing hardware proof are documented separately.
enum AZW3PrototypeWriter {
    static func convert(_ epub: Data) throws -> Data {
        let document = try AZW3PrototypeDocument(epub)
        var text = Data(), starts: [Int] = [], skeletonLengths: [Int] = [], insertions: [Int] = []
        var fragmentLengths: [Int] = []
        for (index, chapter) in document.chapters.enumerated() {
            try Task.checkCancellation()
            let prefix = Data(("<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>" + AZW3PrototypeDocument.escape(chapter.title) + "</title></head><body aid=\"B\(index)\">").utf8)
            let suffix = Data("</body></html>".utf8), fragment = Data(chapter.body.utf8)
            starts.append(text.count); insertions.append(text.count + prefix.count)
            skeletonLengths.append(prefix.count + suffix.count); fragmentLengths.append(fragment.count)
            text.append(prefix); text.append(suffix); text.append(fragment)
        }
        var records = [Data()], position = 0
        // Keep every record individually valid UTF-8 without overlap trailers; flags declare no trailers.
        while position < text.count {
            var end = min(position + 4096, text.count)
            while end < text.count, text[end] & 0xc0 == 0x80 { end -= 1 }
            records.append(text.subdata(in: position..<end)); position = end
        }
        let textCount = records.count - 1
        var selectors = Data(), chunkEntries: [KF8PrototypeIndex.Entry] = []
        for index in document.chapters.indices {
            let offset = selectors.count
            // P selects the parent containing this fragment; it is not the file ordinal.
            let selector = Data("P-//*[@aid='B\(index)']".utf8)
            selectors.append(try KF8PrototypeIndex.variable(selector.count)); selectors.append(selector)
            chunkEntries.append(.init(label: String(format: "%010d", insertions[index]), control: 15,
                                      values: [offset, index, index, 0, fragmentLengths[index]]))
        }
        let chunkIndex = records.count
        records += try KF8PrototypeIndex.records(tags: [[2,1,1,0], [3,1,2,0], [4,1,4,0], [6,2,8,0]], entries: chunkEntries, strings: selectors)
        let skeletonIndex = records.count
        let skeletonEntries = document.chapters.indices.map { index in
            KF8PrototypeIndex.Entry(label: String(format: "SKEL%010d", index), control: 10,
                                    values: [1,1,starts[index],skeletonLengths[index],starts[index],skeletonLengths[index]])
        }
        records += try KF8PrototypeIndex.records(tags: [[1,1,3,0], [6,2,12,0]], entries: skeletonEntries)
        let navigationIndex = records.count
        var labels = Data(), navEntries: [KF8PrototypeIndex.Entry] = []
        let offsets = document.navigation.map { insertions[$0.chapter] + $0.offset }
        guard zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw BookError.unsupported("The prototype requires navigation in reading order.")
        }
        for (index, nav) in document.navigation.enumerated() {
            let labelOffset = labels.count, label = Data(nav.title.utf8)
            labels.append(try KF8PrototypeIndex.variable(label.count)); labels.append(label)
            let next = index + 1 < offsets.count ? offsets[index + 1] : text.count
            navEntries.append(.init(label: String(format: "%02X", index), control: 143,
                                    values: [offsets[index], next - offsets[index], labelOffset, 0, nav.chapter, nav.offset]))
        }
        records += try KF8PrototypeIndex.records(tags: [[1,1,1,0], [2,1,2,0], [3,1,4,0], [4,1,8,0], [21,1,16,0], [22,1,32,0], [23,1,64,0], [6,2,128,0]], entries: navEntries, strings: labels)
        let firstResource = document.resources.isEmpty ? Int(UInt32.max) : records.count
        records += document.resources.map(\.data)
        let fdst = records.count
        var flow = Data("FDST".utf8)
        for value in [12,1,0,text.count] { flow.append(try KF8PrototypeIndex.word(value)) }
        records.append(flow)
        let flis = records.count
        // Fixed-layout auxiliary record fields, serialized in network byte order.
        var flisData = Data("FLIS".utf8)
        for value in [8,0x00410000,0,Int(UInt32.max),0x00010003,3,1,Int(UInt32.max)] { flisData.append(try KF8PrototypeIndex.word(value)) }
        records.append(flisData)
        let fcis = records.count
        var fcisData = Data("FCIS".utf8)
        for value in [20,16,2,0,text.count,0,40,0,40,8,0x00010001,0] { fcisData.append(try KF8PrototypeIndex.word(value)) }
        records.append(fcisData)
        records.append(Data([0xe9,0x8e,0x0d,0x0a]))

        var exthFields: [(Int, Data)] = document.metadata.authors.map { (100, Data($0.utf8)) }
        exthFields += [(503,Data(document.metadata.title.utf8)), (524,Data(document.metadata.language.utf8)),
                       (501,Data("PDOC".utf8)), (112,Data(("smallibre:" + SHA256Digest.digest(epub).value).utf8)),
                       (113,Data(documentIdentifier(epub).utf8)),
                       (116,try KF8PrototypeIndex.word(insertions[0])), (125,try KF8PrototypeIndex.word(document.resources.count))]
        if !document.metadata.publisher.isEmpty { exthFields.append((101,Data(document.metadata.publisher.utf8))) }
        var fields = Data()
        for (tag, value) in exthFields {
            guard value.count <= 16 * 1024 else { throw BookError.unsupported("Prototype metadata is too large.") }
            fields.append(try KF8PrototypeIndex.word(tag)); fields.append(try KF8PrototypeIndex.word(value.count + 8)); fields.append(value)
        }
        var exth = Data("EXTH".utf8)
        exth.append(try KF8PrototypeIndex.word(fields.count + 12)); exth.append(try KF8PrototypeIndex.word(exthFields.count)); exth.append(fields)
        KF8PrototypeIndex.align(&exth)
        var header = Data(repeating: 0, count: 280)
        try KF8PrototypeIndex.set16(&header, 0, 1)
        try KF8PrototypeIndex.set32(&header, 4, text.count)
        try KF8PrototypeIndex.set16(&header, 8, textCount)
        try KF8PrototypeIndex.set16(&header, 10, 4096)
        header.replaceSubrange(16..<20, with: Data("MOBI".utf8))
        for offset in [40,44,48,52,56,60,64,68,72,76,164,168,224,232,236,256,260,264,272] {
            try KF8PrototypeIndex.set32(&header, offset, Int(UInt32.max))
        }
        let title = Data(document.metadata.title.utf8)
        let values = [(20,264), (24,2), (28,65001), (32,Int(UInt32(SHA256Digest.digest(text).value.prefix(8), radix:16) ?? 1)),
                      (36,8), (80,textCount + 1), (84,280 + exth.count), (88,title.count), (92,document.metadata.language == "en" ? 9 : 0),
                      (104,8), (108,firstResource), (128,0x50), (192,fdst), (196,1), (200,fcis), (204,1), (208,flis), (212,1),
                      (244,navigationIndex), (248,chunkIndex), (252,skeletonIndex)]
        for (offset, value) in values { try KF8PrototypeIndex.set32(&header, offset, value) }
        header.append(exth); header.append(title); KF8PrototypeIndex.align(&header)
        records[0] = header
        guard records.count < 65536 else { throw BookError.invalid("Too many prototype records.") }
        var output = Data(repeating: 0, count: 78)
        let name = Data("Smallibre_native_prototype".utf8)
        output.replaceSubrange(0..<name.count, with: name)
        output.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        try KF8PrototypeIndex.set32(&output, 68, records.count * 2 - 1)
        try KF8PrototypeIndex.set16(&output, 76, records.count)
        var offset = 78 + records.count * 8 + 2
        for (index, record) in records.enumerated() {
            output.append(try KF8PrototypeIndex.word(offset)); output.append(try KF8PrototypeIndex.word(index * 2)); offset += record.count
        }
        guard offset <= 32 * 1024 * 1024 else { throw BookError.unsupported("Prototype output exceeds 32 MB.") }
        output.append(contentsOf: [0,0])
        for record in records { try Task.checkCancellation(); output.append(record) }
        return output
    }

    /// UUIDv5 in the URL namespace, named by the prototype profile and prepared EPUB SHA-256.
    /// SHA-1 is used only by the UUIDv5 naming algorithm, never for integrity verification.
    /// A stable ID keeps repeated conversions deterministic; changed input gets a new identity.
    private static func documentIdentifier(_ epub: Data) -> String {
        var name = Data([0x6b,0xa7,0xb8,0x11,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8])
        name.append(Data(("urn:smallibre:azw3:prototype:v1:sha256:" + SHA256Digest.digest(epub).value).utf8))
        var bytes = Array(Insecure.SHA1.hash(data: name).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                           bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])).uuidString.lowercased()
    }

}
