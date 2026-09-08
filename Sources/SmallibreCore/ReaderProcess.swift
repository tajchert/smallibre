import Foundation
import Darwin

private actor ReaderProcessGate {
    static let shared = ReaderProcessGate()
    private var current: Process?
    func start(_ process: Process) throws {
        guard current?.isRunning != true else { throw BookError.invalid("The previous reader operation is still stopping. Wait or reconnect before starting another operation.") }
        try process.run(); current = process
    }
}

public enum ReaderProcess {
    public static func run(executable: URL, arguments: [String], timeout: Double = 30) async throws -> Data {
        try Task.checkCancellation()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let output = try FileHandle(forWritingTo: file)
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? output.close(); try? FileManager.default.removeItem(at: file)
        }
        try await ReaderProcessGate.shared.start(process)
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw BookError.invalid("Reader operation timed out. Reconnect and refresh. Check operation history before retrying a write.") }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw BookError.invalid("Reader helper stopped unexpectedly. Refresh and check operation history before retrying.") }
        try output.close()
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 32 * 1024 * 1024 else { throw BookError.invalid("Reader response exceeded its size limit.") }
        return try Data(contentsOf: file)
    }
}

public struct ReaderRequest: Codable, Sendable {
    public var action: String
    public var root: URL
    public var connection: UUID
    public var rootIdentity: String?
    public var book: ReaderBook?
    public var localRoot: URL
    public var metadata: BookMetadata?
    public var libraryBookID: UUID?
    public var fullScan: Bool
    public init(action: String, root: URL, connection: UUID, rootIdentity: String?, book: ReaderBook? = nil, localRoot: URL, metadata: BookMetadata? = nil, fullScan: Bool = false, libraryBookID: UUID? = nil) {
        self.action = action; self.root = root; self.connection = connection; self.rootIdentity = rootIdentity
        self.libraryBookID = libraryBookID; self.book = book; self.localRoot = localRoot; self.metadata = metadata; self.fullScan = fullScan
    }
}
public struct ReaderResponse: Codable, Sendable {
    public var books: [ReaderBook]?
    public var rootIdentity: String?
    public var imported: LibraryBook?
    public var file: URL?
    public var error: String?
    public init(books: [ReaderBook]? = nil, rootIdentity: String? = nil, imported: LibraryBook? = nil, file: URL? = nil, error: String? = nil) {
        self.books = books; self.rootIdentity = rootIdentity; self.imported = imported; self.file = file; self.error = error
    }
}
public enum ReaderClient {
    public static func perform(_ request: ReaderRequest, executable: URL, timeout: Double = 30) async throws -> ReaderResponse {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try JSONEncoder().encode(request).write(to: path, options: .atomic)
        let data = try await ReaderProcess.run(executable: executable, arguments: [path.path], timeout: timeout)
        let response = try JSONDecoder().decode(ReaderResponse.self, from: data)
        if let error = response.error { throw BookError.invalid(error) }
        return response
    }
}
