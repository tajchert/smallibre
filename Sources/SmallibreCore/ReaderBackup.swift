import Foundation
import Darwin

public struct ReaderReceipt: Codable, Sendable, Identifiable {
    public let id: UUID
    public let operation: String
    public let source: String
    public let sourceHash: String
    public let backup: URL
    public let date: Date
    public var state: String
    public var detail: String?
    /// Absent in legacy mounted-reader receipts.
    public var transfer: ReaderTransferRecord? = nil
    public func save() throws {
        let url = backup.deletingLastPathComponent().appendingPathComponent("receipt.json")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }; try handle.synchronize()
    }
    public static func list(localRoot: URL) -> [ReaderReceipt] {
        let root = localRoot.appendingPathComponent("reader-backups")
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("receipt.json")) else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        }.sorted { $0.date > $1.date }
    }
}

extension ReaderStore {
    func backup(_ book: ReaderBook, localRoot: URL, operation: String) throws -> ReaderReceipt {
        let data = try verified(book)
        let id = UUID(), folder = localRoot.appendingPathComponent("reader-backups/\(id.uuidString)")
        guard !folder.standardizedFileURL.path.hasPrefix(root.path + "/") else { throw BookError.invalid("Backups must be saved on the Mac.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(URL(fileURLWithPath: book.relativePath).lastPathComponent)
        var receipt = ReaderReceipt(id: id, operation: operation, source: book.relativePath, sourceHash: book.hash, backup: target, date: Date(), state: "preparingBackup")
        try receipt.save()
        try data.write(to: target, options: .atomic)
        let handle = try FileHandle(forWritingTo: target); try handle.synchronize(); try handle.close()
        guard Self.digest(try Data(contentsOf: target)) == book.hash else { throw BookError.invalid("Backup verification failed. Device file was preserved.") }
        receipt.state = "backedUp"; try receipt.save()
        return receipt
    }
    public func backupAndDelete(_ book: ReaderBook, localRoot: URL) throws -> URL {
        var receipt = try backup(book, localRoot: localRoot, operation: "delete")
        receipt.state = "inProgress"; try receipt.save()
        do {
            try delete(book)
            receipt.state = "completed"; try receipt.save()
        } catch {
            receipt.state = "needsReview"; receipt.detail = error.localizedDescription; try? receipt.save(); throw error
        }
        return receipt.backup
    }
    public func send(_ sourceID: UUID, library: LibraryStore, localRoot: URL) async throws -> URL {
        try await send(sourceID, library: library, localRoot: localRoot, beforeExport: {})
    }
    func send(_ sourceID: UUID, library: LibraryStore, localRoot: URL, beforeExport: @Sendable () async throws -> Void) async throws -> URL {
        try validateRoot()
        let books = try await library.books()
        guard let match = books.first(where: { $0.id == sourceID }) else { throw BookError.invalid("Book no longer in library") }
        let data = try await library.preparedData(for: sourceID)
        let id = UUID(), directory = localRoot.appendingPathComponent("reader-backups/\(id.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("prepared-book." + match.metadata.format.lowercased())
        try data.write(to: backup, options: .atomic)
        let handle = try FileHandle(forWritingTo: backup); try handle.synchronize(); try handle.close()
        var receipt = ReaderReceipt(id: id, operation: "send", source: root.path, sourceHash: Self.digest(data), backup: backup, date: Date(), state: "inProgress", detail: "If interrupted, refresh the reader and compare file hashes before retrying. Hidden .smallibre temporary files may remain.")
        try receipt.save()
        do {
            try validateRoot()
            // Export uses a unique temporary file, readback verification and a no-overwrite move.
            try await beforeExport()
            let result = try LibraryStore.exportData(data, title: match.metadata.title, format: match.metadata.format, to: root)
            receipt.state = "completed"; receipt.detail = result.path; try receipt.save(); return result
        } catch { receipt.state = "needsReview"; receipt.detail = error.localizedDescription; try? receipt.save(); throw error }
    }
    public func updateMetadata(_ book: ReaderBook, metadata: BookMetadata, localRoot: URL) throws -> URL {
        try updateMetadata(book, metadata: metadata, localRoot: localRoot, beforeReplace: {})
    }
    func updateMetadata(_ book: ReaderBook, metadata: BookMetadata, localRoot: URL, beforeReplace: @Sendable () throws -> Void) throws -> URL {
        let original = try verified(book)
        let output = try MOBIMetadataEditor.prepare(original, metadata: metadata)
        var receipt = try backup(book, localRoot: localRoot, operation: "metadata")
        let target = try location(book.relativePath)
        let components = book.relativePath.split(separator: "/").map(String.init)
        var directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw BookError.invalid("Reader disconnected") }
        defer { close(directory) }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw BookError.invalid("Reader folder changed") }
            close(directory); directory = next
        }
        let name = components.last!, stage = ".smallibre-\(receipt.id.uuidString).tmp"
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw BookError.invalid("Device book unavailable") }
        defer { close(file) }
        var initial = stat()
        guard fstat(file, &initial) == 0, (initial.st_mode & S_IFMT) == S_IFREG,
              initial.st_size <= ZIPArchive.maximumSize else { throw BookError.invalid("Device book changed") }
        let bytes = try FileHandle(fileDescriptor: file, closeOnDealloc: false).readToEnd() ?? Data()
        guard Self.digest(bytes) == book.hash else { throw BookError.invalid("Device book changed") }
        let staged = openat(directory, stage, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard staged >= 0 else { throw BookError.invalid("Could not prepare device metadata file") }
        defer { close(staged); unlinkat(directory, stage, 0) }
        receipt.state = "inProgress"; receipt.detail = "Temporary device file: \(stage)"; try receipt.save()
        do {
            let handle = FileHandle(fileDescriptor: staged, closeOnDealloc: false)
            try handle.write(contentsOf: output); try handle.synchronize(); try handle.seek(toOffset: 0)
            guard Self.digest(try handle.readToEnd() ?? Data()) == Self.digest(output) else { throw BookError.invalid("Metadata preparation failed verification") }
            try beforeReplace()
            try validateRoot()
            var current = stat(), parent = stat(), opened = stat()
            guard fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  current.st_ino == initial.st_ino, current.st_dev == initial.st_dev,
                  current.st_size == initial.st_size,
                  current.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
                  current.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
                  lstat(target.deletingLastPathComponent().path, &parent) == 0, fstat(directory, &opened) == 0,
                  parent.st_ino == opened.st_ino, parent.st_dev == opened.st_dev else { throw BookError.invalid("Device path changed before metadata update") }
            guard renameat(directory, stage, directory, name) == 0 else { throw BookError.invalid("Could not update metadata. Backup retained") }
            let check = openat(directory, name, O_RDONLY | O_NOFOLLOW)
            guard check >= 0 else { throw BookError.invalid("Device readback failed") }
            defer { close(check) }
            guard Self.digest(try FileHandle(fileDescriptor: check, closeOnDealloc: false).readToEnd() ?? Data()) == Self.digest(output) else { throw BookError.invalid("Device readback failed. Restore backup") }
            receipt.state = "completed"; receipt.detail = "Metadata updated; original in backup"; try receipt.save()
        } catch { receipt.state = "needsReview"; receipt.detail = error.localizedDescription; try? receipt.save(); throw error }
        return receipt.backup
    }
    public func downloadCopy(_ book: ReaderBook, localRoot: URL) throws -> URL {
        var receipt = try backup(book, localRoot: localRoot, operation: "download")
        receipt.state = "completed"; try receipt.save()
        return receipt.backup
    }
}
