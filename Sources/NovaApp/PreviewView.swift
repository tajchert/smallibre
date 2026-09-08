import SwiftUI
import WebKit
import NovaCore

struct PreviewView: View {
    let content: PreviewContent
    @State private var chapter = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(content.title).font(.system(size: 17, design: .serif)); Text("Reading preview").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { chapter = max(0, chapter - 1) } label: { Image(systemName: "chevron.left") }.disabled(chapter == 0).help("Previous chapter")
                Picker("Chapter", selection: $chapter) { ForEach(content.epub.chapters.indices, id: \.self) { Text("Chapter \($0 + 1)").tag($0) } }.labelsHidden().frame(width: 140)
                Button { chapter = min(content.epub.chapters.count - 1, chapter + 1) } label: { Image(systemName: "chevron.right") }.disabled(chapter == content.epub.chapters.count - 1).help("Next chapter")
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).padding(.leading, 14)
            }.padding(18)
            Divider()
            BookWebView(epub: content.epub, chapter: chapter)
            Divider()
            Text("Your reader’s settings may change the final appearance.").font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
        }.frame(width: 830, height: 680).background(NovaTheme.canvas)
    }
}

private struct BookWebView: NSViewRepresentable {
    let epub: EPUBBook
    let chapter: Int
    func makeCoordinator() -> Coordinator { Coordinator(epub: epub) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "nova-book")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.chapter != chapter else { return }
        context.coordinator.chapter = chapter
        view.load(URLRequest(url: URL(string: "nova-book://book/")!.appendingPathComponent(epub.chapters[chapter])))
    }
    @MainActor final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        let epub: EPUBBook
        var chapter: Int?
        init(epub: EPUBBook) { self.epub = epub }
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url, url.host == "book" else { urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return }
            let path = String(url.path.dropFirst())
            do {
                var data = try epub.archive.data(named: path)
                let ext = url.pathExtension.lowercased()
                let mime: String
                switch ext {
                case "xhtml", "html", "htm":
                    data = try PreviewSanitizer.html(data)
                    mime = "text/html"
                case "css": mime = "text/css"
                case "jpg", "jpeg": mime = "image/jpeg"
                case "png": mime = "image/png"
                case "gif": mime = "image/gif"
                case "svg": mime = "image/svg+xml"
                case "woff": mime = "font/woff"
                case "woff2": mime = "font/woff2"
                case "ttf": mime = "font/ttf"
                case "otf": mime = "font/otf"
                default: mime = "application/octet-stream"
                }
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime == "text/html" ? "utf-8" : nil))
                urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
            } catch { urlSchemeTask.didFailWithError(error) }
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "nova-book" && url?.host == "book" ? .allow : .cancel)
        }
    }
}
