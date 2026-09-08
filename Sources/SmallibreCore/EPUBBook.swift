import Foundation

public struct EPUBBook: Sendable {
    public let archive: ZIPArchive
    public let packagePath: String
    public let chapters: [String]
    public let metadata: BookMetadata
    public let allowsTypography: Bool

    public init(data: Data) throws {
        let archive = try ZIPArchive(data: data)
        guard try archive.data(named: "mimetype") == Data("application/epub+zip".utf8) else { throw BookError.invalid("This ZIP file is not an EPUB book.") }
        let container = try SafeXML.document(archive.data(named: "META-INF/container.xml"))
        guard let rootfile = try container.nodes(forXPath: "//*[local-name()='rootfile']").first as? XMLElement,
              let path = rootfile.attribute(forName: "full-path")?.stringValue, ZIPArchive.isSafePath(path) else { throw BookError.invalid("The EPUB does not specify a valid package.") }
        let package = try SafeXML.document(archive.data(named: path))
        guard package.rootElement()?.localName == "package" else { throw BookError.invalid("Invalid EPUB package.") }
        func values(_ name: String) throws -> [String] {
            try package.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='\(name)']").compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        var items: [String: String] = [:], coverPath: String?
        let coverID = (try package.nodes(forXPath: "//*[local-name()='meta'][@name='cover']").first as? XMLElement)?.attribute(forName: "content")?.stringValue
        for node in try package.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']") {
            guard let item = node as? XMLElement, let id = item.attribute(forName: "id")?.stringValue,
                  let href = item.attribute(forName: "href")?.stringValue else { continue }
            let resolved = try Self.resolve(href, relativeTo: path)
            items[id] = resolved
            if item.attribute(forName: "properties")?.stringValue?.split(separator: " ").contains("cover-image") == true || id == coverID { coverPath = resolved }
        }
        let chapters = try package.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']").compactMap { node -> String? in
            guard let node = node as? XMLElement, let id = node.attribute(forName: "idref")?.stringValue else { return nil }
            guard let name = items[id], archive.names.contains(name) else { throw BookError.invalid("The EPUB reading order references a missing chapter.") }
            return name
        }
        guard !chapters.isEmpty else { throw BookError.invalid("The EPUB has no readable chapters.") }
        if archive.names.contains("META-INF/encryption.xml") {
            let encryption = try SafeXML.document(archive.data(named: "META-INF/encryption.xml"))
            for element in try encryption.nodes(forXPath: "//*[local-name()='EncryptionMethod']") {
                let algorithm = (element as? XMLElement)?.attribute(forName: "Algorithm")?.stringValue ?? ""
                guard ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"].contains(algorithm) else {
                    throw BookError.unsupported("This book is protected. Smallibre currently supports DRM-free books.")
                }
            }
        }
        var cover: Data?
        if let coverPath, let resource = try? archive.data(named: coverPath), resource.count < 12 * 1024 * 1024 { cover = resource }
        self.archive = archive; packagePath = path; self.chapters = chapters
        metadata = BookMetadata(title: try values("title").first ?? "Untitled", authors: try values("creator"), language: try values("language").first ?? "", identifier: try values("identifier").first ?? "", publisher: try values("publisher").first ?? "", description: try values("description").first ?? "", format: "EPUB", cover: cover, published: try values("date").first)
        let layout = try package.nodes(forXPath: "//*[local-name()='meta'][@property='rendition:layout']").first?.stringValue
        let special = try package.nodes(forXPath: "//*[local-name()='manifest']/*[@media-overlay or contains(@properties,'scripted')]")
        allowsTypography = layout != "pre-paginated" && special.isEmpty
    }

    public static func resolve(_ href: String, relativeTo path: String) throws -> String {
        let withoutFragment = String(href.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
        guard let decoded = withoutFragment.removingPercentEncoding, !decoded.contains(":"), !decoded.hasPrefix("/"), !decoded.contains("\\"), !decoded.contains("\0") else { throw BookError.invalid("The book references an unsupported external resource.") }
        var parts = path.split(separator: "/").dropLast().map(String.init)
        for part in decoded.split(separator: "/") {
            if part == ".." { guard !parts.isEmpty else { throw BookError.invalid("A resource escapes the book container.") }; parts.removeLast() }
            else if part != "." { parts.append(String(part)) }
        }
        let result = parts.joined(separator: "/")
        guard ZIPArchive.isSafePath(result) else { throw BookError.invalid("Invalid resource path.") }
        return result
    }
}

enum SafeXML {
    static func document(_ data: Data, preservingTextWhitespace: Bool = false) throws -> XMLDocument {
        guard data.count <= 8 * 1024 * 1024,
              let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
              !string.localizedCaseInsensitiveContains("<!ENTITY") else { throw BookError.invalid("Unsupported XML encoding, entities or document size.") }
        let validator = XMLBounds()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        guard parser.parse(), !validator.exceeded else { throw BookError.invalid("The book contains invalid or excessively nested XML.") }
        // Foundation retains whitespace-only runs in xmlString but omits them from
        // children, joining words when callers traverse inline elements. Character
        // references make those runs ordinary text nodes without changing their text.
        if preservingTextWhitespace {
            let encoding: String.Encoding = String(data: data, encoding: .utf8) != nil ? .utf8 : .utf16
            guard let preserved = try preserveWhitespaceNodes(string).data(using: encoding), preserved.count <= 8 * 1024 * 1024 else {
                throw BookError.invalid("Whitespace-preserving XML exceeds 8 MB.")
            }
            return try XMLDocument(data: preserved, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        }
        return try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
    }

    private static func preserveWhitespaceNodes(_ xml: String) throws -> String {
        let bytes = Array(xml.utf8)
        var output: [UInt8] = [], index = 0, depth = 0
        output.reserveCapacity(bytes.count)
        func starts(_ token: String, at offset: Int) -> Bool {
            bytes[offset...].starts(with: token.utf8)
        }
        while index < bytes.count {
            try Task.checkCancellation()
            let start = index
            if bytes[index] == 60 {
                let terminator: String?
                if starts("<!--", at: index) { terminator = "-->" }
                else if starts("<![CDATA[", at: index) { terminator = "]]>" }
                else if starts("<?", at: index) { terminator = "?>" }
                else { terminator = nil }
                if let terminator {
                    index += 2
                    while index < bytes.count, !starts(terminator, at: index) {
                        if index % 4096 == 0 { try Task.checkCancellation() }
                        index += 1
                    }
                    index = min(bytes.count, index + terminator.utf8.count)
                } else {
                    var quote: UInt8?
                    index += 1
                    while index < bytes.count {
                        if index % 4096 == 0 { try Task.checkCancellation() }
                        let byte = bytes[index]; index += 1
                        if let active = quote { if byte == active { quote = nil }; continue }
                        if byte == 34 || byte == 39 { quote = byte }
                        else if byte == 91, starts("<!DOCTYPE", at: start) {
                            throw BookError.unsupported("Internal XML document type subsets cannot preserve ebook text safely.")
                        }
                        else if byte == 62 { break }
                    }
                }
                if terminator == nil, start + 1 < bytes.count, bytes[start + 1] != 33 {
                    if bytes[start + 1] == 47 { depth -= 1 }
                    else if index >= 2, bytes[index - 2] != 47 { depth += 1 }
                }
                guard output.count + index - start <= 8 * 1024 * 1024 else { throw BookError.invalid("Whitespace-preserving XML exceeds 8 MB.") }
                output.append(contentsOf: bytes[start..<index])
            } else {
                while index < bytes.count, bytes[index] != 60 {
                    if index % 4096 == 0 { try Task.checkCancellation() }
                    index += 1
                }
                let run = bytes[start..<index]
                if depth > 0, run.allSatisfy({ [UInt8(32), 9, 10, 13].contains($0) }) {
                    guard output.count + run.count * 6 <= 8 * 1024 * 1024 else { throw BookError.invalid("Whitespace-preserving XML exceeds 8 MB.") }
                    var previous: UInt8?
                    for (offset, byte) in run.enumerated() {
                        if offset % 4096 == 0 { try Task.checkCancellation() }
                        if byte != 10 || previous != 13 { output.append(contentsOf: "&#\(byte == 13 ? 10 : byte);".utf8) }
                        previous = byte
                    }
                } else {
                    guard output.count + run.count <= 8 * 1024 * 1024 else { throw BookError.invalid("Whitespace-preserving XML exceeds 8 MB.") }
                    output.append(contentsOf: run)
                }
            }
        }
        return String(decoding: output, as: UTF8.self)
    }
}

private final class XMLBounds: NSObject, XMLParserDelegate {
    var depth = 0, nodes = 0, exceeded = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        depth += 1; nodes += 1
        if depth > 128 || nodes > 100_000 { exceeded = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}
