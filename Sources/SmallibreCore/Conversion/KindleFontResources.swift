import Foundation

/// Fonts are omitted, never decoded or decrypted. Only recognized font-only obfuscation is accepted.
enum KindleFontResources {
    static let mediaTypes: Set<String> = ["application/vnd.ms-opentype", "application/x-font-opentype", "application/x-font-ttf", "application/x-font-truetype", "application/font-sfnt", "application/font-woff", "font/otf", "font/ttf", "font/woff", "font/woff2"]
    static func validateEncryption(in epub: EPUBBook, fontPaths: Set<String>) throws {
        guard epub.archive.names.contains("META-INF/encryption.xml") else { return }
        let xml = try SafeXML.document(epub.archive.data(named: "META-INF/encryption.xml"))
        guard let root = xml.rootElement(), root.localName == "encryption" else { throw BookError.invalid("Invalid EPUB encryption declarations.") }
        let blocks = try xml.nodes(forXPath: "/*[local-name()='encryption']/*[local-name()='EncryptedData']")
        guard !blocks.isEmpty, blocks.count <= 10_000,
              (root.children ?? []).filter({ $0.kind == .element }).count == blocks.count else {
            throw BookError.unsupported("Only font obfuscation declarations are supported for Kindle conversion.")
        }
        var seen = Set<String>()
        for block in blocks {
            try Task.checkCancellation()
            let children = (block.children ?? []).filter { $0.kind == .element }
            guard children.count == 2, Set(children.compactMap(\.localName)) == ["EncryptionMethod", "CipherData"],
                  let cipher = children.first(where: { $0.localName == "CipherData" }),
                  (cipher.children ?? []).filter({ $0.kind == .element }).count == 1 else {
                throw BookError.unsupported("Unsupported encryption structure; only explicit font-only obfuscation declarations are accepted.")
            }
            let methods = try block.nodes(forXPath: "./*[local-name()='EncryptionMethod']")
            let references = try block.nodes(forXPath: "./*[local-name()='CipherData']/*[local-name()='CipherReference']")
            guard methods.count == 1, references.count == 1,
                  let method = methods.first as? XMLElement, let reference = references.first as? XMLElement,
                  (method.children ?? []).filter({ $0.kind == .element }).isEmpty,
                  let algorithm = method.attribute(forName: "Algorithm")?.stringValue,
                  ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"].contains(algorithm),
                  let uri = reference.attribute(forName: "URI")?.stringValue,
                  !uri.contains("#"), !uri.contains("?"), (reference.children ?? []).filter({ $0.kind == .element }).isEmpty else {
                throw BookError.unsupported("Encrypted content is unsupported; only recognized font-only obfuscation can use font fallback.")
            }
            let path = try EPUBBook.resolve(uri, relativeTo: "container.xml")
            guard fontPaths.contains(path), !epub.chapters.contains(path), seen.insert(path).inserted else {
                throw BookError.unsupported("The encryption declaration does not exclusively reference a declared font. Book content cannot use font fallback.")
            }
        }
    }
}
