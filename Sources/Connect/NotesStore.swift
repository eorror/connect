import Foundation
import SwiftUI

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedThreadID: UUID?
    @Published var lastError: String?
    @Published var showSetup = false
    @Published private(set) var myName: String = UserDefaults.standard.string(forKey: "myName") ?? ""
    @Published private(set) var backend: Backend? = Backend.load()

    /// Called with all unread incoming notes whenever a new one shows up.
    var onIncoming: (([Note]) -> Void)?
    /// Lets the window say "I'm looking at this thread right now", so new replies count as read.
    var isViewingThread: ((UUID) -> Bool)?

    private var alerted: Set<UUID> = []
    private var timer: Timer?
    private var refreshing = false

    var isConfigured: Bool { backend != nil && !myName.isEmpty }

    var threads: [NoteThread] {
        let replies = Dictionary(grouping: notes.filter { $0.replyTo != nil }, by: { $0.replyTo! })
        return notes.filter { $0.replyTo == nil }
            .map { NoteThread(root: $0, replies: replies[$0.id] ?? []) }
            .sorted { $0.last.createdAt > $1.last.createdAt }
    }

    var unreadIncoming: [Note] { notes.filter { $0.sender != myName && $0.readAt == nil } }

    /// The other person's name, once they've written anything.
    var partnerName: String? { notes.last(where: { $0.sender != myName })?.sender }

    func isMine(_ note: Note) -> Bool { note.sender == myName }

    func unreadCount(in thread: NoteThread) -> Int {
        thread.all.filter { !isMine($0) && $0.readAt == nil }.count
    }

    func configure(name: String, backend: Backend) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "myName")
        backend.save()
        myName = trimmed
        self.backend = backend
        showSetup = false
        Task { await refresh() }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard let backend, !myName.isEmpty, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let fetched = try await NotesAPI(backend: backend).fetchNotes()
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
    func send(_ text: String, replyTo: UUID?) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let backend else { return false }
        let new = NewNote(id: UUID(), sender: myName, body: body, replyTo: replyTo)
        do {
            try await NotesAPI(backend: backend).insert(new)
        } catch {
            lastError = error.localizedDescription
            return false
        }
        notes.append(Note(id: new.id, createdAt: Date(), sender: myName, body: body, replyTo: replyTo, readAt: nil))
        selectedThreadID = replyTo ?? new.id
        lastError = nil
        Task { await refresh() }
        return true
    }

    func markThreadRead(_ threadID: UUID) {
        let ids = notes.filter { $0.threadID == threadID && !isMine($0) && $0.readAt == nil }.map(\.id)
        guard !ids.isEmpty, let backend else { return }
        let now = Date()
        for i in notes.indices where ids.contains(notes[i].id) { notes[i].readAt = now }
        Task {
            do { try await NotesAPI(backend: backend).markRead(ids) }
            catch { lastError = error.localizedDescription }
        }
    }
}
