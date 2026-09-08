import XCTest
@testable import SmallibreCore

final class ReaderProcessTests: XCTestCase, @unchecked Sendable {
    func testDeadlineStopsBlockedChild() async throws {
        let start = Date()
        do {
            _ = try await ReaderProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
            XCTFail("Must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testCancellationStopsChild() async throws {
        let task = Task { try await ReaderProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 20) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") } catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
    }
}

extension ReaderProcessTests {
    func testHelperScanAndBackedUpDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device"), local = root.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let file = device.appendingPathComponent("book.epub")
        try FileManager.default.copyItem(at: fixture, to: file)
        let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let connection = UUID()
        let scan = try await ReaderClient.perform(ReaderRequest(action: "scan", root: device, connection: connection, rootIdentity: nil, localRoot: local), executable: helper)
        let book = try XCTUnwrap(scan.books?.first)
        let result = try await ReaderClient.perform(ReaderRequest(action: "delete", root: device, connection: connection, rootIdentity: scan.rootIdentity, book: book, localRoot: local), executable: helper)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.file)), try Data(contentsOf: fixture))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

extension ReaderProcessTests {
    func testConcurrentHelperCannotStartUntilPreviousExits() async throws {
        let task = Task { try await ReaderProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 20) }
        try await Task.sleep(for: .milliseconds(100))
        do {
            _ = try await ReaderProcess.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
            XCTFail("Second helper must not start")
        } catch { XCTAssertTrue(error.localizedDescription.contains("previous reader operation")) }
        task.cancel(); _ = try? await task.value
    }
}

extension ReaderProcessTests {
    func testImmediateExitReturnsOutputRepeatedly() async throws {
        for _ in 0..<20 {
            let output = try await ReaderProcess.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["reader-output"], timeout: 2)
            XCTAssertEqual(String(decoding: output, as: UTF8.self), "reader-output\n")
        }
    }

    func testLaunchFailureDoesNotBlockNextHelper() async throws {
        do {
            _ = try await ReaderProcess.run(executable: URL(fileURLWithPath: "/nonexistent-smallibre-helper"), arguments: [])
            XCTFail("Missing executable must fail")
        } catch {}
        let output = try await ReaderProcess.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["recovered"])
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "recovered\n")
    }

    func testNonzeroExitReportsFailure() async throws {
        do {
            _ = try await ReaderProcess.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
            XCTFail("Unsuccessful helper must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("stopped unexpectedly")) }
    }
}
