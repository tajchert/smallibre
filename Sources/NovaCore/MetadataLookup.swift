import Foundation

public struct MetadataCandidate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let authors: [String]
    public let firstPublished: Int?
}

public actor MetadataLookup {
    private var lastRequest = Date.distantPast
    private var cache: [String: [MetadataCandidate]] = [:]
    public init() {}
    public func search(title: String, author: String) async throws -> [MetadataCandidate] {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !title.isEmpty else { return [] }
        let author = String(author.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let key = title + "\n" + author
        if let value = cache[key] { return value }
        let delay = max(0, 1.1 - Date().timeIntervalSince(lastRequest))
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastRequest = Date()
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "limit", value: "8"), URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year")]
        if !author.isEmpty { components.queryItems?.append(URLQueryItem(name: "author", value: author)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("CalibreNova/0.1", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: MetadataRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw BookError.invalid("Open Library is unavailable or busy. Try again later; your library is unchanged.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw BookError.invalid("The metadata response exceeded the size limit.") }
            data.append(byte)
        }
        let result = try Self.decode(data)
        if cache.count >= 100 { cache.removeAll() }
        cache[key] = result
        return result
    }
    public static func decode(_ data: Data) throws -> [MetadataCandidate] {
        guard data.count <= 2_000_000 else { throw BookError.invalid("The metadata response exceeded the size limit.") }
        struct Response: Decodable { let docs: [Document] }
        struct Document: Decodable { let key: String?; let title: String?; let author_name: [String]?; let first_publish_year: Int? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        return response.docs.prefix(20).compactMap { document in
            guard let key = document.key, let title = document.title, !title.isEmpty, seen.insert(key).inserted else { return nil }
            return MetadataCandidate(id: key, title: String(title.prefix(500)), authors: (document.author_name ?? []).prefix(20).map { String($0.prefix(200)) }, firstPublished: document.first_publish_year)
        }
    }
}

private final class MetadataRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "openlibrary.org" ? request : nil)
    }
}
