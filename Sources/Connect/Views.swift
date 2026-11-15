import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        Group {
            if store.isConfigured && !store.showSetup {
                MainView()
            } else {
                SetupView()
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var store: NotesStore
    @State private var name = UserDefaults.standard.string(forKey: "myName") ?? ""
    @State private var pairingCode = ""
    @State private var url = Backend.load()?.url ?? ""
    @State private var key = Backend.load()?.key ?? ""
    @State private var showManual = Backend.load() != nil
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)
            Text("Set up Connect").font(.title2.bold())

            Form {
                TextField("Your name", text: $name, prompt: Text("What should your notes say they're from?"))
                TextField("Pairing code", text: $pairingCode, prompt: Text("Paste the code you were sent"))
                DisclosureGroup("Server URL and key instead", isExpanded: $showManual) {
                    TextField("Supabase URL", text: $url, prompt: Text("https://xxxx.supabase.co"))
                    TextField("Key", text: $key, prompt: Text("anon / publishable key"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 460)

            if let error {
                Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center)
            }

            HStack {
                if store.isConfigured {
                    Button("Cancel") { store.showSetup = false }
                }
                Button(checking ? "Connecting…" : "Connect") { Task { await connect() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
    }

    private func connect() async {
        error = nil
        let backend: Backend
        if !pairingCode.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let b = Backend(pairingCode: pairingCode) else { error = "That pairing code doesn't look right."; return }
            backend = b
        } else if !url.isEmpty, !key.isEmpty {
            backend = Backend(url: url, key: key)
        } else {
            error = "Paste a pairing code, or enter the server URL and key."
            return
        }
        checking = true
        defer { checking = false }
        do {
            _ = try await NotesAPI(backend: backend).fetchNotes()
            store.configure(name: name, backend: backend)
        } catch {
            self.error = "Couldn't reach the notes server: \(error.localizedDescription)"
        }
    }
}

// MARK: - Main

struct MainView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedThreadID) {
                ForEach(store.threads) { thread in
                    ThreadRow(thread: thread).tag(thread.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if store.threads.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "heart.text.square",
                                           description: Text("Write the first one."))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let err = store.lastError {
                    Label(err, systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(8)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { store.selectedThreadID = nil } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n")
                    .help("New note (⌘N)")
                }
            }
        } detail: {
            if let id = store.selectedThreadID, let thread = store.threads.first(where: { $0.id == id }) {
                ThreadView(thread: thread).id(id)
            } else {
                ComposeView()
            }
        }
        .onChange(of: store.selectedThreadID) { _, id in
            if let id { store.markThreadRead(id) }
        }
    }
}

struct ThreadRow: View {
    @EnvironmentObject var store: NotesStore
    let thread: NoteThread

    var body: some View {
        let unread = store.unreadCount(in: thread)
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(unread > 0 ? Color.pink : .clear).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(store.isMine(thread.root) ? "You" : thread.root.sender)
                        .font(.headline)
                    Spacer()
                    Text(thread.last.createdAt, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(thread.root.body).lineLimit(2).font(.callout).foregroundStyle(.secondary)
                if !thread.replies.isEmpty {
                    Text("\(thread.replies.count) \(thread.replies.count == 1 ? "reply" : "replies")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thread

struct ThreadView: View {
    @EnvironmentObject var store: NotesStore
    let thread: NoteThread
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(thread.all) { note in
                            NoteBubble(note: note, isRoot: note.id == thread.root.id,
                                       showSeen: note.id == lastMine?.id)
                                .id(note.id)
                        }
                    }
                    .padding(20)
                }
                .onAppear { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                .onChange(of: thread.replies.count) { _, _ in
                    withAnimation { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                }
            }
            Divider()
            replyBar
        }
        .navigationTitle(store.isMine(thread.root) ? "Your note" : "Note from \(thread.root.sender)")
    }

    private var lastMine: Note? { thread.all.last(where: { store.isMine($0) }) }

    private var replyBar: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Write a reply…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            HStack {
                Button("Send as New Note") { send(asReply: false) }
                    .help("Starts a new note instead of replying in this one")
                Button("Reply") { send(asReply: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Reply (⌘↩)")
            }
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
    }

    private func send(asReply: Bool) {
        let text = draft
        sending = true
        Task {
            if await store.send(text, replyTo: asReply ? thread.root.id : nil) { draft = "" }
            sending = false
        }
    }
}

struct NoteBubble: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    let isRoot: Bool
    let showSeen: Bool

    var body: some View {
        let mine = store.isMine(note)
        HStack {
            if mine { Spacer(minLength: 60) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text("\(mine ? "You" : note.sender) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(note.body)
                    .font(isRoot ? .title3 : .body)
                    .textSelection(.enabled)
                    .padding(isRoot ? 16 : 10)
                    .foregroundStyle(isRoot ? Color.black.opacity(0.85) : (mine ? .white : .primary))
                    .background(background(mine: mine), in: RoundedRectangle(cornerRadius: isRoot ? 6 : 14))
                    .shadow(color: isRoot ? .black.opacity(0.12) : .clear, radius: 4, y: 2)
                if showSeen && note.readAt != nil {
                    Text("Seen").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !mine { Spacer(minLength: 60) }
        }
    }

    private func background(mine: Bool) -> Color {
        if isRoot { return Color(red: 1.0, green: 0.95, blue: 0.70) }   // sticky-note yellow
        return mine ? .pink : Color.secondary.opacity(0.15)
    }
}

// MARK: - Compose

struct ComposeView: View {
    @EnvironmentObject var store: NotesStore
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.partnerName.map { "New note for \($0)" } ?? "New note")
                .font(.title2.bold())
            TextEditor(text: $draft)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(Color(red: 1.0, green: 0.95, blue: 0.70), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color.black.opacity(0.85))
                .focused($focused)
            HStack {
                Spacer()
                Button(sending ? "Sending…" : "Send Note") {
                    sending = true
                    Task {
                        if await store.send(draft, replyTo: nil) { draft = "" }
                        sending = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .navigationTitle("New Note")
        .onAppear { focused = true }
    }
}

// MARK: - Side popup

struct PopupView: View {
    let notes: [Note]
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let latest = notes.last!
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 30))
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 3) {
                Text(notes.count > 1 ? "\(notes.count) new notes from \(latest.sender)" : "New note from \(latest.sender)")
                    .font(.headline)
                Text(latest.body).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Text("Click to open and reply").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(14)
        .frame(width: 330, height: 100, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.pink.opacity(0.35)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onOpen)
    }
}
