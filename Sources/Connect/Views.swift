import AuthenticationServices
import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.isConfigured && !store.showSetup {
                MainView()
            } else {
                SetupView()
            }
        }
        .foregroundStyle(Theme.ink)
        .font(Theme.sans(14))
        .frame(minWidth: 760, minHeight: 500)
    }
}

/// "Connect" wordmark in italic serif, with today's date beside it (as Cairn does with Desk).
struct Wordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Connect").font(Theme.serif(28, italic: true))
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Theme.sans(13)).foregroundStyle(Theme.ink3)
        }
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var store: NotesStore
    @State private var partner = UserDefaults.standard.string(forKey: "partnerEmail") ?? ""
    @State private var url = Backend.load()?.url ?? ""
    @State private var key = Backend.load()?.key ?? ""
    @State private var showServer = Backend.builtIn == nil
    @State private var error: String?
    @State private var busy = false

    private var partnerValid: Bool {
        let p = partner.trimmingCharacters(in: .whitespaces).lowercased()
        return p.contains("@") && p.contains(".") && p != store.myEmail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect").font(Theme.serif(40, italic: true))
                Text("Little notes between two laptops.").foregroundStyle(Theme.ink2)
            }

            if showServer {
                SetupSection("Server") {
                    ThemedField("Supabase URL", text: $url, prompt: "https://xxxx.supabase.co")
                    ThemedField("Key", text: $key, prompt: "publishable / anon key")
                }
            }

            SetupSection("Your account") {
                if let s = store.auth.session {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.mineTint).frame(width: 34, height: 34)
                            .overlay(Text(String(s.name.prefix(1))).font(Theme.sans(14, .semibold)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(Theme.sans(14, .semibold))
                            Text(s.email).font(Theme.sans(12)).foregroundStyle(Theme.ink3)
                        }
                        Spacer()
                        Button("Sign out") { store.auth.signOut() }.buttonStyle(.pillSecondary)
                    }
                } else {
                    Button { Task { await signIn() } } label: {
                        Label(busy ? "Waiting for Google…" : "Sign in with Google",
                              systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill)
                    .disabled(busy)
                }
            }

            SetupSection("Who are you writing to?") {
                ThemedField("Their Google email", text: $partner, prompt: "name@gmail.com")
            }

            if let error {
                Text(error).font(Theme.sans(12)).foregroundStyle(Color(red: 0.70, green: 0.23, blue: 0.15))
            }

            HStack {
                Spacer()
                if store.isConfigured {
                    Button("Cancel") { store.showSetup = false }.buttonStyle(.pillSecondary)
                }
                Button("Done") { finish() }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.isSignedIn || !partnerValid)
            }
        }
        .padding(30)
        .frame(width: 440)
        .glassCard(radius: 24)
        .padding(30)
    }

    private func currentBackend() -> Backend? {
        if showServer {
            guard url.hasPrefix("http"), !key.isEmpty else { return nil }
            return Backend(url: url, key: key)
        }
        return store.backend
    }

    private func signIn() async {
        error = nil
        guard let backend = currentBackend() else {
            error = "Enter the Supabase URL and key first."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await store.auth.signInWithGoogle(backend: backend)
            if showServer { store.setBackend(backend) }
        } catch {
            let ns = error as NSError
            if ns.domain == ASWebAuthenticationSessionErrorDomain,
               ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
            self.error = error.localizedDescription
        }
    }

    private func finish() {
        if showServer, let b = currentBackend(), b != store.backend { store.setBackend(b) }
        store.setPartner(partner)
        store.showSetup = false
    }
}

struct SetupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Theme.sans(11, .semibold)).tracking(0.6).foregroundStyle(Theme.ink3)
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}

struct ThemedField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    init(_ label: String, text: Binding<String>, prompt: String) {
        self.label = label; _text = text; self.prompt = prompt
    }

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Theme.ink3))
            .textFieldStyle(.plain)
            .font(Theme.sans(14))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.solid, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Main

struct MainView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Wordmark()
                Spacer()
                if let err = store.lastError {
                    Label("Offline", systemImage: "wifi.exclamationmark")
                        .font(Theme.sans(12)).foregroundStyle(Theme.ink3).help(err)
                }
                Button { store.selectedThreadID = nil } label: {
                    Label("New note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.pill)
                .keyboardShortcut("n")
            }
            .padding(.leading, 70)   // clear the window's traffic lights
            .frame(height: 30)

            HStack(spacing: 16) {
                NotesList().frame(width: 290)
                Group {
                    if let id = store.selectedThreadID, let thread = store.threads.first(where: { $0.id == id }) {
                        ThreadView(thread: thread).id(id)
                    } else {
                        ComposeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: store.selectedThreadID) { _, id in
            if let id { store.markThreadRead(id) }
        }
    }
}

struct NotesList: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notes").font(Theme.serif(24))
                Spacer()
                let unread = store.unreadIncoming.count
                if unread > 0 {
                    Text("\(unread) new").font(Theme.sans(11, .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accentSoft, in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)

            if store.threads.isEmpty {
                VStack(spacing: 6) {
                    Text("No notes yet").font(Theme.serif(20))
                    Text("Write the first one.").font(Theme.sans(13)).foregroundStyle(Theme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.threads) { thread in
                            ThreadRow(thread: thread, selected: store.selectedThreadID == thread.id)
                                .onTapGesture { store.selectedThreadID = thread.id }
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard()
    }
}

struct ThreadRow: View {
    @EnvironmentObject var store: NotesStore
    let thread: NoteThread
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let unread = store.unreadCount(in: thread)
        let mine = store.isMine(thread.root)
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(mine ? Theme.mineDot : Theme.theirDot).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mine ? "You" : thread.root.senderName).font(Theme.sans(13, .semibold))
                    Spacer()
                    Text(thread.last.createdAt, format: .relative(presentation: .named))
                        .font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                }
                Text(thread.root.body).font(Theme.sans(13)).foregroundStyle(Theme.ink2).lineLimit(2)
                if !thread.replies.isEmpty {
                    Text("\(thread.replies.count) \(thread.replies.count == 1 ? "reply" : "replies")")
                        .font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                }
            }
            if unread > 0 {
                Circle().fill(Theme.accent).frame(width: 7, height: 7).padding(.top, 6)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Theme.accentSoft : (hovering ? Theme.glass2 : .clear))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1))
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
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
                    .padding(22)
                }
                .onAppear { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                .onChange(of: thread.replies.count) { _, _ in
                    withAnimation { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            replyBar
        }
    }

    private var lastMine: Note? { thread.all.last(where: { store.isMine($0) }) }

    private var replyBar: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Write a reply…", text: $draft,
                      prompt: Text("Write a reply…").foregroundStyle(Theme.ink3), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.sans(14))
                .lineLimit(1...6)
                .padding(12)
                .background(Theme.solid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            HStack(spacing: 8) {
                Button("Send as new note") { send(asReply: false) }
                    .buttonStyle(.pillSecondary)
                    .help("Starts a new note instead of replying in this one")
                Button("Reply") { send(asReply: true) }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Reply (⌘↩)")
            }
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
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
            if mine { Spacer(minLength: 70) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                Text("\(mine ? "You" : note.senderName) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                Text(note.body)
                    .font(isRoot ? Theme.serif(22) : Theme.sans(14))
                    .lineSpacing(isRoot ? 2 : 1)
                    .textSelection(.enabled)
                    .padding(.horizontal, isRoot ? 18 : 14)
                    .padding(.vertical, isRoot ? 14 : 10)
                    .background {
                        RoundedRectangle(cornerRadius: isRoot ? 16 : 14, style: .continuous)
                            .fill(mine ? Theme.mineTint : Theme.theirTint)
                            .overlay(RoundedRectangle(cornerRadius: isRoot ? 16 : 14, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1))
                            .shadow(color: Theme.shadow, radius: 10, y: 4)
                    }
                if showSeen && note.readAt != nil {
                    Text("Seen").font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                }
            }
            if !mine { Spacer(minLength: 70) }
        }
    }
}

// MARK: - Compose

struct ComposeView: View {
    @EnvironmentObject var store: NotesStore
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A note for \(store.partnerName)").font(Theme.serif(30))
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Write something nice…").font(Theme.serif(22)).foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 23).padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(Theme.serif(22))
                    .scrollContentBackground(.hidden)
                    .padding(18)
                    .focused($focused)
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.mineTint)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }
            HStack {
                Text("⌘↩ to send").font(Theme.sans(12)).foregroundStyle(Theme.ink3)
                Spacer()
                Button(sending ? "Sending…" : "Send note") {
                    sending = true
                    Task {
                        if await store.send(draft, replyTo: nil) { draft = "" }
                        sending = false
                    }
                }
                .buttonStyle(.pill)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }
}

// MARK: - Side popup

struct PopupView: View {
    let notes: [Note]
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        let latest = notes.last!
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Theme.theirTint).frame(width: 36, height: 36)
                .overlay(Text(String(latest.senderName.prefix(1))).font(Theme.sans(15, .semibold)))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(notes.count > 1 ? "\(notes.count) notes from \(latest.senderName)" : "A note from \(latest.senderName)")
                    .font(Theme.sans(13, .semibold))
                Text(latest.body).font(Theme.serif(17)).foregroundStyle(Theme.ink2).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ink3)
                    .frame(width: 20, height: 20)
                    .background(Theme.glass2, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.6)
            .help("Dismiss")
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .frame(width: 330, height: 100, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(response: 0.42, dampingFraction: 0.6), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }
}
