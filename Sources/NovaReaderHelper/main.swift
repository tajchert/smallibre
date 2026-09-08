import Foundation
import NovaCore

@main struct ReaderHelper {
    static func main() async {
        let response: ReaderResponse
        do {
            guard CommandLine.arguments.count == 2 else { throw BookError.invalid("Missing reader request") }
            let request = try JSONDecoder().decode(ReaderRequest.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let store = ReaderStore(root: request.root, connection: request.connection, expectedRootIdentity: request.rootIdentity)
            switch request.action {
            case "scan": response = ReaderResponse(books: try await store.scan(cacheURL: !request.fullScan ? request.localRoot.appendingPathComponent("reader-cache.json") : nil), rootIdentity: store.rootIdentity)
            case "download":
                guard let book = request.book else { throw BookError.invalid("Missing book") }
                let library = try LibraryStore(root: request.localRoot)
                response = ReaderResponse(imported: try await store.download(book, into: library).book)
            case "delete":
                guard let book = request.book else { throw BookError.invalid("Missing book") }
                response = ReaderResponse(file: try await store.backupAndDelete(book, localRoot: request.localRoot))
            case "send":
                guard let id = request.libraryBookID else { throw BookError.invalid("Missing library book") }
                response = ReaderResponse(file: try await store.send(id, library: LibraryStore(root: request.localRoot), localRoot: request.localRoot))
            case "metadata":
                guard let book = request.book, let metadata = request.metadata else { throw BookError.invalid("Missing metadata") }
                response = ReaderResponse(file: try await store.updateMetadata(book, metadata: metadata, localRoot: request.localRoot))
            case "copy":
                guard let book = request.book else { throw BookError.invalid("Missing book") }
                response = ReaderResponse(file: try await store.downloadCopy(book, localRoot: request.localRoot))
            default: throw BookError.unsupported("Unsupported reader operation")
            }
        } catch { response = ReaderResponse(error: error.localizedDescription) }
        if let data = try? JSONEncoder().encode(response) { FileHandle.standardOutput.write(data) }
    }
}
