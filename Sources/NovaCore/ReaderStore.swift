import Foundation
import CryptoKit
import Darwin

public struct ReaderBook: Identifiable, Sendable {
    public var id: String { relativePath }
    let connection: UUID
    public let relativePath: String
    public let metadata: BookMetadata?
    public let hash: String
    public let byteCount: Int
    public let issue: String?
    public var title: String { metadata?.title ?? URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent }
}

/// A mounted reader's documents directory. No device databases or sidecars are modified.
public actor ReaderStore {
    public let root: URL
    private let connection = UUID()
    private let rootIdentity: String?
    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.rootIdentity = try? Self.identity(self.root)
    }
    private static func identity(_ url: URL) throws -> String {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw BookError.invalid("Reader folder is unavailable.") }
        return "\(info.st_dev):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
    }

    public func scan() throws -> [ReaderBook] {
        try validateRoot()
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { throw BookError.invalid("Could not read the reader folder.") }
        var books: [ReaderBook] = []
        for case let enumeratedURL as URL in files {
            let url = enumeratedURL.standardizedFileURL
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { files.skipDescendants(); continue }
            guard values?.isRegularFile == true, ["epub", "mobi", "azw3", "azw", "prc", "kfx", "pdf"].contains(url.pathExtension.lowercased()) else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let bytes: Data
            do { bytes = try read(relative) }
            catch {
                try validateRoot()
                books.append(ReaderBook(connection: connection, relativePath: relative, metadata: nil, hash: "", byteCount: 0, issue: error.localizedDescription))
                continue
            }
            let metadata: BookMetadata?, issue: String?
            do { metadata = try BookInspector.inspect(url); issue = nil }
            catch { metadata = nil; issue = error.localizedDescription }
            books.append(ReaderBook(connection: connection, relativePath: relative, metadata: metadata, hash: Self.digest(bytes), byteCount: bytes.count, issue: issue))
        }
        return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    public func download(_ book: ReaderBook, into library: LibraryStore) async throws -> ImportResult {
        let data = try verified(book)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(URL(fileURLWithPath: book.relativePath).pathExtension)
        defer { try? FileManager.default.removeItem(at: temp) }
        try data.write(to: temp, options: .atomic)
        return try await library.importBook(from: temp)
    }
    public func delete(_ book: ReaderBook) throws { try delete(book, beforeUnlink: {}) }
    func delete(_ book: ReaderBook, beforeUnlink: @Sendable () throws -> Void) throws {
        guard book.connection == connection else { throw BookError.invalid("Device selection is stale. Refresh first.") }
        _ = try location(book.relativePath)
        let components = book.relativePath.split(separator: "/").map(String.init)
        var directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw BookError.invalid("Reader disconnected.") }
        defer { close(directory) }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw BookError.invalid("Reader path changed. Refresh first.") }
            close(directory); directory = next
        }
        try validateRoot()
        guard let name = components.last else { throw BookError.invalid("Invalid device file.") }
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw BookError.invalid("Device file unavailable.") }
        defer { close(file) }
        var initial = stat()
        guard fstat(file, &initial) == 0, (initial.st_mode & S_IFMT) == S_IFREG,
              initial.st_size <= ZIPArchive.maximumSize else { throw BookError.invalid("Device file changed.") }
        let bytes = try FileHandle(fileDescriptor: file, closeOnDealloc: false).readToEnd() ?? Data()
        guard Self.digest(bytes) == book.hash else { throw BookError.invalid("Device file changed. Refresh first.") }
        try beforeUnlink()
        try validateRoot()
        let parent = root.appendingPathComponent(book.relativePath).deletingLastPathComponent()
        var openedParent = stat(), currentParent = stat(), currentFile = stat()
        guard fstat(directory, &openedParent) == 0, lstat(parent.path, &currentParent) == 0,
              openedParent.st_dev == currentParent.st_dev, openedParent.st_ino == currentParent.st_ino,
              fstatat(directory, name, &currentFile, AT_SYMLINK_NOFOLLOW) == 0,
              currentFile.st_dev == initial.st_dev, currentFile.st_ino == initial.st_ino,
              currentFile.st_size == initial.st_size,
              currentFile.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
              currentFile.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec else {
            throw BookError.invalid("Device file changed. Refresh first.")
        }
        // Nonrecursive; identity checks narrow races but are not an atomic conditional unlink.
        guard unlinkat(directory, name, 0) == 0 else {
            throw BookError.invalid("Could not delete this device file. Refresh and try again.")
        }
    }
    private func verified(_ book: ReaderBook) throws -> Data {
        guard book.connection == connection else { throw BookError.invalid("Device selection is stale. Refresh first.") }
        let bytes = try read(book.relativePath)
        guard Self.digest(bytes) == book.hash else { throw BookError.invalid("This device file changed. Refresh the list before continuing.") }
        return bytes
    }
    private func validateRoot() throws {
        guard let rootIdentity, try Self.identity(root) == rootIdentity else { throw BookError.invalid("The connected reader changed. Choose its folder again.") }
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw BookError.invalid("Reader disconnected. Reconnect it and refresh.") }
        guard root.resolvingSymlinksInPath().path == root.path else { throw BookError.invalid("Reader folder must not be a symbolic link.") }
    }
    private func location(_ relative: String) throws -> URL {
        try validateRoot()
        guard ZIPArchive.isSafePath(relative) else { throw BookError.invalid("Unsafe reader path.") }
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.resolvingSymlinksInPath().path == url.path, url.path.hasPrefix(root.path + "/") else { throw BookError.invalid("Reader path leaves the selected folder.") }
        return url
    }
    private func read(_ relative: String) throws -> Data {
        let url = try location(relative)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= ZIPArchive.maximumSize else { throw BookError.invalid("Device file exceeds the supported size.") }
        return try Data(contentsOf: url)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
