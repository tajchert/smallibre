import Foundation

/// Protocol state is independent of local dataset validation. Once a command is sent,
/// only its complete successful response restores synchronization.
final class MTPProbeTransactions {
    private let send: (Data) throws -> Void
    private let receive: (UInt32) throws -> MTPPacket
    private let checkBudget: () throws -> Void
    private var transaction: UInt32 = 0
    private(set) var synchronized = true
    private(set) var sessionOpen = false

    init(send: @escaping (Data) throws -> Void, receive: @escaping (UInt32) throws -> MTPPacket,
         checkBudget: @escaping () throws -> Void = {}) {
        self.send = send; self.receive = receive; self.checkBudget = checkBudget
    }

    func exchange(_ operation: MTPReadOperation, parameters: [UInt32] = [], expectsData: Bool) throws -> Data {
        guard synchronized else { throw MTPProbeError.invalid("MTP session synchronization is uncertain") }
        guard transaction < 2048 else { throw MTPProbeError.invalid("Probe transaction limit exceeded") }
        try checkBudget()
        let id = transaction
        let command = try MTPPacket.command(operation, transaction: id, parameters: parameters)
        transaction += 1
        synchronized = false
        try send(command)
        let first = try receive(id)
        var data = Data(); var response = first
        if first.kind == 2 {
            guard expectsData, first.code == operation.rawValue else { throw MTPProbeError.invalid("Unexpected data operation") }
            data = first.payload; response = try receive(id)
        } else if expectsData, first.code == 0x2001 { throw MTPProbeError.invalid("Missing data phase") }
        guard response.kind == 3, response.code == 0x2001 else {
            throw MTPProbeError.invalid("MTP response failure: \(String(response.code, radix: 16))")
        }
        synchronized = true
        if operation == .openSession { sessionOpen = true }
        if operation == .closeSession { sessionOpen = false }
        return data
    }

    /// A local validation failure after a successful exchange can still close cleanly.
    /// Failed/uncertain exchanges must never cause a second command on this session.
    func closeAfterFailure() -> Bool {
        guard sessionOpen, synchronized else { return false }
        do { _ = try exchange(.closeSession, expectsData: false); return true }
        catch { return false }
    }
}
