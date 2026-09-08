import Foundation
import CSQLite

/// Owned exclusively by LibraryStore's actor. SQLite's serialized mode also protects initialization/destruction.
final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw BookError.invalid("Could not open the library database.")
        }
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("CREATE TABLE IF NOT EXISTS books (id TEXT PRIMARY KEY, hash TEXT UNIQUE NOT NULL, payload BLOB NOT NULL, title TEXT NOT NULL, authors TEXT NOT NULL, added REAL NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS books_title ON books(title COLLATE NOCASE)")
        try execute("PRAGMA user_version=1")
    }
    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> BookError { .invalid("Library database: \(String(cString: sqlite3_errmsg(handle)))") }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &result, nil) == SQLITE_OK, let result else { throw failure() }
        return result
    }
    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    func save(_ book: LibraryBook, insert: Bool) throws {
        let query = try statement(insert ? "INSERT INTO books(id,hash,payload,title,authors,added) VALUES(?,?,?,?,?,?)" : "UPDATE books SET hash=?2,payload=?3,title=?4,authors=?5,added=?6 WHERE id=?1")
        defer { sqlite3_finalize(query) }
        bind(book.id.uuidString, at: 1, to: query); bind(book.hash, at: 2, to: query)
        let payload = try JSONEncoder().encode(book)
        _ = payload.withUnsafeBytes { sqlite3_bind_blob(query, 3, $0.baseAddress, Int32(payload.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        bind(book.metadata.title, at: 4, to: query); bind(book.metadata.authors.joined(separator: ", "), at: 5, to: query)
        sqlite3_bind_double(query, 6, book.addedAt.timeIntervalSince1970)
        guard sqlite3_step(query) == SQLITE_DONE else { throw failure() }
    }
    func books(matching search: String = "") throws -> [LibraryBook] {
        let query = try statement("SELECT payload FROM books WHERE instr(lower(title || ' ' || authors), lower(?)) > 0 ORDER BY added DESC, id")
        defer { sqlite3_finalize(query) }
        bind(search, at: 1, to: query)
        var result: [LibraryBook] = []
        while true {
            let status = sqlite3_step(query)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(query, 0) else { throw failure() }
            result.append(try JSONDecoder().decode(LibraryBook.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))))
        }
    }
    func book(column: String, value: String) throws -> LibraryBook? {
        precondition(column == "id" || column == "hash")
        let query = try statement("SELECT payload FROM books WHERE \(column)=?")
        defer { sqlite3_finalize(query) }
        bind(value, at: 1, to: query)
        let status = sqlite3_step(query)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(query, 0) else { throw failure() }
        return try JSONDecoder().decode(LibraryBook.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0))))
    }
}
