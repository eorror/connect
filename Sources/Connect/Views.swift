import AuthenticationServices
import ServiceManagement
import Sparkle
import SwiftUI

// MARK: - Panel root

/// Either the little tab on the screen edge, or the full panel.
struct PanelRoot: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var panel: PanelState

    var body: some View {
        Group {
            if panel.expanded {
                PanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onExitCommand { panel.collapse() }
            } else {
                NoteTab()
            }
        }
        .foregroundStyle(Theme.ink)
        .font(Theme.sans(14))
    }
}

/// The small thing that pokes out of the right edge when a note arrives.
struct NoteTab: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var panel: PanelState
    @State private var hovering = false

    var body: some View {
        let unread = store.unreadIncoming.count
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        ZStack(alignment: .topLeading) {
            Circle().fill(Theme.theirTint)
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                .overlay(Text(String(store.partnerName.prefix(1)).uppercased()).font(Theme.sans(15, .semibold)))
                .frame(width: 32, height: 32)
            if unread > 0 {
                Text("\(unread)")
                    .font(Theme.sans(10, .semibold))
                    .foregroundStyle(Theme.onInk)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Theme.ink, in: Capsule())
                    .offset(x: 20, y: -5)
            }
        }
        .padding(.leading, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            shape.fill(.regularMaterial)
                .overlay(shape.fill(Theme.panel))
                .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .clipShape(shape)
        .contentShape(shape)
        .offset(x: hovering ? 0 : 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { panel.open() }
        .help(unread == 1 ? "A note from \(store.partnerName)" : "\(unread) notes from \(store.partnerName)")
    }
}

// MARK: - Panel

struct PanelView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var panel: PanelState

    private var screen: Screen {
        if !store.isConfigured || store.showSetup { return .setup }
        if store.showSettings { return .settings }
        if let id = store.selectedThreadID, let t = store.threads.first(where: { $0.id == id }) { return .thread(t) }
        if store.composing { return .compose }
        return .list
    }

    enum Screen { case setup, settings, list, compose, thread(NoteThread) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            Group {
                switch screen {
                case .setup: ScrollView { SetupView() }
                case .settings: SettingsView()
                case .list: NotesList()
                case .compose: ComposeView()
                case .thread(let t): ThreadView(thread: t).id(t.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: store.selectedThreadID) { _, id in
            if let id { store.markThreadRead(id) }
        }
    }

    private var canGoBack: Bool {
        switch screen {
        case .settings, .compose, .thread: return true
        default: return false
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if canGoBack {
                IconButton("chevron.left", help: "Back") {
                    store.showSettings = false
                    store.composing = false
                    store.selectedThreadID = nil
                }
            }
            Text(title).font(Theme.serif(22, italic: screen.isList))
                .lineLimit(1)
            Spacer()
            if store.lastError != nil {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                    .help(store.lastError ?? "")
            }
            if store.isConfigured && !store.showSetup {
                if screen.isList {
                    IconButton("square.and.pencil", help: "New note (⌘N)") {
                        store.selectedThreadID = nil
                        store.composing = true
                    }
                    .keyboardShortcut("n")
                }
                if !store.showSettings {
                    IconButton("gearshape", help: "Settings") { store.showSettings = true }
                        .keyboardShortcut(",")
                }
            }
            IconButton("xmark", help: "Close (Esc)") { panel.collapse() }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var title: String {
        switch screen {
        case .setup: return "Welcome"
        case .settings: return "Settings"
        case .list: return "Connect"
        case .compose: return "New note"
        case .thread(let t): return store.isMine(t.root) ? "Your note" : t.root.senderName
        }
    }
}

private extension PanelView.Screen {
    var isList: Bool { if case .list = self { return true } else { return false } }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.help = help; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .frame(width: 28, height: 28)
                .background(hovering ? Theme.glass2 : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - List

struct NotesList: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        if store.threads.isEmpty {
            VStack(spacing: 10) {
                Text("No notes yet").font(Theme.serif(22))
                Text("Write the first one.").font(Theme.sans(13)).foregroundStyle(Theme.ink3)
                Button("Write a note") { store.composing = true }.buttonStyle(.pill).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.threads) { thread in
                        ThreadRow(thread: thread, selected: false)
                            .onTapGesture { store.selectedThreadID = thread.id }
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Thread

struct ThreadView: View {
    @EnvironmentObject var store: NotesStore
    let thread: NoteThread
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(thread.all) { note in
                            NoteBubble(note: note, isRoot: note.id == thread.root.id,
                                       showSeen: note.id == lastMine?.id)
                                .id(note.id)
                        }
                    }
                    .padding(16)
                }
                .onAppear { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                .onChange(of: thread.replies.count) { _, _ in
                    withAnimation { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            replyBar
        }
        .onAppear { focused = true }
    }

    private var lastMine: Note? { thread.all.last(where: { store.isMine($0) }) }
    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var replyBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageField(text: $draft, placeholder: "Reply…", focused: $focused) { send(asReply: true) }
            HStack {
                Text("↩ send · ⌥↩ new line").font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                Spacer()
                Button("Send as new note") { send(asReply: false) }
                    .buttonStyle(.plain)
                    .font(Theme.sans(12, .medium))
                    .foregroundStyle(Theme.ink2)
                    .disabled(sending || empty)
                    .opacity(empty ? 0.4 : 1)
            }
        }
        .padding(12)
    }

    private func send(asReply: Bool) {
        guard !sending, !empty else { return }
        let text = draft
        sending = true
        Task {
            if await store.send(text, replyTo: asReply ? thread.root.id : nil) { draft = "" }
            sending = false
        }
    }
}

/// Text box where Return sends and Option-Return adds a new line.
struct MessageField: View {
    @Binding var text: String
    let placeholder: String
    var serif = false
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        TextField(placeholder, text: $text,
                  prompt: Text(placeholder).foregroundStyle(Theme.ink3), axis: .vertical)
            .textFieldStyle(.plain)
            .font(serif ? Theme.serif(19) : Theme.sans(14))
            .lineLimit(serif ? 4...12 : 1...6)
            .focused(focused)
            .onSubmit(onSend)
            .padding(12)
            .background(Theme.solid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Compose

struct ComposeView: View {
    @EnvironmentObject var store: NotesStore
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To \(store.partnerName)").font(Theme.sans(12, .semibold)).foregroundStyle(Theme.ink3)
            MessageField(text: $draft, placeholder: "Write something nice…", serif: true, focused: $focused) { send() }
            HStack {
                Text("↩ send · ⌥↩ new line").font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                Spacer()
                Button(sending ? "Sending…" : "Send") { send() }
                    .buttonStyle(.pill)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
        .padding(16)
        .onAppear { focused = true }
    }

    private func send() {
        guard !sending, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        Task {
            if await store.send(draft, replyTo: nil) { draft = "" }
            sending = false
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var panel: PanelState
    @State private var partner = UserDefaults.standard.string(forKey: "partnerEmail") ?? ""
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var autoUpdate = true

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SetupSection("Updates") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect \(version)").font(Theme.sans(13, .semibold))
                            Text(lastChecked).font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                        }
                        Spacer()
                        Button("Check for updates") { panel.updater.checkForUpdates() }
                            .buttonStyle(.pill)
                    }
                    Toggle("Install updates automatically", isOn: $autoUpdate)
                        .onChange(of: autoUpdate) { _, on in
                            panel.updater.automaticallyChecksForUpdates = true
                            panel.updater.automaticallyDownloadsUpdates = on
                        }
                }

                SetupSection("Your account") {
                    if let s = store.auth.session {
                        HStack(spacing: 10) {
                            Circle().fill(Theme.mineTint).frame(width: 30, height: 30)
                                .overlay(Text(String(s.name.prefix(1))).font(Theme.sans(13, .semibold)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(Theme.sans(13, .semibold))
                                Text(s.email).font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                            }
                            Spacer()
                            Button("Sign out") { store.auth.signOut() }.buttonStyle(.pillSecondary)
                        }
                    }
                }

                SetupSection("Writing to") {
                    HStack(spacing: 8) {
                        ThemedField("Their Google email", text: $partner, prompt: "name@gmail.com")
                            .onSubmit(savePartner)
                        Button("Save") { savePartner() }
                            .buttonStyle(.pillSecondary)
                            .disabled(partner.trimmingCharacters(in: .whitespaces).lowercased() == store.partnerEmail)
                    }
                }

                SetupSection("General") {
                    Toggle("Open Connect when the Mac starts", isOn: $openAtLogin)
                        .onChange(of: openAtLogin) { _, on in
                            if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        }
                    Button("Quit Connect") { panel.quit() }.buttonStyle(.pillSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.mineDot)
            .controlSize(.small)
            .font(Theme.sans(13))
            .padding(18)
        }
        .onAppear { autoUpdate = panel.updater.automaticallyDownloadsUpdates }
    }

    private var lastChecked: String {
        guard let d = panel.updater.lastUpdateCheckDate else { return "Not checked yet" }
        return "Checked " + d.formatted(.relative(presentation: .named))
    }

    private func savePartner() {
        let p = partner.trimmingCharacters(in: .whitespaces).lowercased()
        guard p.contains("@"), p.contains("."), p != store.myEmail else { return }
        store.setPartner(p)
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
                Text("Connect").font(Theme.serif(34, italic: true))
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
        .padding(22)
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

struct NoteBubble: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    let isRoot: Bool
    let showSeen: Bool

    var body: some View {
        let mine = store.isMine(note)
        HStack {
            if mine { Spacer(minLength: 36) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                Text("\(mine ? "You" : note.senderName) · \(note.createdAt.formatted(.relative(presentation: .named)))")
                    .font(Theme.sans(11)).foregroundStyle(Theme.ink3)
                Text(note.body)
                    .font(isRoot ? Theme.serif(19) : Theme.sans(14))
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
            if !mine { Spacer(minLength: 36) }
        }
    }
}

