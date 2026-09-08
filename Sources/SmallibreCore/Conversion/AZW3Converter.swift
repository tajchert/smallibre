import Foundation

/// Native, bounded reflowable EPUB to standalone KF8 conversion. No source file is mutated.
public enum AZW3Converter {
    public static let version = "1"
    public static let profile = "native-reflowable-kf8-v1"
    public struct Result: Sendable {
        public let data: Data
        public let warnings: [String]
    }
    public static func convert(_ input: Data) throws -> Result {
        try Task.checkCancellation()
        let output = try AZW3PrototypeWriter.convert(input, production: true)
        try validate(output)
        return Result(data: output, warnings: ["Native AZW3 conversion supports a bounded reflowable EPUB subset. Navigation is flattened. Kindle may render CSS differently; review the converted book before relying on it."])
    }

    /// Independent structural check of the emitted Palm database, text, indices and flow records.
    /// This validates our output profile, not arbitrary third-party AZW3 books.
    public static func validate(_ data: Data) throws {
        try AZW3Validator.validate(data)
    }
}
