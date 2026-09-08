import Foundation
import Darwin

extension LibraryStore {
    /// Capture preparation inputs together on the library actor, then convert away from UI isolation.
    public func prepareKindleArtifact(for id: UUID) async throws -> PreparedBookArtifact {
        guard let book = try books().first(where: { $0.id == id }), book.metadata.format == "EPUB" else {
            throw BookError.unsupported("Kindle conversion requires an EPUB in your library.")
        }
        let input = try preparedData(for: id)
        struct Settings: Encodable { let metadata: BookMetadata; let typography: TypographySettings }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let provenance = PreparedBookProvenance(sourceLibraryID: id,
            sourceOriginalSHA256: try SHA256Digest(book.hash), preparedInputSHA256: .digest(input),
            settingsSHA256: .digest(try encoder.encode(Settings(metadata: book.metadata, typography: book.typography))),
            converterVersion: AZW3Converter.version, profile: AZW3Converter.profile)
        let key = SHA256Digest.digest(try encoder.encode(provenance)).value
        // Deterministic UUID permits direct cache lookup without an unbounded directory scan.
        let hex = Array(key.prefix(32))
        let identifier = UUID(uuidString: String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32]))!
        let parent = root.appendingPathComponent("converted", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try PreparedBookArtifact.requireDirectory(parent)
        let folder = parent.appendingPathComponent(identifier.uuidString, isDirectory: true)
        if let cached = try cachedKindleArtifact(in: folder, provenance: provenance) { return cached }
        let conversion = Task.detached(priority: .userInitiated) { try await KindleConversionWorker.shared.convert(input) }
        let result = try await withTaskCancellationHandler(operation: { try await conversion.value }, onCancel: { conversion.cancel() })
        try Task.checkCancellation()
        try AZW3Converter.validate(result.data)
        // Another preparation can finish while this actor awaits conversion.
        if let cached = try cachedKindleArtifact(in: folder, provenance: provenance) { return cached }
        let stage = parent.appendingPathComponent(".preparing-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        let bytesURL = stage.appendingPathComponent("book.azw3")
        try result.data.write(to: bytesURL, options: .withoutOverwriting)
        try Self.synchronizeArtifactFile(bytesURL)
        var title = Self.safeFilename(book.metadata.title)
        while title.utf8.count > 220 { title.removeLast() }
        let artifact = try PreparedBookArtifact(id: identifier, provenance: provenance, outputFormat: .azw3,
            suggestedFilename: title + ".azw3", localURL: folder.appendingPathComponent("book.azw3"),
            byteCount: result.data.count, outputSHA256: .digest(result.data), warnings: result.warnings)
        _ = try PreparedBookArtifact.readVerified(bytesURL, byteCount: artifact.byteCount, sha256: artifact.outputSHA256)
        let manifest = stage.appendingPathComponent("artifact.json")
        try encoder.encode(artifact).write(to: manifest, options: .withoutOverwriting)
        try Self.synchronizeArtifactFile(manifest)
        try Task.checkCancellation()
        // Publish both files together; never overwrite an existing artifact directory.
        do { try FileManager.default.moveItem(at: stage, to: folder) }
        catch {
            if let cached = try cachedKindleArtifact(in: folder, provenance: provenance) { return cached }
            throw error
        }
        try artifact.requireStored(in: root)
        return artifact
    }

    public func exportKindleArtifact(_ artifact: PreparedBookArtifact, to folder: URL) throws -> URL {
        try artifact.requireStored(in: root)
        let data = try artifact.verifiedData()
        try AZW3Converter.validate(data)
        return try Self.exportData(data, title: (artifact.suggestedFilename as NSString).deletingPathExtension, format: "azw3", to: folder)
    }

    private func cachedKindleArtifact(in folder: URL, provenance: PreparedBookProvenance) throws -> PreparedBookArtifact? {
        var info = stat()
        guard lstat(folder.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw BookError.invalid("Converted file storage is unavailable.")
        }
        try PreparedBookArtifact.requireDirectory(folder)
        let artifact = try PreparedBookArtifact.readManifest(folder.appendingPathComponent("artifact.json"))
        guard artifact.provenance == provenance else { throw BookError.invalid("Converted file provenance does not match. Existing files were preserved.") }
        try artifact.requireStored(in: root)
        try AZW3Converter.validate(artifact.verifiedData())
        return artifact
    }

    private static func synchronizeArtifactFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.synchronize()
    }
}

extension PreparedBookArtifact {
    /// Ensure the exact reviewed manifest is published in this library, not an arbitrary supplied URL.
    public func requireStored(in libraryRoot: URL) throws {
        let converted = libraryRoot.standardizedFileURL.appendingPathComponent("converted", isDirectory: true)
        let folder = converted.appendingPathComponent(id.uuidString, isDirectory: true)
        guard outputFormat == .azw3, localURL.standardizedFileURL == folder.appendingPathComponent("book.azw3") else {
            throw BookError.invalid("Prepared file is outside this library’s converted storage.")
        }
        try Self.requireDirectory(converted); try Self.requireDirectory(folder)
        guard try Self.readManifest(folder.appendingPathComponent("artifact.json")) == self else {
            throw BookError.invalid("Prepared file manifest changed. Review the conversion again.")
        }
        _ = try verifiedData()
    }

    static func requireDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw BookError.invalid("Converted storage folder is missing or is a symbolic link.")
        }
    }

    static func readManifest(_ url: URL) throws -> Self {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw BookError.invalid("Converted file manifest is unavailable.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= 1024 * 1024 else { throw BookError.invalid("Invalid converted file manifest.") }
        let bytes = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard bytes.count == info.st_size else { throw BookError.invalid("Converted file manifest changed while reading.") }
        return try JSONDecoder().decode(Self.self, from: bytes)
    }
}

/// Serialize CPU-intensive conversions even across separately opened library actors.
private actor KindleConversionWorker {
    static let shared = KindleConversionWorker()
    func convert(_ input: Data) throws -> AZW3Converter.Result {
        try Task.checkCancellation()
        return try AZW3Converter.convert(input)
    }
}
