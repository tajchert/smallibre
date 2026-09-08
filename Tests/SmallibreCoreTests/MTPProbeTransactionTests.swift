import XCTest
@testable import SmallibreCore

final class MTPProbeTransactionTests: XCTestCase {
    private final class Wire {
        var sent: [UInt16] = []
        var replies: [Data]
        init(_ replies: [Data]) { self.replies = replies }
        lazy var session = MTPProbeTransactions(send: { [unowned self] in self.sent.append($0.mtp16(6)) }, receive: { [unowned self] id in
            guard !self.replies.isEmpty else { throw MTPProbeError.invalid("Disconnected") }
            return try MTPPacket(self.replies.removeFirst(), transaction: id)
        })
    }
    private func packet(_ kind: UInt16 = 3, code: UInt16 = 0x2001, id: UInt32, payload: Data = Data()) -> Data {
        var data = Data(); data.mtpAppend(UInt32(12 + payload.count)); data.mtpAppend(kind)
        data.mtpAppend(code); data.mtpAppend(id); data.append(payload); return data
    }
    func testCompletedHandleResponseThenLocalLimitFailureClosesSession() throws {
        var handles = Data(); handles.mtpAppend(UInt32(1001))
        for id in 1...1001 { handles.mtpAppend(UInt32(id)) }
        let wire = Wire([packet(id: 0), packet(2, code: 0x1007, id: 1, payload: handles), packet(id: 1), packet(id: 2)])
        _ = try wire.session.exchange(.openSession, parameters: [1], expectsData: false)
        let data = try wire.session.exchange(.objectHandles, parameters: [1, 0, 0], expectsData: true)
        XCTAssertThrowsError(try MTPPacket.identifiers(data, maximum: 1000))
        XCTAssertTrue(wire.session.closeAfterFailure())
        XCTAssertFalse(wire.session.sessionOpen)
        XCTAssertEqual(wire.sent, [0x1002, 0x1007, 0x1003])
    }
    func testCompletedObjectInfoThenUnsafeFilenameClosesSession() throws {
        var info = Data(repeating: 0, count: 52); info.append(3)
        info.mtpAppend(UInt16(46)); info.mtpAppend(UInt16(46)); info.mtpAppend(UInt16(0))
        let wire = Wire([packet(id: 0), packet(2, code: 0x1008, id: 1, payload: info), packet(id: 1), packet(id: 2)])
        _ = try wire.session.exchange(.openSession, parameters: [1], expectsData: false)
        let data = try wire.session.exchange(.objectInfo, parameters: [1], expectsData: true)
        XCTAssertThrowsError(try MTPPacket.filename(data))
        XCTAssertTrue(wire.session.closeAfterFailure())
        XCTAssertEqual(wire.sent, [0x1002, 0x1008, 0x1003])
    }
    func testMissingOrFailedResponseNeverSendsCloseOrReplays() throws {
        for replies in [[packet(id: 0)], [packet(id: 0), packet(code: 0x2019, id: 1)], [packet(id: 0), packet(id: 99)]] {
            let wire = Wire(replies)
            _ = try wire.session.exchange(.openSession, parameters: [1], expectsData: false)
            XCTAssertThrowsError(try wire.session.exchange(.storageIDs, expectsData: true))
            XCTAssertFalse(wire.session.synchronized)
            XCTAssertFalse(wire.session.closeAfterFailure())
            XCTAssertThrowsError(try wire.session.exchange(.closeSession, expectsData: false))
            XCTAssertEqual(wire.sent, [0x1002, 0x1004])
        }
    }
    func testFailedCloseRemainsUnconfirmedWithoutSecondAttempt() throws {
        let wire = Wire([packet(id: 0)])
        _ = try wire.session.exchange(.openSession, parameters: [1], expectsData: false)
        XCTAssertFalse(wire.session.closeAfterFailure())
        XCTAssertFalse(wire.session.closeAfterFailure())
        XCTAssertTrue(wire.session.sessionOpen)
        XCTAssertEqual(wire.sent, [0x1002, 0x1003])
    }
}
