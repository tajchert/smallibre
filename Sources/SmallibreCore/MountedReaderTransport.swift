import Foundation
import Darwin

/// Helper-only mounted adapter. An interrupted upload remains in place for explicit review.
public actor MountedReaderTransport: ReaderTransport {
    public let destination: ReaderDestination
    public let capabilities: ReaderCapabilities = [.uploadNew, .fetch]
    private let root: URL
    private let identity: String
    private let beforeCreate: @Sendable () throws -> Void

    public init(destination: ReaderDestination) throws {
        try self.init(destination: destination, beforeCreate: {})
    }
    init(destination: ReaderDestination, beforeCreate: @escaping @Sendable () throws -> Void) throws {
        guard case let .mounted(root, identity) = destination.endpoint, root.isFileURL else {
            throw ReaderTransportError.unsupported
        }
        self.destination = destination; self.root = root; self.identity = identity; self.beforeCreate = beforeCreate
    }
    public func list() throws -> [ReaderTransportItem] { throw ReaderTransportError.unsupported }

    private func validate(_ directory: Int32) throws {
        var path = stat(), opened = stat()
        guard root.standardizedFileURL.path == root.path, root.resolvingSymlinksInPath().path == root.path,
              lstat(root.path, &path) == 0, fstat(directory, &opened) == 0,
              (path.st_mode & S_IFMT) == S_IFDIR, path.st_dev == opened.st_dev, path.st_ino == opened.st_ino,
              "\(path.st_dev):\(path.st_ino):\(path.st_birthtimespec.tv_sec):\(path.st_birthtimespec.tv_nsec)" == identity else {
            throw ReaderTransportError.staleSelection
        }
    }
    private func openRoot() throws -> Int32 {
        let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw ReaderTransportError.disconnected }
        do { try validate(directory); return directory } catch { close(directory); throw error }
    }

    public func uploadNew(_ bytes: Data, suggestedFilename: String, to destination: ReaderDestination) throws -> ReaderItemID {
        guard self.destination == destination else { throw ReaderTransportError.staleSelection }
        guard !bytes.isEmpty, bytes.count <= ZIPArchive.maximumSize,
              !suggestedFilename.isEmpty, !suggestedFilename.hasPrefix("."), suggestedFilename.utf8.count <= 240,
              !suggestedFilename.contains("/"), !suggestedFilename.contains("\\"), !suggestedFilename.contains(":"),
              !suggestedFilename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ReaderTransportError.invalidResponse
        }
        let directory = try openRoot(); defer { close(directory) }
        try beforeCreate()
        let ext = (suggestedFilename as NSString).pathExtension
        let stem = (suggestedFilename as NSString).deletingPathExtension
        for index in 0..<1000 {
            try Task.checkCancellation()
            try validate(directory)
            let name = index == 0 ? suggestedFilename : stem + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let file = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK, 0o600)
            if file < 0 {
                if errno == EEXIST { continue }
                throw ReaderTransportError.outcomeUnknown
            }
            let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
            defer { try? handle.close() }
            // Once creation succeeds, never unlink/replay even when writing or validation fails.
            try validate(directory)
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
            try Task.checkCancellation()
            try validate(directory)
            var opened = stat(), current = stat()
            guard fstat(file, &opened) == 0, fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  (current.st_mode & S_IFMT) == S_IFREG, current.st_ino == opened.st_ino,
                  current.st_dev == opened.st_dev, current.st_size == bytes.count else {
                throw ReaderTransportError.outcomeUnknown
            }
            return ReaderItemID(destination: destination, locator: .mounted(relativePath: name))
        }
        throw BookError.invalid("Too many reader filename collisions.")
    }

    public func fetch(_ item: ReaderItemID, to localURL: URL, maximumBytes: Int) throws {
        try item.requireCurrent(destination)
        guard case let .mounted(name) = item.locator, !name.contains("/"), localURL.isFileURL,
              maximumBytes > 0, maximumBytes <= ZIPArchive.maximumSize,
              !localURL.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw ReaderTransportError.invalidResponse }
        let directory = try openRoot(); defer { close(directory) }
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw ReaderTransportError.disconnected }
        let input = FileHandle(fileDescriptor: file, closeOnDealloc: true); defer { try? input.close() }
        var opened = stat()
        guard fstat(file, &opened) == 0, (opened.st_mode & S_IFMT) == S_IFREG,
              opened.st_size >= 0, opened.st_size <= maximumBytes else { throw ReaderTransportError.invalidResponse }
        let outputFD = open(localURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard outputFD >= 0 else { throw BookError.invalid("Could not create new readback file.") }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true); defer { try? output.close() }
        var count = 0
        while count <= maximumBytes {
            try Task.checkCancellation()
            let data = try input.read(upToCount: min(1024 * 1024, maximumBytes - count + 1)) ?? Data()
            if data.isEmpty { break }
            count += data.count
            guard count <= maximumBytes else { throw ReaderTransportError.invalidResponse }
            try output.write(contentsOf: data)
        }
        try output.synchronize()
        try validate(directory)
        var current = stat()
        guard fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_ino == opened.st_ino, current.st_dev == opened.st_dev,
              (current.st_mode & S_IFMT) == S_IFREG, current.st_size == count else {
            throw ReaderTransportError.outcomeUnknown
        }
    }
}
