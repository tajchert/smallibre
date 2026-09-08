import Foundation

/// A deliberately small CSS fallback pass; it never opens font URLs.
enum KindleFallbackCSS {
    struct Result { let css: String; let warnings: [String] }

    static func normalize(_ css: String) throws -> Result {
        guard css.utf8.count <= 1024 * 1024 else { throw BookError.unsupported("CSS exceeds 1 MB.") }
        let bytes = Array(css.utf8)
        var cleaned: [UInt8] = [], quote: UInt8?, index = 0
        while index < bytes.count {
            if index % 4096 == 0 { try Task.checkCancellation() }
            let byte = bytes[index]
            guard byte != 92, byte != 60, byte != 62 else { throw unsupported() }
            if let active = quote {
                if byte == active { quote = nil }
                guard byte != 10, byte != 13 else { throw malformed() }
                cleaned.append(byte); index += 1
            } else if byte == 34 || byte == 39 {
                quote = byte; cleaned.append(byte); index += 1
            } else if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                index += 2
                while index + 1 < bytes.count && !(bytes[index] == 42 && bytes[index + 1] == 47) {
                    if index % 4096 == 0 { try Task.checkCancellation() }
                    index += 1
                }
                guard index + 1 < bytes.count else { throw malformed() }
                index += 2
            } else { cleaned.append(byte); index += 1 }
        }
        guard quote == nil else { throw malformed() }
        let source = String(decoding: cleaned, as: UTF8.self)
        let marks = try delimiters(source)
        var warnings: [String] = []
        func warn(_ message: String) { if !warnings.contains(message) { warnings.append(message) } }
        func declarations(_ text: String, page: Bool = false) throws -> String {
            let lower = text.lowercased()
            guard !["url", "@", "expression", "javascript", "behavior", "-moz-binding"].contains(where: lower.contains) else { throw unsupported() }
            let parts = try split(text, on: 59)
            return try parts.map { part in
                if part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return part }
                let colons = try delimiters(part).filter { $0.1 == 58 }
                guard let colon = colons.first else { throw malformed() }
                let raw = Array(part.utf8)
                let name = String(decoding: raw[..<colon.0], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = String(decoding: raw[(colon.0 + 1)...], as: UTF8.self)
                if page {
                    guard ["margin", "margin-top", "margin-right", "margin-bottom", "margin-left"].contains(name),
                          value.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^(?:0|[0-9]+(?:\.[0-9]+)?(?:px|pt|em|rem|%|in|cm|mm))(?:\s+(?:0|[0-9]+(?:\.[0-9]+)?(?:px|pt|em|rem|%|in|cm|mm))){0,3}$"#, options: [.regularExpression, .caseInsensitive]) != nil else {
                        throw BookError.unsupported("Unsupported @page content; only simple page margins can be replaced by Kindle reader settings.")
                    }
                    return ""
                }
                guard name != "font" else { throw BookError.unsupported("CSS font shorthand cannot be safely preserved by native AZW3 conversion; use separate font properties.") }
                guard name == "font-family" else { return part }
                var familyValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let important = familyValue.lowercased().hasSuffix("!important")
                if important { familyValue = String(familyValue.dropLast(10)).trimmingCharacters(in: .whitespacesAndNewlines) }
                let families = try split(familyValue, on: 44).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard !families.contains("") else { throw malformed() }
                let generic = families.filter { ["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"].contains($0.lowercased()) }
                if generic.count == families.count { return part }
                warn("Custom fonts were replaced with Kindle reader fonts; bold and italic styling is retained.")
                let prefix = String(decoding: raw[...colon.0], as: UTF8.self)
                return prefix + " " + (generic.isEmpty ? "serif" : generic.joined(separator: ", ")) + (important ? " !important" : "")
            }.joined(separator: ";")
        }
        var output = ""
        if !marks.contains(where: { $0.1 == 123 || $0.1 == 125 }) {
            output = try declarations(source)
        } else {
            var start = 0, opening: Int?
            let raw = Array(source.utf8)
            for (position, byte) in marks where byte == 123 || byte == 125 {
                if byte == 123 {
                    guard opening == nil else { throw malformed() }
                    opening = position
                } else {
                    guard let open = opening else { throw malformed() }
                    let header = String(decoding: raw[start..<open], as: UTF8.self)
                    let kind = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let body = String(decoding: raw[(open + 1)..<position], as: UTF8.self)
                    if kind == "@font-face" {
                        warn("Custom fonts were replaced with Kindle reader fonts; bold and italic styling is retained.")
                    } else if kind == "@page" {
                        _ = try declarations(body, page: true)
                        warn("Publisher page margins were removed; Kindle reader settings control page margins.")
                    } else {
                        guard !kind.isEmpty, !kind.contains("@"), !kind.contains(";") else { throw unsupported() }
                        output += header + "{" + (try declarations(body)) + "}"
                    }
                    opening = nil; start = position + 1
                }
            }
            guard opening == nil, String(decoding: raw[start...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw malformed() }
            output += String(decoding: raw[start...], as: UTF8.self)
        }
        let lower = output.lowercased()
        guard !["url", "@", "expression", "javascript", "behavior", "-moz-binding", "\\", "/*", "<", ">"].contains(where: lower.contains) else { throw unsupported() }
        try Task.checkCancellation()
        return Result(css: output, warnings: warnings)
    }

    /// Delimiters outside strings and balanced function/attribute groups.
    private static func delimiters(_ text: String) throws -> [(Int, UInt8)] {
        var result: [(Int, UInt8)] = [], quote: UInt8?, stack: [UInt8] = []
        for (index, byte) in text.utf8.enumerated() {
            if index % 4096 == 0 { try Task.checkCancellation() }
            if let active = quote { if byte == active { quote = nil }; continue }
            if byte == 34 || byte == 39 { quote = byte; continue }
            if byte == 40 || byte == 91 { stack.append(byte); continue }
            if byte == 41 || byte == 93 {
                guard stack.popLast() == (byte == 41 ? 40 : 91) else { throw malformed() }; continue
            }
            if stack.isEmpty, [UInt8(58), 59, 44, 123, 125].contains(byte) { result.append((index, byte)) }
        }
        guard quote == nil, stack.isEmpty else { throw malformed() }
        return result
    }
    private static func split(_ text: String, on delimiter: UInt8) throws -> [String] {
        let bytes = Array(text.utf8)
        var parts: [String] = [], start = 0
        for (index, _) in try delimiters(text).filter({ $0.1 == delimiter }) {
            parts.append(String(decoding: bytes[start..<index], as: UTF8.self)); start = index + 1
        }
        parts.append(String(decoding: bytes[start...], as: UTF8.self))
        return parts
    }
    private static func malformed() -> BookError { .invalid("Malformed or unsupported nested CSS in native AZW3 conversion.") }
    private static func unsupported() -> BookError { .unsupported("CSS imports, resource URLs, escapes and executable extensions are unsupported in AZW3 conversion.") }
}
