import Foundation
import IOKit
import IOUSBHost

/// Experimental helper-only diagnostic. No upload/delete/reset/seize operations exist here.
public enum MTPReadOnlyProbe {
    public struct Result: Encodable {
        public let schemaVersion = 1
        public let status: String
        public let interfacesSeen: Int
        public let devices: [Device]
        public let limitation: String
    }
    public struct Device: Encodable {
        public let registryID: UInt64
        public let vendorID: Int
        public let productID: Int
        public var status: String
        public var storageIDs: [UInt32] = []
        public var objects: [Object] = []
    }
    public struct Object: Encodable {
        public let storageID: UInt32
        public let handle: UInt32
        public let parent: UInt32
        public let format: UInt16
        public let byteCount: UInt32
        public let filename: String
    }

    public static func run() throws -> Result {
        guard URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "SmallibreReaderHelper" else {
            throw MTPProbeError.invalid("USB probe is restricted to SmallibreReaderHelper")
        }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iterator)
        guard status == KERN_SUCCESS else { throw MTPProbeError.invalid("USB registry enumeration failed: \(status)") }
        defer { IOObjectRelease(iterator) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var devices: [Device] = []; var seen = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            seen += 1
            guard seen <= 256 else { throw MTPProbeError.invalid("USB interface limit exceeded") }
            func number(_ key: String) -> Int {
                (IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? NSNumber)?.intValue ?? -1
            }
            // Only Amazon still-image interfaces are probed; do not claim unrelated cameras or phones.
            guard number("idVendor") == 0x1949, number("bInterfaceClass") == 6, number("bInterfaceSubClass") == 1,
                  number("bInterfaceProtocol") == 1 else { continue }
            guard devices.count < 4, ContinuousClock.now < deadline else {
                throw MTPProbeError.invalid("Probe candidate/deadline limit exceeded")
            }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }
            var device = Device(registryID: registryID, vendorID: number("idVendor"), productID: number("idProduct"), status: "candidate")
            do {
                let session = try NativeSession(service, deadline: deadline)
                defer { session.interface.destroy() }
                _ = try session.exchange(.openSession, parameters: [1], expectsData: false)
                do {
                    device.storageIDs = try MTPPacket.identifiers(session.exchange(.storageIDs, expectsData: true), maximum: 16)
                    for storage in device.storageIDs {
                        let handles = try MTPPacket.identifiers(session.exchange(.objectHandles, parameters: [storage, 0, 0], expectsData: true), maximum: 1000 - device.objects.count)
                        for handle in handles {
                            let info = try session.exchange(.objectInfo, parameters: [handle], expectsData: true)
                            let name = try MTPPacket.filename(info)
                            guard info.mtp32(0) == storage else { throw MTPProbeError.invalid("Object storage changed") }
                            device.objects.append(Object(storageID: storage, handle: handle, parent: info.mtp32(38), format: info.mtp16(4), byteCount: info.mtp32(8), filename: name))
                        }
                    }
                    _ = try session.exchange(.closeSession, expectsData: false)
                    device.status = "readOnlyInventoryCompleted"
                } catch {
                    let closed = session.transactions.closeAfterFailure()
                    device.status = "\(closed ? "inventoryFailedSessionClosed" : "inventoryFailedRemoteSessionClosureUnconfirmed"): \(error.localizedDescription)"
                }
            } catch { device.status = "openOrSessionFailedRemoteSessionClosureUnconfirmed: \(error.localizedDescription)" }
            devices.append(device)
        }
        return Result(status: seen == 0 ? "noVisibleUSBInterfacesAccessUnverified" : devices.isEmpty ? "noStandardMTPCandidates" : "candidatesProbed", interfacesSeen: seen, devices: devices, limitation: "Experimental read-only probe; USB visibility, MTP compatibility and Kindle rendering require identified hardware certification. No mutation support. Empty enumeration does not establish that no device is connected.")
    }
}

private final class NativeSession {
    let interface: IOUSBHostInterface
    let input: IOUSBHostPipe
    let output: IOUSBHostPipe
    var buffered = Data()
    let deadline: ContinuousClock.Instant
    lazy var transactions = MTPProbeTransactions(
        send: { [unowned self] command in
            var transferred = 0
            try self.output.__sendIORequest(with: NSMutableData(data: command), bytesTransferred: &transferred, completionTimeout: 2)
            guard transferred == command.count else { throw MTPProbeError.invalid("Short command transfer") }
        },
        receive: { [unowned self] in try self.packet($0) },
        checkBudget: { [unowned self] in
            guard ContinuousClock.now < self.deadline else { throw MTPProbeError.invalid("Probe deadline exceeded") }
        })

    init(_ service: io_service_t, deadline: ContinuousClock.Instant) throws {
        self.deadline = deadline
        let host = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        do {
            var current: UnsafePointer<IOUSBDescriptorHeader>?
            var incoming: IOUSBHostPipe?; var outgoing: IOUSBHostPipe?
            var count = 0
            while let endpoint = IOUSBGetNextEndpointDescriptor(host.configurationDescriptor, host.interfaceDescriptor, current) {
                count += 1
                guard count <= 32 else { throw MTPProbeError.invalid("Excessive USB endpoints") }
                current = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
                if endpoint.pointee.bmAttributes & 3 == 2 {
                    let pipe = try host.copyPipe(withAddress: Int(endpoint.pointee.bEndpointAddress))
                    if endpoint.pointee.bEndpointAddress & 0x80 != 0 { incoming = pipe } else { outgoing = pipe }
                }
            }
            guard let incoming, let outgoing else { throw MTPProbeError.invalid("Missing bulk endpoint pair") }
            interface = host; input = incoming; output = outgoing
        } catch { host.destroy(); throw error }
    }

    func exchange(_ operation: MTPReadOperation, parameters: [UInt32] = [], expectsData: Bool) throws -> Data {
        try transactions.exchange(operation, parameters: parameters, expectsData: expectsData)
    }

    func packet(_ id: UInt32) throws -> MTPPacket {
        for _ in 0..<260 {
            if buffered.count >= 4 {
                let length = Int(buffered.mtp32(0))
                guard length >= 12, length <= MTPPacket.maximumLength else { throw MTPProbeError.invalid("Unbounded container") }
                if buffered.count >= length {
                    let bytes = Data(buffered.prefix(length)); buffered = Data(buffered.dropFirst(length))
                    return try MTPPacket(bytes, transaction: id)
                }
            }
            guard ContinuousClock.now < deadline else { throw MTPProbeError.invalid("Probe deadline exceeded") }
            let chunk = NSMutableData(length: 16_384)!
            var count = 0
            try input.__sendIORequest(with: chunk, bytesTransferred: &count, completionTimeout: 2)
            guard count >= 0, count <= chunk.length, buffered.count + count <= MTPPacket.maximumLength + 16_384 else {
                throw MTPProbeError.invalid("USB response exceeded bounds")
            }
            buffered.append((chunk as Data).prefix(count))
        }
        throw MTPProbeError.invalid("Excessive USB response fragments")
    }
}
