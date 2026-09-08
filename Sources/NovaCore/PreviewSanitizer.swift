import Foundation

public enum PreviewSanitizer {
    public static func allowsNavigation(_ url: URL) -> Bool {
        url.scheme == "nova-book" && url.host == "book" && ["html", "xhtml", "htm"].contains(url.pathExtension.lowercased())
    }
    public static func html(_ data: Data) throws -> Data {
        let document = try SafeXML.document(data)
        let blocked: Set<String> = ["script", "iframe", "frame", "frameset", "object", "embed", "form", "base", "meta"]
        for element in try document.nodes(forXPath: "//*").compactMap({ $0 as? XMLElement }) {
            if blocked.contains(element.localName?.lowercased() ?? "") { element.detach(); continue }
            for attribute in element.attributes ?? [] where attribute.localName?.lowercased().hasPrefix("on") == true {
                if let name = attribute.name { element.removeAttribute(forName: name) }
            }
            if element.uri == "http://www.w3.org/1999/xhtml", let name = element.localName { element.name = name }
        }
        guard let head = try document.nodes(forXPath: "//*[local-name()='head']").first as? XMLElement else { throw BookError.invalid("No previewable chapter head.") }
        let policy = XMLElement(name: "meta")
        policy.addAttribute(XMLNode.attribute(withName: "http-equiv", stringValue: "Content-Security-Policy") as! XMLNode)
        policy.addAttribute(XMLNode.attribute(withName: "content", stringValue: "default-src 'none'; img-src nova-book: data:; style-src nova-book: 'unsafe-inline'; font-src nova-book: data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'") as! XMLNode)
        head.insertChild(policy, at: 0)
        let style = XMLElement(name: "style", stringValue: "html { color-scheme: light dark; } body { max-width: 42em; padding: 28px; margin: 0 auto; font-size: 19px; } img, svg { max-width: 100%; height: auto; }")
        head.insertChild(style, at: 1)
        document.characterEncoding = "utf-8"
        document.documentContentKind = .html
        return document.xmlData
    }
}
