import Foundation
import CZlib

/// A bounded ZIP container. Resources remain in memory; archive paths never reach the filesystem.
public struct ZIPArchive: Sendable {
    struct Entry: Sendable {
        let name: String
        let method: UInt16
        let crc: UInt32
        let size: Int
        let compressed: Data
    }
    private var entries: [Entry]
    public var names: [String] { entries.map(\.name) }
    public static let maximumSize = 256 * 1024 * 1024

    public init(data: Data) throws {
        guard data.count >= 22, data.count <= Self.maximumSize else { throw BookError.invalid("The book is empty or exceeds the 256 MB import limit.") }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if data.u32(i) == 0x06054b50, i + 22 + Int(data.u16(i + 20)) == data.count { end = i; break }
        }
        guard let end, data.u16(end + 4) == 0, data.u16(end + 6) == 0,
              data.u16(end + 8) == data.u16(end + 10) else { throw BookError.invalid("The EPUB has an invalid or multipart ZIP directory.") }
        let count = Int(data.u16(end + 10))
        let directorySize = Int(data.u32(end + 12))
        var cursor = Int(data.u32(end + 16))
        guard count > 0, count <= 10_000, cursor + directorySize == end else { throw BookError.invalid("Unsupported EPUB archive directory.") }
        var result: [Entry] = [], seen = Set<String>(), total = 0, compressedTotal = 0
        var extents: [Range<Int>] = []
        for _ in 0..<count {
            guard cursor + 46 <= end, data.u32(cursor) == 0x02014b50 else { throw BookError.invalid("Damaged EPUB resource directory.") }
            let flags = data.u16(cursor + 8), method = data.u16(cursor + 10)
            let compressedSize = Int(data.u32(cursor + 20)), size = Int(data.u32(cursor + 24))
            let nameSize = Int(data.u16(cursor + 28)), extraSize = Int(data.u16(cursor + 30)), commentSize = Int(data.u16(cursor + 32))
            let local = Int(data.u32(cursor + 42))
            guard cursor + 46 + nameSize + extraSize + commentSize <= end,
                  flags & 1 == 0, [0, 8].contains(method), size <= 64 * 1024 * 1024,
                  local + 30 <= data.count, data.u32(local) == 0x04034b50 else {
                throw BookError.unsupported("This EPUB uses unsupported compression, encryption, or an oversized resource.")
            }
            let rawName = data.subdata(in: cursor + 46..<cursor + 46 + nameSize)
            guard let name = String(data: rawName, encoding: .utf8), Self.isSafePath(name),
                  seen.insert(name.precomposedStringWithCanonicalMapping).inserted,
                  (data.u32(cursor + 38) >> 16) & 0xF000 != 0xA000 else {
                throw BookError.invalid("The EPUB contains an unsafe or duplicate resource path.")
            }
            let start = local + 30 + Int(data.u16(local + 26)) + Int(data.u16(local + 28))
            guard start + compressedSize <= Int(data.u32(end + 16)),
                  data.u16(local + 8) == method, data.u16(local + 6) & 1 == 0,
                  local + 30 + Int(data.u16(local + 26)) <= data.count,
                  data.subdata(in: local + 30..<local + 30 + Int(data.u16(local + 26))) == rawName else {
                throw BookError.invalid("The EPUB contains inconsistent resource headers.")
            }
            total += size
            compressedTotal += compressedSize
            let extent = local..<start + compressedSize
            guard total <= Self.maximumSize, compressedTotal <= Self.maximumSize,
                  method != 0 || size == compressedSize, !extents.contains(where: { $0.overlaps(extent) }) else {
                throw BookError.invalid("The EPUB contains overlapping resources or exceeds the safety limit.")
            }
            extents.append(extent)
            if !name.hasSuffix("/") {
                result.append(Entry(name: name, method: method, crc: data.u32(cursor + 16), size: size, compressed: data.subdata(in: start..<start + compressedSize)))
            }
            cursor += 46 + nameSize + extraSize + commentSize
        }
        guard cursor == end else { throw BookError.invalid("The EPUB directory length is inconsistent.") }
        entries = result
    }

    public static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") && !path.contains("\0") &&
        !path.split(separator: "/", omittingEmptySubsequences: false).dropLast(path.hasSuffix("/") ? 1 : 0).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }

    public func data(named name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw BookError.invalid("Missing book resource: \(name)") }
        let result = try entry.method == 0 ? entry.compressed : Self.inflate(entry.compressed, size: entry.size)
        guard result.count == entry.size, Self.checksum(result) == entry.crc else { throw BookError.invalid("A book resource failed its integrity check: \(name)") }
        return result
    }

    public func writing(replacements: [String: Data]) throws -> Data {
        var ordered = entries.filter { $0.name != "mimetype" }
        ordered.insert(Entry(name: "mimetype", method: 0, crc: 0, size: 0, compressed: Data()), at: 0)
        for key in replacements.keys.sorted() where !ordered.contains(where: { $0.name == key }) {
            guard Self.isSafePath(key) else { throw BookError.invalid("Unsafe output resource path.") }
            ordered.append(Entry(name: key, method: 0, crc: 0, size: 0, compressed: Data()))
        }
        var output = Data(), directory = Data()
        for entry in ordered {
            let content: Data? = entry.name == "mimetype" ? Data("application/epub+zip".utf8) : replacements[entry.name]
            let method: UInt16 = entry.name == "mimetype" ? 0 : (content == nil ? entry.method : 8)
            let raw = try content.map { method == 0 ? $0 : try Self.deflate($0) } ?? entry.compressed
            let size = content?.count ?? entry.size
            let crc = content.map(Self.checksum) ?? entry.crc
            let name = Data(entry.name.utf8), offset = output.count
            output.le32(0x04034b50); output.le16(20); output.le16(0x800); output.le16(method)
            output.le16(0); output.le16(33); output.le32(crc); output.le32(UInt32(raw.count)); output.le32(UInt32(size))
            output.le16(UInt16(name.count)); output.le16(0); output.append(name); output.append(raw)
            directory.le32(0x02014b50); directory.le16(20); directory.le16(20); directory.le16(0x800); directory.le16(method)
            directory.le16(0); directory.le16(33); directory.le32(crc); directory.le32(UInt32(raw.count)); directory.le32(UInt32(size))
            directory.le16(UInt16(name.count)); directory.le16(0); directory.le16(0); directory.le16(0); directory.le16(0); directory.le32(0); directory.le32(UInt32(offset)); directory.append(name)
        }
        let offset = output.count
        output.append(directory); output.le32(0x06054b50); output.le16(0); output.le16(0)
        output.le16(UInt16(ordered.count)); output.le16(UInt16(ordered.count)); output.le32(UInt32(directory.count)); output.le32(UInt32(offset)); output.le16(0)
        guard output.count <= Self.maximumSize else { throw BookError.invalid("The prepared book exceeds the size limit.") }
        return output
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }
    private static func inflate(_ data: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw BookError.invalid("Cannot initialize decompression.") }
        defer { inflateEnd(&stream) }
        var result = Data(count: max(1, size))
        let status = result.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(1, size))
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == data.count else { throw BookError.invalid("The EPUB contains invalid compressed data.") }
        result.count = size
        return result
    }
    private static func deflate(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw BookError.invalid("Cannot initialize compression.") }
        defer { deflateEnd(&stream) }
        let capacity = Int(compressBound(uLong(data.count))) + 32
        var result = Data(count: capacity)
        let status = result.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(capacity)
                return CZlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw BookError.invalid("Could not compress book resource.") }
        result.count = Int(stream.total_out)
        return result
    }
}

extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    func be16(_ offset: Int) -> UInt16 { UInt16(self[offset]) << 8 | UInt16(self[offset + 1]) }
    func be32(_ offset: Int) -> UInt32 { UInt32(be16(offset)) << 16 | UInt32(be16(offset + 2)) }
    mutating func le16(_ n: UInt16) { append(UInt8(truncatingIfNeeded: n)); append(UInt8(truncatingIfNeeded: n >> 8)) }
    mutating func le32(_ n: UInt32) { le16(UInt16(truncatingIfNeeded: n)); le16(UInt16(truncatingIfNeeded: n >> 16)) }
}
