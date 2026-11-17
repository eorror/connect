import Combine
import Foundation
import SwiftUI

@MainActor
final class NotesStore: ObservableObject {
    let auth: AuthManager

    @Published private(set) var notes: [Note] = []
    @Published var selectedThreadID: UUID?
    /// A just-arrived letter whose envelope should play opening when it's shown.
    @Published var envelopeToOpen: UUID?
    @Published var lastError: String?
    @Published var showSetup = false
    /// Panel screens: writing a fresh note, or the settings page.
    @Published var composing = false
    @Published var showSettings = false
    @Published private(set) var backend: Backend? = Backend.load()
    @Published private(set) var partnerEmail: String = UserDefaults.standard.string(forKey: "partnerEmail") ?? ""

    /// Called with all unread incoming notes whenever a new one shows up.
    var onIncoming: (([Note]) -> Void)?
    /// Lets the window say "I'm looking at this thread right now", so new replies count as read.
    var isViewingThread: ((UUID) -> Bool)?

    private var alerted: Set<UUID> = []
    private var timer: Timer?
    private var refreshing = false
    private var cancellables = Set<AnyCancellable>()

    init(auth: AuthManager) {
        self.auth = auth
        // Re-render views when the sign-in state changes; drop notes on sign-out.
        auth.$session
            .removeDuplicates { $0?.email == $1?.email }
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.notes = []
                self.alerted = []
                self.selectedThreadID = nil
                Task { await self.refresh() }
            }
            .store(in: &cancellables)
        auth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var myEmail: String { auth.session?.email ?? "" }
    var myName: String { auth.session?.name ?? "" }
    var isSignedIn: Bool { auth.session != nil }
    var isConfigured: Bool { backend != nil && isSignedIn && !partnerEmail.isEmpty }

    var threads: [NoteThread] {
        let replies = Dictionary(grouping: notes.filter { $0.replyTo != nil }, by: { $0.replyTo! })
        return notes.filter { $0.replyTo == nil }
            .map { NoteThread(root: $0, replies: replies[$0.id] ?? []) }
            .sorted { $0.last.createdAt > $1.last.createdAt }
    }

    var unreadIncoming: [Note] { notes.filter { !isMine($0) && $0.readAt == nil } }

    /// The other person's name once they've written, otherwise their email.
    var partnerName: String {
        notes.last(where: { !isMine($0) })?.senderName ?? partnerEmail
    }

    /// Debug only (CONNECT_PREVIEW): a local, unsent letter from the partner, to check the look.
    func injectPreviewLetter(paper: Paper) {
        notes.append(previewLetter(paper: paper))
    }

    func previewLetter(paper: Paper) -> Note {
        Note(id: UUID(), createdAt: Date(), senderEmail: partnerEmail, senderName: partnerName,
                          recipientEmail: myEmail,
                          body: paper.token + "\n[doodle:\(Self.previewDoodle)]\nMissing you already. Dinner tonight? I'll bring the good bread x",
                          replyTo: nil, readAt: nil)
    }

    /// A heart and a little sun, encoded the way a real drawing travels.
    private static var previewDoodle: String {
        let heart: [CGPoint] = stride(from: 0.0, through: 2 * .pi, by: 0.2).map { t in
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return CGPoint(x: 860 + x * 4.2, y: 120 - y * 4.2)
        }
        let sun: [CGPoint] = stride(from: 0.0, through: 2 * .pi + 0.3, by: 0.35).map { t in
            CGPoint(x: 700 + cos(t) * 28, y: 80 + sin(t) * 28)
        }
        var rays: [[CGPoint]] = []
        for i in 0..<8 {
            let t = Double(i) * .pi / 4
            rays.append([CGPoint(x: 700 + cos(t) * 45, y: 80 + sin(t) * 45),
                         CGPoint(x: 700 + cos(t) * 65, y: 80 + sin(t) * 65)])
        }
        let squiggle: [CGPoint] = stride(from: 0.0, through: 1.0, by: 0.05).map { u in
            CGPoint(x: 80 + u * 420, y: 860 + sin(u * 14) * 18)
        }
        return Doodle.encode([heart, sun] + rays + [squiggle])
    }

    func isMine(_ note: Note) -> Bool { note.senderEmail == myEmail }

    func unreadCount(in thread: NoteThread) -> Int {
        thread.all.filter { !isMine($0) && $0.readAt == nil }.count
    }

    // MARK: Setup

    func setBackend(_ b: Backend) {
        b.save()
        backend = b
    }

    func setPartner(_ email: String) {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        UserDefaults.standard.set(e, forKey: "partnerEmail")
        partnerEmail = e
        notes = []
        alerted = []
        selectedThreadID = nil
        Task { await refresh() }
    }

    // MARK: Sync

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    /// Runs a request with a fresh token; if the server rejects it, refreshes once and retries.
    private func withAPI<T>(_ op: (NotesAPI) async throws -> T) async throws -> T {
        guard let backend else { throw APIError(message: "No server set up") }
        let token = try await auth.validAccessToken(backend: backend)
        do {
            return try await op(NotesAPI(backend: backend, accessToken: token))
        } catch let e as APIError where e.status == 401 {
            auth.expireNow()
            let retry = try await auth.validAccessToken(backend: backend)
            return try await op(NotesAPI(backend: backend, accessToken: retry))
        }
    }

    func refresh() async {
        guard isConfigured, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let me = myEmail, partner = partnerEmail
        do {
            let fetched = try await withAPI { try await $0.fetchNotes(me: me, partner: partner) }
            guard me == myEmail, partner == partnerEmail else { return }   // account changed mid-request
            if fetched != notes { notes = fetched }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }

        // New replies in the thread that's open on screen are read immediately.
        if let viewing = selectedThreadID, isViewingThread?(viewing) == true {
            markThreadRead(viewing)
        }

        let unread = unreadIncoming
        let fresh = unread.filter { !alerted.contains($0.id) }
        if !fresh.isEmpty {
            fresh.forEach { alerted.insert($0.id) }
            onIncoming?(unread)
        }
    }

    @discardableResult
    func send(_ text: String, replyTo: UUID?, openAfter: Bool = true) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, isConfigured else { return false }
        let new = NewNote(id: UUID(), senderEmail: myEmail, senderName: myName,
                          recipientEmail: partnerEmail, body: body, replyTo: replyTo)
        do {
            try await withAPI { try await $0.insert(new) }
        } catch {
            lastError = error.localizedDescription
            return false
        }
        notes.append(Note(id: new.id, createdAt: Date(), senderEmail: new.senderEmail, senderName: new.senderName,
                          recipientEmail: new.recipientEmail, body: body, replyTo: replyTo, readAt: nil))
        if openAfter {
            composing = false
            selectedThreadID = replyTo ?? new.id
        }
        lastError = nil
        Task { await refresh() }
        return true
    }

    func markThreadRead(_ threadID: UUID) {
        let ids = notes.filter { $0.threadID == threadID && !isMine($0) && $0.readAt == nil }.map(\.id)
        guard !ids.isEmpty else { return }
        let now = Date()
        for i in notes.indices where ids.contains(notes[i].id) { notes[i].readAt = now }
        Task {
            do { try await withAPI { try await $0.markRead(ids) } }
            catch { lastError = error.localizedDescription }
        }
    }
}
