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
    var helper: URL { Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("SmallibreReaderHelper") }
    var hashes: Set<String> { Set(books.map(\.hash).filter { !$0.isEmpty }) }
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
                books = response.books ?? []; rootIdentity = response.rootIdentity
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
    func send(_ book: LibraryBook, destination: URL, model: AppModel) {
        guard libraryReady, !sleeping, !busy else { return }
        guard !needsRefreshAfterSleep else {
            error = "Refresh or reconnect the reader after sleep before sending. Check Backups & history before retrying an interrupted write."
            model.error = error; return
        }
        localRoot = model.root
        let token = begin("Sending and verifying book…")
        let request = ReaderRequest(action: "send", root: destination, connection: UUID(), rootIdentity: nil, localRoot: localRoot, libraryBookID: book.id)
        task = Task {
            defer { finish(token) }
            do {
                let result = try await ReaderClient.perform(request, executable: helper, timeout: 60)
                guard operationID == token else { return }
                status = "Sent and verified · \(result.file?.lastPathComponent ?? book.metadata.title)"
                model.status = status
            } catch is CancellationError {} catch { if operationID == token { self.error = error.localizedDescription; model.error = error.localizedDescription } }
        }
    }
    func download(_ book: ReaderBook, model: AppModel, edit: Bool = false) { run("download", books: [book], model: model, edit: edit) }
}
