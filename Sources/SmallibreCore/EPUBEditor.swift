import Foundation

enum EPUBEditor {
    static func prepare(_ epub: EPUBBook, metadata: BookMetadata, typography: TypographySettings) throws -> Data {
        guard !typography.enabled || epub.allowsTypography else { throw BookError.unsupported("Typography changes are available for reflowable books without scripts or media overlays.") }
        guard typography.lineHeight.isFinite, (1...2.4).contains(typography.lineHeight), typography.marginPercent.isFinite, (0...12).contains(typography.marginPercent) else { throw BookError.invalid("Typography settings are outside the supported range.") }
        var changes: [String: Data] = [:]
        var embeddedMetadata = epub.metadata; embeddedMetadata.cover = nil
        var requestedMetadata = metadata; requestedMetadata.cover = nil
        if requestedMetadata != embeddedMetadata {
            let package = try SafeXML.document(epub.archive.data(named: epub.packagePath))
            guard let element = try package.nodes(forXPath: "//*[local-name()='metadata']").first as? XMLElement else { throw BookError.invalid("Missing book metadata.") }
            if element.resolveNamespace(forName: "dc") == nil { element.addNamespace(XMLNode.namespace(withName: "dc", stringValue: "http://purl.org/dc/elements/1.1/") as! XMLNode) }
            let fields = [("title", [metadata.title], [epub.metadata.title]), ("creator", metadata.authors, epub.metadata.authors), ("language", [metadata.language], [epub.metadata.language]), ("publisher", [metadata.publisher], [epub.metadata.publisher]), ("description", [metadata.description], [epub.metadata.description])]
            for (name, requested, original) in fields where requested != original {
                let values = requested.filter { !$0.isEmpty }
                let existing = try element.nodes(forXPath: "./*[local-name()='\(name)']")
                for (index, value) in values.enumerated() {
                    if index < existing.count { existing[index].stringValue = value }
                    else { element.addChild(XMLElement(name: "dc:\(name)", stringValue: value)) }
                }
                // Removing an author must also remove refinements that would otherwise dangle.
                if name == "creator" || values.isEmpty {
                    for old in existing.dropFirst(values.count) {
                        if let id = (old as? XMLElement)?.attribute(forName: "id")?.stringValue {
                            for refined in try element.nodes(forXPath: "./*[@refines]") {
                                if (refined as? XMLElement)?.attribute(forName: "refines")?.stringValue == "#" + id { refined.detach() }
                            }
                        }
                        old.detach()
                    }
                }
            }
            changes[epub.packagePath] = package.xmlData
        }
        if typography.enabled {
            let line = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), typography.lineHeight)
            let margin = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), typography.marginPercent)
            let font: String
            switch typography.font { case .original: font = ""; case .serif: font = "font-family: serif !important;"; case .sansSerif: font = "font-family: sans-serif !important;" }
            let css = "body { margin-left: \(margin)% !important; margin-right: \(margin)% !important; } body, p { line-height: \(line) !important; \(font) }"
            for path in epub.chapters {
                let chapter = try SafeXML.document(epub.archive.data(named: path))
                guard let head = try chapter.nodes(forXPath: "//*[local-name()='head']").first as? XMLElement else { throw BookError.invalid("A chapter has no document head.") }
                for node in try head.nodes(forXPath: "./*[local-name()='style'][@id='smallibre-typography' or @id='nova-typography']") { node.detach() }
                let prefix = head.prefix.flatMap { $0.isEmpty ? nil : $0 }
                let style = XMLElement(name: prefix.map { "\($0):style" } ?? "style", uri: "http://www.w3.org/1999/xhtml")
                style.stringValue = css
                style.addAttribute(XMLNode.attribute(withName: "id", stringValue: "smallibre-typography") as! XMLNode)
                style.addAttribute(XMLNode.attribute(withName: "type", stringValue: "text/css") as! XMLNode)
                head.addChild(style)
                changes[path] = chapter.xmlData
            }
        }
        if changes.isEmpty { return try epub.archive.writing(replacements: [:]) }
        let result = try epub.archive.writing(replacements: changes)
        let validated = try EPUBBook(data: result)
        guard validated.chapters == epub.chapters else { throw BookError.invalid("Preparation changed the book's reading order.") }
        for name in changes.keys { _ = try validated.archive.data(named: name) }
        return result
    }
}
