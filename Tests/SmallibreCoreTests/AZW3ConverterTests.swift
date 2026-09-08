import XCTest
@testable import SmallibreCore

final class AZW3ConverterTests: XCTestCase {
    private func fixture() throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!)
    }
    func testConvertsLongStyledChapterWithoutLosingText() throws {
        let archive = try ZIPArchive(data: fixture()), path = "Book/text/one.xhtml"
        let original = String(data: try archive.data(named: path), encoding: .utf8)!
        let prose = String(repeating: "Long café 🌙 paragraph. ", count: 2000)
        let changed = original.replacingOccurrences(of: "</head>", with: "<style>p { color: red; }</style></head>")
            .replacingOccurrences(of: "</body>", with: "<p style=\"text-align: center\">\(prose)</p></body>")
        let result = try AZW3Converter.convert(archive.writing(replacements: [path: Data(changed.utf8)]))
        try AZW3Converter.validate(result.data)
        XCTAssertNotNil(result.data.range(of: Data(prose.utf8)))
        XCTAssertNotNil(result.data.range(of: Data("p { color: red; }".utf8)))
        XCTAssertNotNil(result.data.range(of: Data("text-align: center".utf8)))
    }
    func testEPUB2NavigationAndCoverMetadata() throws {
        let archive = try ZIPArchive(data: fixture())
        let packagePath = "Book/package.opf"
        let package = String(data: try archive.data(named: packagePath), encoding: .utf8)!
            .replacingOccurrences(of: "version=\"3.0\"", with: "version=\"2.0\"")
            .replacingOccurrences(of: "href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"", with: "href=\"nav.xhtml\" media-type=\"application/x-dtbncx+xml\"")
            .replacingOccurrences(of: "<spine>", with: "<spine toc=\"nav\">")
            .replacingOccurrences(of: "</metadata>", with: "<meta name=\"cover\" content=\"image\"/></metadata>")
        let ncx = "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\"><navMap><navPoint id=\"a\"><navLabel><text>First section</text></navLabel><content src=\"text/one.xhtml\"/></navPoint><navPoint id=\"b\"><navLabel><text>Second section</text></navLabel><content src=\"text/two.xhtml\"/></navPoint></navMap></ncx>"
        let output = try AZW3Converter.convert(archive.writing(replacements: [packagePath: Data(package.utf8), "Book/nav.xhtml": Data(ncx.utf8)])).data
        XCTAssertNotNil(output.range(of: Data("First section".utf8)))
        let header = Int(output.be32(78)), exth = header + 280
        var cursor = exth + 12, cover: UInt32?
        for _ in 0..<Int(output.be32(exth + 8)) {
            if output.be32(cursor) == 201 { cover = output.be32(cursor + 8) }
            cursor += Int(output.be32(cursor + 4))
        }
        XCTAssertEqual(cover, 0)
    }
    func testBundledSampleAndCommentedCSSConvert() throws {
        let sample = try Data(contentsOf: Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!)
        let archive = try ZIPArchive(data: sample)
        let output = try AZW3Converter.convert(archive.writing(replacements: ["EPUB/style.css": Data("/* authored stylesheet */ p { color: red; }".utf8)])).data
        XCTAssertNotNil(output.range(of: Data("A book asks for very little".utf8)))
        XCTAssertNotNil(output.range(of: Data("p { color: red; }".utf8)))
    }
    func testSupports300ChaptersWithSortedNavigationAndAggregateBounds() throws {
        let archive = try ZIPArchive(data: fixture())
        var replacements: [String: Data] = [:], items = "", spine = "", nav = ""
        for index in 0..<300 {
            let name = "chapter\(index).xhtml"
            items += "<item id=\"c\(index)\" href=\"\(name)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"c\(index)\"/>"
            nav += "<li><a href=\"\(name)\">Section \(index)</a></li>"
            replacements["Book/" + name] = Data("<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Section \(index)</title></head><body><p>Text \(index)</p></body></html>".utf8)
        }
        replacements["Book/package.opf"] = Data("<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>Many chapters</dc:title></metadata><manifest>\(items)<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/></manifest><spine>\(spine)</spine></package>".utf8)
        replacements["Book/nav.xhtml"] = Data("<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>Contents</title></head><body><nav epub:type=\"toc\"><ol>\(nav)</ol></nav></body></html>".utf8)
        let output = try AZW3Converter.convert(archive.writing(replacements: replacements)).data
        XCTAssertNotNil(output.range(of: Data("Text 299".utf8)))
        // Read labels directly from the navigation IDXT offsets, independently of the encoder.
        let header = Int(output.be32(78)), navigation = Int(output.be32(header + 244))
        let entryRecord = Int(output.be32(78 + (navigation + 1) * 8))
        let entryCount = Int(output.be32(entryRecord + 24)), table = entryRecord + Int(output.be32(entryRecord + 20))
        let labels = (0..<entryCount).map { index -> String in
            let start = entryRecord + Int(output.be16(table + 4 + index * 2))
            return String(decoding: output.subdata(in: start + 1..<start + 1 + Int(output[start])), as: UTF8.self)
        }
        XCTAssertEqual(labels.count, 300)
        XCTAssertEqual(labels, labels.sorted(), "Navigation labels must retain lexical reading order beyond FF")
        XCTAssertEqual(labels[255], "0FF")
        XCTAssertEqual(labels[256], "100")

        for index in 0..<100 {
            let path = "Book/chapter\(index).xhtml"
            let chapter = String(data: replacements[path]!, encoding: .utf8)!.replacingOccurrences(of: "</head>", with: "<link rel=\"stylesheet\" href=\"large.css\"/></head>")
            replacements[path] = Data(chapter.utf8)
        }
        replacements["Book/large.css"] = Data(String(repeating: "p { color:red; }", count: 20_000).utf8)
        replacements["Book/package.opf"] = Data(String(data: replacements["Book/package.opf"]!, encoding: .utf8)!.replacingOccurrences(of: "</manifest>", with: "<item id=\"css\" href=\"large.css\" media-type=\"text/css\"/></manifest>").utf8)
        XCTAssertThrowsError(try AZW3Converter.convert(archive.writing(replacements: replacements))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Normalized"), error.localizedDescription)
        }
    }
    func testPreservesCommonRootBodyAndSemanticMarkup() throws {
        let archive = try ZIPArchive(data: fixture()), path = "Book/text/one.xhtml"
        let original = String(data: try archive.data(named: path), encoding: .utf8)!
        let chapter = original.replacingOccurrences(of: "<html ", with: "<html lang=\"pl\" xml:lang=\"pl\" ")
            .replacingOccurrences(of: "<body>", with: "<body class=\"prose\" style=\"margin: 2em\" lang=\"pl\">")
            .replacingOccurrences(of: "</body>", with: "<section epub:type=\"chapter\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><figure><figcaption>Caption</figcaption></figure></section></body>")
        let output = try AZW3PrototypeWriter.convert(archive.writing(replacements: [path: Data(chapter.utf8)]), production: true)
        for text in ["lang=\"pl\"", "class=\"prose\"", "style=\"margin: 2em\"", "<section", "<figcaption"] {
            XCTAssertNotNil(output.range(of: Data(text.utf8)), text)
        }
        let header = Int(output.be32(78)), textCount = Int(output.be16(header + 8))
        let start = Int(output.be32(86)), end = Int(output.be32(78 + (textCount + 1) * 8))
        let raw = String(decoding: output.subdata(in: start..<end), as: UTF8.self)
        // Independently restore the one-fragment chapter layout: skeleton, then its body.
        let first = try XCTUnwrap(raw.components(separatedBy: "<html ").dropFirst().first)
        let split = try XCTUnwrap(first.range(of: "</body></html>"))
        let reconstructed = "<html " + first[..<split.lowerBound] + first[split.upperBound...] + "</body></html>"
        let xml = try SafeXML.document(Data(reconstructed.utf8))
        let section = try XCTUnwrap(xml.nodes(forXPath: "//*[local-name()='section']").first as? XMLElement)
        XCTAssertEqual(section.attribute(forLocalName: "type", uri: "http://www.idpf.org/2007/ops")?.stringValue, "chapter")
    }
    func testProductionIdentifierIsStableAndProfileSpecific() throws {
        func identifier(_ data: Data) -> Data? {
            let exth = Int(data.be32(78)) + 280
            var cursor = exth + 12
            for _ in 0..<Int(data.be32(exth + 8)) {
                let count = Int(data.be32(cursor + 4))
                if data.be32(cursor) == 113 { return data.subdata(in: cursor + 8..<cursor + count) }
                cursor += count
            }
            return nil
        }
        let source = try fixture(), first = try AZW3Converter.convert(source).data
        XCTAssertEqual(first, try AZW3Converter.convert(source).data)
        XCTAssertNotEqual(identifier(first), try identifier(AZW3PrototypeWriter.convert(source)))
        XCTAssertNotNil(identifier(first).flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:)))
    }
    func testRejectsRemoteOrActiveCSS() throws {
        let archive = try ZIPArchive(data: fixture()), path = "Book/text/one.xhtml"
        let original = String(data: try archive.data(named: path), encoding: .utf8)!
        for css in ["@import 'https://example.com/style.css';", "p { background: url(https://example.com/x); }", "p { width: expression(alert(1)); }"] {
            let changed = original.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
            XCTAssertThrowsError(try AZW3Converter.convert(archive.writing(replacements: [path: Data(changed.utf8)])))
        }
    }
    func testValidatorRejectsTruncationAndInvalidIndexPointer() throws {
        let output = try AZW3Converter.convert(fixture()).data
        XCTAssertThrowsError(try AZW3Converter.validate(Data(output.prefix(100))))
        var damaged = output
        let header = Int(output.be32(78))
        damaged.replaceSubrange(header + 248..<header + 252, with: [255,255,255,254])
        XCTAssertThrowsError(try AZW3Converter.validate(damaged))
    }
}
