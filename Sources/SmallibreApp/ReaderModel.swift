import SwiftUI
import AppKit
import Combine
import SmallibreCore

@MainActor @Observable final class ReaderModel {
    var libraryReady = false
    var books: [ReaderBook] = []
    var generation = UUID()
    var folder: URL?
    var busy = false
    var error: String?
    var status: String?
    var task: Task<Void, Never>?
    var progress = 0.0
    var receipts: [ReaderReceipt] = []
    var rootIdentity: String?
    @ObservationIgnored private var workspaceSubscriptions = Set<AnyCancellable>()
    private var sleeping = false
    private var needsRefreshAfterSleep = false
    private var interruptedBySleep = false
    private var operationID = UUID()
    var localRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Smallibre")
    var helper: URL = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("SmallibreReaderHelper")
    private var sentFiles: [URL: Date] = [:]
    var hashes: Set<String> { Set(books.map(\.hash).filter { !$0.isEmpty }) }
    enum LibraryMatch: Equatable { case original, converted }
    /// Display-only provenance association; device mutations still use scanned identities and hashes.
    func libraryMatch(_ book: LibraryBook, deviceHash: String) -> LibraryMatch? {
        guard !deviceHash.isEmpty else { return nil }
        if book.hash == deviceHash { return .original }
        return receipts.contains { receipt in
            guard let transfer = receipt.transfer, transfer.state == .verified else { return false }
            let artifact = transfer.artifact
            return artifact.outputSHA256.value == deviceHash &&
                artifact.provenance.sourceLibraryID == book.id &&
                artifact.provenance.sourceOriginalSHA256.value == book.hash
        } ? .converted : nil
    }
    func deviceMatch(_ book: LibraryBook) -> LibraryMatch? {
        if hashes.contains(book.hash) { return .original }
        return books.contains { libraryMatch(book, deviceHash: $0.hash) == .converted } ? .converted : nil
    }
    func libraryBook(deviceHash: String?, library: [LibraryBook]) -> LibraryBook? {
        guard let deviceHash, !deviceHash.isEmpty else { return nil }
        return library.first { libraryMatch($0, deviceHash: deviceHash) == .original }
            ?? library.first { libraryMatch($0, deviceHash: deviceHash) == .converted }
    }
    func libraryLabel(for item: ReaderBook, library: [LibraryBook]) -> String {
        if library.contains(where: { libraryMatch($0, deviceHash: item.hash) == .original }) { return "In library" }
        return library.contains(where: { libraryMatch($0, deviceHash: item.hash) == .converted }) ? "Converted copy" : "On device"
    }
    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        notificationCenter.publisher(for: NSWorkspace.didMountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL { self?.mounted(url) }
            }.store(in: &workspaceSubscriptions)
        notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL { self?.disconnected(url) }
            }.store(in: &workspaceSubscriptions)
        notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.systemWillSleep() }.store(in: &workspaceSubscriptions)
        notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.systemDidWake() }.store(in: &workspaceSubscriptions)
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose Kindle documents folder"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url { connect(url) }
    }
    func discover() {
        guard libraryReady, !sleeping, !needsRefreshAfterSleep, !busy else { return }
        // Existence and directory scanning are delegated to the helper, never to the UI thread.
        connect(URL(fileURLWithPath: "/Volumes/Kindle/documents"))
    }
    func mounted(_ volume: URL) {
        guard libraryReady, !sleeping, !needsRefreshAfterSleep, !busy else { return }
        let path = volume.standardizedFileURL.path
        if let folder {
            let selected = folder.standardizedFileURL.path
            guard selected == path || selected.hasPrefix(path + "/") else { return }
            connect(folder)
        } else if path == "/Volumes/Kindle" {
            discover()
        }
    }
    func systemWillSleep() {
        guard !sleeping else { return }
        sleeping = true
        interruptedBySleep = interruptedBySleep || busy
        needsRefreshAfterSleep = needsRefreshAfterSleep || busy || folder != nil
        task?.cancel(); task = nil; operationID = UUID(); busy = false
        generation = UUID(); rootIdentity = nil; books = []
        if needsRefreshAfterSleep { status = "Reader paused for system sleep. Refresh after waking." }
    }
    func systemDidWake() {
        guard sleeping else { return }
        sleeping = false
        if needsRefreshAfterSleep {
            status = "Refresh the reader before continuing." +
                (interruptedBySleep ? " Writes may have finished; check Backups & history before retrying." : "")
        }
    }
    func connect(_ url: URL) {
        guard libraryReady, !sleeping else { return }
        cancel(); generation = UUID(); folder = url; rootIdentity = nil; books = []; refresh()
    }
    func refresh(full: Bool = false) {
        guard libraryReady, !sleeping, !busy, let folder else { return }
        let request = ReaderRequest(action: "scan", root: folder, connection: generation, rootIdentity: rootIdentity, localRoot: localRoot, fullScan: full)
        let token = begin("Reading device books…")
        task = Task {
            defer { finish(token) }
            do {
                let response = try await ReaderClient.perform(request, executable: helper)
                guard operationID == token else { return }
                books = ordered(response.books ?? [], at: folder); rootIdentity = response.rootIdentity
                needsRefreshAfterSleep = false; interruptedBySleep = false
                status = "\(books.count) books · refreshed just now"
            } catch is CancellationError {} catch {
                guard operationID == token else { return }
                books = []; rootIdentity = nil; generation = UUID(); self.error = error.localizedDescription
                status = "Scan stopped. Reconnect if needed, then Refresh."
            }
        }
    }
    func cancel() {
        task?.cancel(); task = nil; operationID = UUID(); busy = false
        status = "Stopped. Writes may have finished; refresh and check Backups & history before retrying."
        reloadHistory()
    }
    func disconnected(_ url: URL) {
        guard let folder, folder.path.hasPrefix(url.path + "/") else { return }
        cancel(); generation = UUID(); books = []; self.folder = nil; rootIdentity = nil; status = "Kindle disconnected"
    }
    private func begin(_ message: String) -> UUID {
        let token = UUID(); operationID = token; busy = true; progress = 0; status = message; error = nil; return token
    }
    private func finish(_ token: UUID) { if operationID == token { busy = false; task = nil; reloadHistory() } }
    func reloadHistory() { receipts = ReaderReceipt.list(localRoot: localRoot) }
    func run(_ action: String, books selected: [ReaderBook], model: AppModel, metadata: BookMetadata? = nil, edit: Bool = false) {
        guard libraryReady, !sleeping, !busy, let folder, rootIdentity != nil else { return }
        localRoot = model.root
        let connection = generation, identity = rootIdentity
        let token = begin("Starting device operation…")
        task = Task {
            var done = 0, failures: [String] = []
            defer { finish(token) }
            for book in selected {
                if Task.isCancelled || operationID != token { return }
                status = "\(action.capitalized) · \(done + failures.count + 1) of \(selected.count) · \(book.title)"
                do {
                    let request = ReaderRequest(action: action, root: folder, connection: connection, rootIdentity: identity, book: book, localRoot: localRoot, metadata: metadata)
                    let result = try await ReaderClient.perform(request, executable: helper)
                    guard operationID == token else { return }
                    if let imported = result.imported {
                        await model.reload(); model.selection = imported.id
                        if edit { model.editing = imported }
                    }
                    if action == "delete" { books.removeAll { $0.id == book.id } }
                    done += 1; progress = Double(done + failures.count) / Double(selected.count)
                } catch is CancellationError { return }
                catch {
                    failures.append("\(book.title): \(error.localizedDescription)")
                    // Stop at the first error: remaining items have not been touched.
                    break
                }
            }
            guard operationID == token else { return }
            status = "\(done) completed" + (failures.isEmpty ? "" : " · stopped on an error; remaining books unchanged")
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
            if action == "metadata", done > 0 { finish(token); refresh(full: true) }
        }
    }
    /// One user action owns discovery, conversion and transfer. Only discovery failure
    /// opens the manual fallback; conversion/write failures must never replay a send.
    func sendToDevice(_ book: LibraryBook, model: AppModel) {
        guard libraryReady, !sleeping, !busy, model.operation == nil, deviceMatch(book) == nil, let store = model.store else { return }
        guard !needsRefreshAfterSleep else {
            model.error = "Refresh or reconnect the reader after sleep before sending. Check Backups & history before retrying an interrupted write."
            return
        }
        guard ["EPUB", "MOBI", "AZW3"].contains(book.metadata.format) else {
            model.transferBook = book
            return
        }
        localRoot = model.root
        let destination = folder ?? URL(fileURLWithPath: "/Volumes/Kindle/documents")
        let connection = generation, expectedIdentity = rootIdentity
        let token = begin("Checking connected Kindle…")
        model.error = nil
        task = Task {
            defer { finish(token) }
            let identity: String
            do {
                try Task.checkCancellation()
                guard operationID == token else { return }
                let response = try await ReaderClient.perform(
                    ReaderRequest(action: "scan", root: destination, connection: connection,
                                  rootIdentity: expectedIdentity, localRoot: localRoot), executable: helper)
                try Task.checkCancellation()
                guard operationID == token else { return }
                guard let verifiedIdentity = response.rootIdentity else { throw BookError.invalid("Device identity unavailable") }
                identity = verifiedIdentity
                folder = destination; rootIdentity = identity; books = ordered(response.books ?? [], at: destination)
                reloadHistory()
                if deviceMatch(book) != nil { status = "Already on device"; return }
            } catch is CancellationError { return }
            catch {
                guard operationID == token else { return }
                self.error = "Could not access the Kindle automatically. Connect it and choose its books folder. " + error.localizedDescription
                model.transferBook = book
                return
            }
            do {
                var artifact: PreparedBookArtifact?
                if book.metadata.format == "EPUB" {
                    status = "Preparing Kindle copy…"
                    artifact = try await store.prepareKindleArtifact(for: book.id)
                }
                try Task.checkCancellation()
                guard operationID == token else { return }
                status = "Sending and verifying book…"
                let request = ReaderRequest(action: artifact == nil ? "send" : "sendArtifact",
                    root: destination, connection: connection, rootIdentity: identity,
                    localRoot: localRoot, libraryBookID: book.id, preparedArtifact: artifact)
                let result = try await ReaderClient.perform(request, executable: helper, timeout: 60)
                guard operationID == token else { return }
                status = "Sent and verified · \(result.file?.lastPathComponent ?? book.metadata.title)"
                if let artifact, !artifact.warnings.isEmpty {
                    status = (status ?? "Sent and verified") + " · Conversion notes are saved in Backups & history."
                }
                model.status = status
                await refreshAfterSend(result, destination: destination, connection: connection, identity: identity, token: token)
            } catch is CancellationError {} catch {
                guard operationID == token else { return }
                self.error = error.localizedDescription; model.error = error.localizedDescription
            }
        }
    }
    func send(_ book: LibraryBook, destination: URL, model: AppModel, artifact: PreparedBookArtifact? = nil) {
        guard libraryReady, !sleeping, !busy else { return }
        guard !needsRefreshAfterSleep else {
            error = "Refresh or reconnect the reader after sleep before sending. Check Backups & history before retrying an interrupted write."
            model.error = error; return
        }
        if let artifact, artifact.provenance.sourceLibraryID != book.id {
            model.error = "The prepared Kindle copy belongs to a different book."; return
        }
        localRoot = model.root
        let token = begin("Sending and verifying book…")
        let connection = UUID()
        let request = ReaderRequest(action: artifact == nil ? "send" : "sendArtifact", root: destination, connection: connection, rootIdentity: nil, localRoot: localRoot, libraryBookID: book.id, preparedArtifact: artifact)
        task = Task {
            defer { finish(token) }
            do {
                try Task.checkCancellation()
                guard operationID == token else { return }
                let result = try await ReaderClient.perform(request, executable: helper, timeout: 60)
                guard operationID == token else { return }
                status = "Sent and verified · \(result.file?.lastPathComponent ?? book.metadata.title)"
                model.status = status
                await refreshAfterSend(result, destination: destination, connection: connection, identity: nil, token: token)
            } catch is CancellationError {} catch { if operationID == token { self.error = error.localizedDescription; model.error = error.localizedDescription } }
        }
    }
    private func ordered(_ scanned: [ReaderBook], at root: URL) -> [ReaderBook] {
        scanned.sorted {
            let left = sentFiles[root.appendingPathComponent($0.relativePath).standardizedFileURL] ?? .distantPast
            let right = sentFiles[root.appendingPathComponent($1.relativePath).standardizedFileURL] ?? .distantPast
            if left != right { return left > right }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    private func refreshAfterSend(_ result: ReaderResponse, destination: URL, connection: UUID, identity: String?, token: UUID) async {
        guard operationID == token else { return }
        if folder != destination || generation != connection { books = [] }
        folder = destination; generation = connection; rootIdentity = identity
        if let file = result.file { sentFiles[file.standardizedFileURL] = Date() }
        reloadHistory()
        do {
            let response = try await ReaderClient.perform(
                ReaderRequest(action: "scan", root: destination, connection: connection,
                              rootIdentity: identity, localRoot: localRoot), executable: helper)
            guard operationID == token else { return }
            folder = destination; generation = connection; rootIdentity = response.rootIdentity
            books = ordered(response.books ?? [], at: destination)
        } catch is CancellationError {} catch {
            guard operationID == token else { return }
            self.error = "The book was sent and verified, but the device list could not refresh. Refresh the reader before sending again. " + error.localizedDescription
        }
    }
    func download(_ book: ReaderBook, model: AppModel, edit: Bool = false) { run("download", books: [book], model: model, edit: edit) }
}
