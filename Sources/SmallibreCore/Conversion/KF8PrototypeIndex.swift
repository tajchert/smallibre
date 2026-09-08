import Foundation

/// Bounded single-record INDX encoder; oversized index records are rejected.
enum KF8PrototypeIndex {
    struct Entry { let label: String; let control: UInt8; let values: [Int] }
    static func records(tags: [[UInt8]], entries: [Entry], strings: Data = Data()) throws -> [Data] {
        guard !entries.isEmpty, entries.count <= 512, strings.count < 60_000 else { throw BookError.unsupported("Prototype index limit exceeded.") }
        var block = Data(repeating: 0, count: 192), offsets: [Int] = []
        block.replaceSubrange(0..<4, with: Data("INDX".utf8))
        try set32(&block, 4, 192); try set32(&block, 12, 1)
        try set32(&block, 24, entries.count); try set32(&block, 28, Int(UInt32.max)); try set32(&block, 32, Int(UInt32.max))
        for entry in entries {
            try Task.checkCancellation()
            let label = Data(entry.label.utf8)
            guard label.count <= 255 else { throw BookError.invalid("Prototype index label too long.") }
            offsets.append(block.count); block.append(UInt8(label.count)); block.append(label); block.append(entry.control)
            for value in entry.values { block.append(try variable(value)) }
        }
        align(&block)
        try set32(&block, 20, block.count)
        block.append(Data("IDXT".utf8))
        for offset in offsets { block.append(try half(offset)) }
        align(&block)
        guard block.count <= 65535 else { throw BookError.unsupported("Prototype index record is too large.") }
        var master = Data(repeating: 0, count: 192)
        master.replaceSubrange(0..<4, with: Data("INDX".utf8))
        for (offset, value) in [(4,192),(16,2),(24,1),(28,65001),(32,Int(UInt32.max)),(36,entries.count),(52,strings.isEmpty ? 0 : 1),(180,192)] {
            try set32(&master, offset, value)
        }
        var table = Data("TAGX".utf8)
        table.append(try word(12 + (tags.count + 1) * 4)); table.append(try word(1))
        for tag in tags { table.append(contentsOf: tag) }
        table.append(contentsOf: [0,0,0,1]); master.append(table); align(&master)
        let geometryOffset = master.count, lastLabel = Data(entries[entries.count - 1].label.utf8)
        master.append(UInt8(lastLabel.count)); master.append(lastLabel); master.append(try half(entries.count)); align(&master)
        try set32(&master, 20, master.count)
        master.append(Data("IDXT".utf8)); master.append(try half(geometryOffset)); align(&master)
        var result = [master,block]
        if !strings.isEmpty { var strings = strings; align(&strings); result.append(strings) }
        return result
    }
    static func variable(_ value: Int) throws -> Data {
        guard value >= 0, value <= Int(UInt32.max) else { throw BookError.invalid("Invalid KF8 variable integer.") }
        var value = value, bytes = [UInt8(value & 127) | 128]
        value >>= 7
        while value > 0 { bytes.insert(UInt8(value & 127), at: 0); value >>= 7 }
        return Data(bytes)
    }
    static func word(_ value: Int) throws -> Data {
        guard let n = UInt32(exactly: value) else { throw BookError.invalid("KF8 32-bit field overflow.") }
        return Data([UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)])
    }
    static func half(_ value: Int) throws -> Data {
        guard let n = UInt16(exactly: value) else { throw BookError.invalid("KF8 16-bit field overflow.") }
        return Data([UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)])
    }
    static func set32(_ data: inout Data, _ offset: Int, _ value: Int) throws {
        guard offset >= 0, offset <= data.count - 4 else { throw BookError.invalid("KF8 field out of bounds.") }
        data.replaceSubrange(offset..<offset + 4, with: try word(value))
    }
    static func set16(_ data: inout Data, _ offset: Int, _ value: Int) throws {
        guard offset >= 0, offset <= data.count - 2 else { throw BookError.invalid("KF8 field out of bounds.") }
        data.replaceSubrange(offset..<offset + 2, with: try half(value))
    }
    static func align(_ data: inout Data) { while data.count % 4 != 0 { data.append(0) } }
}
