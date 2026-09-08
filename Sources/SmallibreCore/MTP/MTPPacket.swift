import Foundation

/// Strict, bounded PTP/MTP USB containers. Only read-only operations are representable.
enum MTPReadOperation: UInt16 {
    case openSession = 0x1002, closeSession = 0x1003, storageIDs = 0x1004
    case objectHandles = 0x1007, objectInfo = 0x1008
}

enum MTPProbeError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct MTPPacket {
    static let maximumLength = 1_048_576
    let kind: UInt16
    let code: UInt16
    let transaction: UInt32
    let payload: Data

    static func command(_ operation: MTPReadOperation, transaction: UInt32, parameters: [UInt32]) throws -> Data {
        guard parameters.count <= 5 else { throw MTPProbeError.invalid("Too many command parameters") }
        var result = Data()
        result.mtpAppend(UInt32(12 + parameters.count * 4))
        result.mtpAppend(UInt16(1)); result.mtpAppend(operation.rawValue); result.mtpAppend(transaction)
        parameters.forEach { result.mtpAppend($0) }
        return result
    }

    init(_ bytes: Data, transaction: UInt32) throws {
        guard bytes.count >= 12, bytes.count <= Self.maximumLength,
              Int(bytes.mtp32(0)) == bytes.count else { throw MTPProbeError.invalid("Invalid container length") }
        kind = bytes.mtp16(4); code = bytes.mtp16(6); self.transaction = bytes.mtp32(8)
        guard self.transaction == transaction, kind == 2 || kind == 3 else {
            throw MTPProbeError.invalid("Unexpected transaction or container type")
        }
        payload = bytes.subdata(in: 12..<bytes.count)
        if kind == 3 && (payload.count > 20 || payload.count % 4 != 0) {
            throw MTPProbeError.invalid("Malformed response parameters")
        }
    }

    static func identifiers(_ data: Data, maximum: Int) throws -> [UInt32] {
        guard data.count >= 4 else { throw MTPProbeError.invalid("Truncated identifier array") }
        let count = Int(data.mtp32(0))
        guard count <= maximum, count == (data.count - 4) / 4, data.count == 4 + count * 4 else {
            throw MTPProbeError.invalid("Invalid or excessive identifier count")
        }
        let ids = (0..<count).map { data.mtp32(4 + $0 * 4) }
        guard Set(ids).count == ids.count, !ids.contains(0), !ids.contains(UInt32.max) else {
            throw MTPProbeError.invalid("Invalid or duplicate identifier")
        }
        return ids
    }

    static func filename(_ data: Data) throws -> String {
        // ObjectInfo fixed fields occupy 52 bytes, followed by counted UTF-16 filename.
        guard data.count >= 53 else { throw MTPProbeError.invalid("Truncated object info") }
        let count = Int(data[52])
        guard count > 0, data.count >= 53 + count * 2, data.mtp16(53 + (count - 1) * 2) == 0 else {
            throw MTPProbeError.invalid("Invalid object filename")
        }
        let units = (0..<(count - 1)).map { data.mtp16(53 + $0 * 2) }
        let name = String(decoding: units, as: UTF16.self)
        guard !name.isEmpty, !name.contains("\0"), !name.contains("/"), !name.contains("\\"), name != ".", name != "..",
              Array(name.utf16) == units else { throw MTPProbeError.invalid("Unsafe or malformed object filename") }
        return name
    }
}

extension Data {
    func mtp16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func mtp32(_ offset: Int) -> UInt32 { UInt32(mtp16(offset)) | UInt32(mtp16(offset + 2)) << 16 }
    mutating func mtpAppend<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
