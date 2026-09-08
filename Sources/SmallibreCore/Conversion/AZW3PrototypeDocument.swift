import Foundation
import ImageIO

/// Bounded reflowable document normalizer shared with the original hardware proof profile.
/// Unsupported media and active content are rejected, and navigation is flattened.
struct AZW3PrototypeDocument {
    struct Chapter { let path: String; let title: String; let body: String; let targets: [String: Int]; var styles: String = ""; var rootAttributes: String = ""; var bodyAttributes: String = "" }
    struct Resource { let data: Data; let mime: String }
    struct Navigation { let title: String; let chapter: Int; let offset: Int }
    let metadata: BookMetadata
    let chapters: [Chapter]
    let resources: [Resource]
    let navigation: [Navigation]
    let coverIndex: Int?

    init(_ input: Data, production: Bool = false) throws {
        let chapterLimit = production ? 1024 * 1024 : 8192
        guard input.count <= 16 * 1024 * 1024 else { throw BookError.unsupported("Native AZW3 conversion accepts EPUBs up to 16 MB.") }
        let epub = try EPUBBook(data: input)
        guard epub.allowsTypography, !epub.archive.names.contains("META-INF/encryption.xml"),
              epub.chapters.count <= (production ? 512 : 64), Set(epub.chapters).count == epub.chapters.count else {
            throw BookError.unsupported("Native AZW3 conversion requires unencrypted reflowable chapters without repeated spine items, within its chapter count limit.")
        }
        metadata = epub.metadata
        let package = try SafeXML.document(epub.archive.data(named: epub.packagePath))
        var manifest: [String: (path: String, mime: String)] = [:]
        var navigationPath: String?
        for node in try package.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']") {
            guard let item = node as? XMLElement, let id = item.attribute(forName: "id")?.stringValue,
                  let href = item.attribute(forName: "href")?.stringValue, let mime = item.attribute(forName: "media-type")?.stringValue,
                  manifest[id] == nil else { throw BookError.invalid("Invalid or duplicate manifest item.") }
            let path = try EPUBBook.resolve(href, relativeTo: epub.packagePath)
            guard (["application/xhtml+xml", "image/png", "image/jpeg"] + (production ? ["text/css", "application/x-dtbncx+xml"] : [])).contains(mime) else {
                throw BookError.unsupported("Native AZW3 conversion cannot preserve \(mime). Only XHTML, CSS, NCX, PNG and JPEG resources are supported.")
            }
            guard epub.archive.names.contains(path) else { throw BookError.invalid("Missing prototype resource: \(path)") }
            manifest[id] = (path, mime)
            if item.attribute(forName: "properties")?.stringValue?.split(separator: " ").contains("nav") == true {
                guard navigationPath == nil else { throw BookError.invalid("Multiple EPUB navigation documents.") }
                navigationPath = path
            }
        }
        var usesNCX = false
        if navigationPath == nil, production,
           let spine = try package.nodes(forXPath: "//*[local-name()='spine']").first as? XMLElement,
           let toc = spine.attribute(forName: "toc")?.stringValue,
           let item = manifest[toc], item.mime == "application/x-dtbncx+xml" {
            navigationPath = item.path; usesNCX = true
        }
        guard let navigationPath else { throw BookError.unsupported("Native AZW3 conversion requires EPUB navigation (EPUB 3 nav or EPUB 2 spine NCX).") }
        var imageMap: [String: Int] = [:], images: [Resource] = [], imageBytes = 0
        for item in manifest.values.filter({ $0.mime.hasPrefix("image/") }).sorted(by: { $0.path < $1.path }) {
            guard imageMap[item.path] == nil else { throw BookError.invalid("Duplicate image resource.") }
            let data = try epub.archive.data(named: item.path)
            guard data.count <= 4 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_000_000 else {
                throw BookError.unsupported("Image dimensions or bytes exceed the prototype limits: \(item.path)")
            }
            let signatureOK = item.mime == "image/png" ? data.starts(with: [137,80,78,71,13,10,26,10]) : data.starts(with: [255,216,255])
            guard signatureOK else { throw BookError.invalid("Image bytes do not match their declared type.") }
            imageBytes += data.count
            guard imageBytes <= 16 * 1024 * 1024 else { throw BookError.unsupported("AZW3 images exceed 16 MB in total.") }
            imageMap[item.path] = images.count; images.append(Resource(data: data, mime: item.mime))
        }
        resources = images
        var coverPaths: Set<String> = []
        if production {
            for node in try package.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']") {
                if let item = node as? XMLElement,
                   item.attribute(forName: "properties")?.stringValue?.split(separator: " ").contains("cover-image") == true,
                   let id = item.attribute(forName: "id")?.stringValue, let value = manifest[id] { coverPaths.insert(value.path) }
            }
            for node in try package.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='meta'][@name='cover']") {
                if let item = node as? XMLElement, let id = item.attribute(forName: "content")?.stringValue,
                   let value = manifest[id] { coverPaths.insert(value.path) }
            }
        }
        guard coverPaths.count <= 1, coverPaths.allSatisfy({ imageMap[$0] != nil }) else { throw BookError.unsupported("Ambiguous or unsupported EPUB cover.") }
        coverIndex = coverPaths.first.flatMap { imageMap[$0] }
        struct PendingLink { let marker: String; let targetPath: String; let anchor: String; let chapter: Int; let byteOffset: Int }
        var links: [PendingLink] = [], parsed: [Chapter] = []
        var normalizedBytes = 0, stylesheetCache: [String: String] = [:]
        let supported: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "em", "strong", "b", "i", "u", "s", "blockquote", "ul", "ol", "li", "div", "span", "a", "img", "br", "hr", "sup", "sub", "pre", "code"]
        for (chapterNumber, path) in epub.chapters.enumerated() {
            try Task.checkCancellation()
            let xml = try SafeXML.document(epub.archive.data(named: path))
            guard let root = xml.rootElement(), root.localName == "html",
                  let body = try xml.nodes(forXPath: "/*[local-name()='html']/*[local-name()='body']").first as? XMLElement else {
                throw BookError.invalid("Invalid prototype chapter: \(path)")
            }
            let children = root.children ?? []
            guard production || (root.attributes ?? []).isEmpty,
                  children.filter({ $0.localName == "body" }).count == 1,
                  children.filter({ $0.localName == "head" }).count == 1,
                  children.allSatisfy({ $0.localName == "head" || $0.localName == "body" || $0.kind == .comment || ($0.kind == .text && ($0.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }) else {
                throw BookError.unsupported("Unsupported root attributes or chapter structure in \(path).")
            }
            let headChildren = try xml.nodes(forXPath: "/*[local-name()='html']/*[local-name()='head']/*")
            guard headChildren.allSatisfy({ ["title", "meta"].contains($0.localName ?? "") || (production && ["style", "link"].contains($0.localName ?? "")) }) else {
                throw BookError.unsupported("The prototype does not yet preserve chapter styles or linked resources.")
            }
            func containerAttributes(_ element: XMLElement) throws -> String {
                guard production else { return "" }
                return try (element.attributes ?? []).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }).map { attribute in
                    let key = attribute.name ?? "", value = attribute.stringValue ?? ""
                    guard ["id", "class", "style", "lang", "xml:lang", "dir", "epub:type"].contains(key) else { throw BookError.unsupported("Unsupported chapter container attribute: \(key)") }
                    return " " + key + "=\"" + Self.escape(key == "style" ? try Self.safeCSS(value) : value) + "\""
                }.joined()
            }
            let rootAttributes = try containerAttributes(root), bodyAttributes = try containerAttributes(body)
            var styles = ""
            if production {
                for node in headChildren {
                    guard let element = node as? XMLElement else { continue }
                    if element.localName == "style" { styles += try Self.safeCSS(element.stringValue ?? "") + "\n" }
                    if element.localName == "link" {
                        guard element.attribute(forName: "rel")?.stringValue == "stylesheet",
                              let href = element.attribute(forName: "href")?.stringValue else { throw BookError.unsupported("Unsupported chapter head link.") }
                        let cssPath = try EPUBBook.resolve(href, relativeTo: path)
                        guard manifest.values.contains(where: { $0.path == cssPath && $0.mime == "text/css" }),
                              let css = String(data: try epub.archive.data(named: cssPath), encoding: .utf8) else { throw BookError.invalid("Missing UTF-8 stylesheet.") }
                        let normalized = try stylesheetCache[cssPath] ?? Self.safeCSS(css)
                        stylesheetCache[cssPath] = normalized
                        styles += normalized + "\n"
                    }
                    guard styles.utf8.count <= 1024 * 1024 else { throw BookError.unsupported("Chapter styles exceed 1 MB.") }
                }
            }
            let title = (headChildren.first(where: { $0.localName == "title" })?.stringValue) ?? "Chapter \(chapterNumber + 1)"
            var result = "", targets: [String: Int] = ["": 0], tagNumber = 0
            func serialize(_ node: XMLNode) throws {
                try Task.checkCancellation()
                if node.kind == .text { result += Self.escape(node.stringValue ?? ""); return }
                if node.kind == .comment { return }
                guard let element = node as? XMLElement, let name = element.localName, (supported.contains(name) || (production && ["section", "article", "nav", "aside", "figure", "figcaption", "header", "footer", "main"].contains(name))),
                      element.uri == nil || element.uri == "" || element.uri == "http://www.w3.org/1999/xhtml" else {
                    throw BookError.unsupported("Unsupported content in \(path): \(node.name ?? "node")")
                }
                if let id = element.attribute(forName: "id")?.stringValue {
                    guard targets[id] == nil else { throw BookError.invalid("Duplicate chapter anchor: \(id)") }
                    targets[id] = result.utf8.count
                }
                result += "<" + name
                for attribute in (element.attributes ?? []).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
                    let key = attribute.name ?? "", value = attribute.stringValue ?? ""
                    guard (["id", "class", "title", "href", "src", "alt", "width", "height", "lang"] + (production ? ["style", "xml:lang", "epub:type"] : [])).contains(key) else {
                        throw BookError.unsupported("Unsupported prototype attribute \(key) in \(path).")
                    }
                    var output = value
                    if key == "style" { output = try Self.safeCSS(value) }
                    if key == "href" {
                        guard name == "a" else { throw BookError.unsupported("Unsupported resource link.") }
                        let target = try Self.resolveTarget(value, from: path)
                        guard epub.chapters.contains(target.0) else { throw BookError.unsupported("The prototype only supports links to spine chapters.") }
                        let marker = "kindle:pos:fid:0000:off:" + Self.base32(links.count, width: 10)
                        links.append(PendingLink(marker: marker, targetPath: target.0, anchor: target.1, chapter: chapterNumber, byteOffset: result.utf8.count + (" " + key + "=\"").utf8.count)); output = marker
                    }
                    if key == "src" {
                        let target = try EPUBBook.resolve(value, relativeTo: path)
                        guard name == "img", let image = imageMap[target] else { throw BookError.invalid("Missing or unsupported prototype image.") }
                        output = "kindle:embed:" + Self.base32(image + 1, width: 4) + "?mime=" + images[image].mime
                    }
                    result += " " + key + "=\"" + Self.escape(output) + "\""
                }
                if name == "img", element.attribute(forName: "src") == nil { throw BookError.invalid("Image has no source.") }
                result += " aid=\"A" + Self.base32(chapterNumber, width: 2) + Self.base32(tagNumber, width: 4) + "\""
                tagNumber += 1
                if ["img", "br", "hr"].contains(name) {
                    guard (element.children ?? []).isEmpty else { throw BookError.unsupported("Void element contains content in \(path).") }
                    result += "/>"
                }
                else {
                    result += ">"
                    for child in element.children ?? [] { try serialize(child) }
                    result += "</" + name + ">"
                }
                guard result.utf8.count <= chapterLimit else { throw BookError.unsupported("Chapter exceeds the bounded AZW3 fragment size.") }
            }
            for attribute in body.attributes ?? [] {
                guard production || attribute.name == "id" else { throw BookError.unsupported("Unsupported prototype body attribute.") }
                if attribute.name == "id", let id = attribute.stringValue { targets[id] = 0 }
            }
            for child in body.children ?? [] { try serialize(child) }
            guard !result.isEmpty, result.utf8.count <= chapterLimit else { throw BookError.unsupported("Empty or oversized prototype chapter.") }
            normalizedBytes += result.utf8.count + styles.utf8.count + rootAttributes.utf8.count + bodyAttributes.utf8.count + title.utf8.count + 256
            guard normalizedBytes <= 24 * 1024 * 1024 else { throw BookError.unsupported("Normalized AZW3 text and styles exceed 24 MB.") }
            parsed.append(Chapter(path: path, title: title, body: result, targets: targets, styles: styles, rootAttributes: rootAttributes, bodyAttributes: bodyAttributes))
        }
        func destination(_ path: String, _ anchor: String) throws -> (Int, Int) {
            guard let index = parsed.firstIndex(where: { $0.path == path }), let offset = parsed[index].targets[anchor] else {
                throw BookError.invalid("Missing link/navigation target: \(path)#\(anchor)")
            }
            return (index, offset)
        }
        var bodies = parsed.map { Data($0.body.utf8) }
        for link in links {
            let (index, offset) = try destination(link.targetPath, link.anchor)
            let replacement = Data(("kindle:pos:fid:" + Self.base32(index, width: 4) + ":off:" + Self.base32(offset, width: 10)).utf8)
            let range = link.byteOffset..<link.byteOffset + link.marker.utf8.count
            guard replacement.count == range.count, bodies[link.chapter].subdata(in: range) == Data(link.marker.utf8) else {
                throw BookError.invalid("Prototype link position changed during serialization.")
            }
            bodies[link.chapter].replaceSubrange(range, with: replacement)
        }
        chapters = parsed.enumerated().map { index, chapter in
            Chapter(path: chapter.path, title: chapter.title, body: String(decoding: bodies[index], as: UTF8.self), targets: chapter.targets, styles: chapter.styles, rootAttributes: chapter.rootAttributes, bodyAttributes: chapter.bodyAttributes)
        }
        let navXML = try SafeXML.document(epub.archive.data(named: navigationPath))
        if usesNCX {
            let points = try navXML.nodes(forXPath: "//*[local-name()='navMap']//*[local-name()='navPoint']")
            guard !points.isEmpty, points.count <= 512 else { throw BookError.unsupported("AZW3 navigation supports up to 512 entries.") }
            navigation = try points.map { node in
                guard let content = try node.nodes(forXPath: "./*[local-name()='content']").first as? XMLElement,
                      let href = content.attribute(forName: "src")?.stringValue else { throw BookError.invalid("NCX entry has no destination.") }
                let target = try Self.resolveTarget(href, from: navigationPath)
                let (index, offset) = try destination(target.0, target.1)
                let title = try node.nodes(forXPath: "./*[local-name()='navLabel']/*[local-name()='text']").first?.stringValue ?? "Chapter"
                return Navigation(title: title, chapter: index, offset: offset)
            }
            return
        }
        let navs = try navXML.nodes(forXPath: "//*[local-name()='nav']").compactMap { $0 as? XMLElement }.filter {
            $0.attributes?.contains(where: { $0.localName == "type" && ($0.stringValue?.split(separator: " ").contains("toc") == true) }) == true
        }
        guard navs.count == 1 else { throw BookError.invalid("Missing or ambiguous EPUB table of contents.") }
        let nav = navs[0]
        guard try production || (nav.nodes(forXPath: ".//*[local-name()='li']//*[local-name()='li']").isEmpty) else {
            throw BookError.unsupported("The prototype supports a flat table of contents only.")
        }
        let anchors = try nav.nodes(forXPath: ".//*[local-name()='a']").compactMap { $0 as? XMLElement }
        guard !anchors.isEmpty, anchors.count <= (production ? 512 : 64) else { throw BookError.invalid("Invalid prototype navigation size.") }
        navigation = try anchors.map { a in
            guard let href = a.attribute(forName: "href")?.stringValue else { throw BookError.invalid("Navigation entry has no destination.") }
            let target = try Self.resolveTarget(href, from: navigationPath)
            let (index, offset) = try destination(target.0, target.1)
            return Navigation(title: a.stringValue ?? "Chapter", chapter: index, offset: offset)
        }
    }

    /// Reject CSS features requiring resource loading or executable/vendor extensions. Escapes
    /// are rejected and comments removed before validation to prevent token obfuscation.
    private static func safeCSS(_ css: String) throws -> String {
        guard css.utf8.count <= 1024 * 1024 else { throw BookError.unsupported("CSS exceeds 1 MB.") }
        let bytes = Array(css.utf8)
        var filtered: [UInt8] = [], index = 0
        filtered.reserveCapacity(bytes.count)
        while index < bytes.count {
            if index % 4096 == 0 { try Task.checkCancellation() }
            if index + 1 < bytes.count, bytes[index] == 47, bytes[index + 1] == 42 {
                index += 2
                while index + 1 < bytes.count && !(bytes[index] == 42 && bytes[index + 1] == 47) {
                    if index % 4096 == 0 { try Task.checkCancellation() }
                    index += 1
                }
                guard index + 1 < bytes.count else { throw BookError.invalid("Unterminated CSS comment.") }
                index += 2
            } else { filtered.append(bytes[index]); index += 1 }
        }
        let cleaned = String(decoding: filtered, as: UTF8.self)
        let lower = cleaned.lowercased()
        guard css.utf8.count <= 1024 * 1024,
              !["url", "@", "expression", "javascript", "behavior", "-moz-binding", "\\", "/*", "<", ">"].contains(where: lower.contains) else {
            throw BookError.unsupported("CSS imports, resource URLs, escapes and executable extensions are unsupported in AZW3 conversion.")
        }
        return cleaned
    }

    private static func resolveTarget(_ href: String, from path: String) throws -> (String, String) {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let anchor = (parts.count > 1 ? String(parts[1]) : "").removingPercentEncoding else { throw BookError.invalid("Invalid anchor encoding.") }
        return (parts[0].isEmpty ? path : try EPUBBook.resolve(String(parts[0]), relativeTo: path), anchor)
    }
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func base32(_ value: Int, width: Int) -> String {
        let text = String(value, radix: 32, uppercase: true)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
