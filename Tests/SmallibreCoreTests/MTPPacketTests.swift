import XCTest
@testable import SmallibreCore

final class MTPPacketTests: XCTestCase {
    func testCommandEncodingAndParameterBound() throws {
        XCTAssertEqual(try MTPPacket.command(.openSession, transaction: 0, parameters: [1]), Data([16,0,0,0,1,0,2,16,0,0,0,0,1,0,0,0]))
        XCTAssertThrowsError(try MTPPacket.command(.storageIDs, transaction: 1, parameters: Array(repeating: 0, count: 6)))
    }
    func testMalformedContainersAndTransactions() throws {
        let response = Data([12,0,0,0,3,0,1,32,7,0,0,0])
        XCTAssertEqual(try MTPPacket(response, transaction: 7).code, 0x2001)
        XCTAssertThrowsError(try MTPPacket(response, transaction: 8))
        for length in 0..<12 { XCTAssertThrowsError(try MTPPacket(response.prefix(length), transaction: 7)) }
        XCTAssertThrowsError(try MTPPacket(response + Data([0]), transaction: 7))
        var huge = Data(repeating: 0, count: MTPPacket.maximumLength + 1)
        huge.replaceSubrange(0..<4, with: [1,0,16,0])
        XCTAssertThrowsError(try MTPPacket(huge, transaction: 0))
    }
    func testRejectsInvalidResponseShapeAndContainerType() throws {
        var response = Data([13,0,0,0,3,0,1,32,0,0,0,0,0])
        XCTAssertThrowsError(try MTPPacket(response, transaction: 0))
        response = Data([12,0,0,0,4,0,1,32,0,0,0,0])
        XCTAssertThrowsError(try MTPPacket(response, transaction: 0))
        response = Data([36,0,0,0,3,0,1,32,0,0,0,0]) + Data(repeating: 0, count: 24)
        XCTAssertThrowsError(try MTPPacket(response, transaction: 0))
    }
    func testIdentifierBoundsTruncationDuplicatesAndReservedIDs() throws {
        XCTAssertEqual(try MTPPacket.identifiers(Data([1,0,0,0,42,0,0,0]), maximum: 1), [42])
        for data in [Data([255,255,255,255]), Data([1,0,0,0]), Data([1,0,0,0,0,0,0,0]), Data([2,0,0,0,1,0,0,0,1,0,0,0])] {
            XCTAssertThrowsError(try MTPPacket.identifiers(data, maximum: 1000))
        }
        XCTAssertThrowsError(try MTPPacket.identifiers(Data([1,0,0,0,42,0,0,0]), maximum: 0))
    }
    func testFilenameRejectsTraversalAndTruncation() throws {
        func info(_ name: String) -> Data {
            var d = Data(repeating: 0, count: 52); d.append(UInt8(name.utf16.count + 1))
            for unit in name.utf16 { d.mtpAppend(unit) }; d.mtpAppend(UInt16(0)); return d
        }
        XCTAssertEqual(try MTPPacket.filename(info("book.azw3")), "book.azw3")
        for name in ["..", "a/b", "a\\b", ""] { XCTAssertThrowsError(try MTPPacket.filename(info(name))) }
        XCTAssertThrowsError(try MTPPacket.filename(info("book").dropLast()))
    }
}
