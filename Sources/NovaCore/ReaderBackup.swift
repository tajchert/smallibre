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
        try validateRoot()
        let data = try await library.preparedData(for: sourceID)
        let id = UUID(), directory = localRoot.appendingPathComponent("reader-backups/\(id.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("prepared-book")
        try data.write(to: backup, options: .atomic)
        let handle = try FileHandle(forWritingTo: backup); try handle.synchronize(); try handle.close()
        var receipt = ReaderReceipt(id: id, operation: "send", source: root.path, sourceHash: Self.digest(data), backup: backup, date: Date(), state: "inProgress", detail: "If interrupted, refresh the reader and compare file hashes before retrying. Hidden .nova temporary files may remain.")
        try receipt.save()
        do {
            try validateRoot()
            // Export uses a unique temporary file, readback verification and a no-overwrite move.
            let books = try await library.books()
            guard let match = books.first(where: { candidate in candidate.id == sourceID }) else { throw BookError.invalid("Book no longer in library") }
            let result = try await library.export(match.id, to: root)
            receipt.state = "completed"; receipt.detail = result.path; try receipt.save(); return result
        } catch { receipt.state = "needsReview"; receipt.detail = error.localizedDescription; try? receipt.save(); throw error }
    }
    public func updateMetadata(_ book: ReaderBook, metadata: BookMetadata, localRoot: URL) throws -> URL {
        let original = try verified(book)
        let output = try MOBIMetadataEditor.prepare(original, metadata: metadata)
        var receipt = try backup(book, localRoot: localRoot, operation: "metadata")
        let target = try location(book.relativePath)
        let staged = target.deletingLastPathComponent().appendingPathComponent(".nova-\(receipt.id.uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staged) }
        receipt.state = "inProgress"; receipt.detail = "Temporary device file: \(staged.lastPathComponent)"; try receipt.save()
        do {
            try output.write(to: staged, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: staged); try handle.synchronize(); try handle.close()
            guard Self.digest(try Data(contentsOf: staged)) == Self.digest(output) else { throw BookError.invalid("Prepared metadata file failed verification.") }
            _ = try verified(book)
            guard rename(staged.path, target.path) == 0 else { throw BookError.invalid("Could not replace device book. Backup retained.") }
            guard Self.digest(try Data(contentsOf: target)) == Self.digest(output) else { throw BookError.invalid("Device readback failed. Restore from backup.") }
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
