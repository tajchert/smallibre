import Foundation

public enum LibraryLocation {
    // Legacy identifiers are required to find existing libraries and preserve receipt URLs.
    public static let legacyDirectory = "Calibre Nova"
    public static let legacyBundleIdentifier = "com.calibrenova.app"
    public static func prepare(in support: URL) throws -> URL { try prepare(in: support, afterMove: {}) }
    static func prepare(in support: URL, afterMove: () throws -> Void) throws -> URL {
        let manager = FileManager.default
        let target = support.appendingPathComponent("Smallibre", isDirectory: true)
        let legacy = support.appendingPathComponent(legacyDirectory, isDirectory: true)
        let marker = support.appendingPathComponent(".smallibre-library-migration")
        func finishAlias() throws {
            if manager.fileExists(atPath: legacy.path) {
                guard legacy.resolvingSymlinksInPath().standardizedFileURL == target.standardizedFileURL else {
                    throw BookError.invalid("Library migration found conflicting directories. Both copies have been preserved.")
                }
            } else { try manager.createSymbolicLink(at: legacy, withDestinationURL: target) }
            try manager.removeItem(at: marker)
        }
        // An earlier partial startup may have created only a scan cache at the new path.
        // Preserve that directory separately before moving a real existing library.
        if manager.fileExists(atPath: target.path),
           !manager.fileExists(atPath: target.appendingPathComponent("library.sqlite").path),
           manager.fileExists(atPath: legacy.appendingPathComponent("library.sqlite").path) {
            let preserved = support.appendingPathComponent("Smallibre-before-migration-" + UUID().uuidString)
            try manager.moveItem(at: target, to: preserved)
        }
        if manager.fileExists(atPath: target.path) {
            if manager.fileExists(atPath: marker.path) { try finishAlias() }
            return target
        }
        guard manager.fileExists(atPath: legacy.path) else { return target }
        let attributes = try legacy.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            throw BookError.invalid("The previous library is not a regular directory. Choose its actual directory with --library before migrating.")
        }
        if !manager.fileExists(atPath: marker.path) { try Data("1".utf8).write(to: marker, options: .withoutOverwriting) }
        try manager.moveItem(at: legacy, to: target)
        // A retry repairs the alias if the process stops after this move.
        try afterMove()
        try finishAlias()
        return target
    }
}
