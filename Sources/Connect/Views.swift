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
                    .onHover { panel.panelHover($0) }
                    .onExitCommand { panel.collapse() }
            } else {
                NoteTab()
            }
        }
        .foregroundStyle(Theme.ink)
        .font(Theme.sans(14))
    }
}

/// The tab that hangs down from the top edge near the right corner. Slim when there's nothing
/// new; shows her initial and a count when a note is waiting. Hover to open, drag to slide it
/// along the top.
struct NoteTab: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var panel: PanelState
    @State private var hovering = false

    var body: some View {
        let unread = store.unreadIncoming.count
        let radius: CGFloat = unread > 0 ? 18 : 7
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: 0, style: .continuous)
        ZStack(alignment: .top) {
            // Invisible but hoverable: the mouse only has to get close.
            Color.white.opacity(0.001)
            Group {
                if unread > 0 {
                    JumpingEnvelope(count: unread,
                                    color: (store.unreadIncoming.last?.paper ?? .beige).envelope)
                        .padding(.bottom, 9)
                        .frame(width: 52, height: hovering ? 48 : 44, alignment: .bottom)
                } else {
                    Capsule().fill(Theme.ink3.opacity(0.5)).frame(width: 26, height: 3)
                        .frame(width: 64, height: hovering ? 15 : 10)
                }
            }
            .background {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(Theme.panel))
                    .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .clipShape(shape)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { inside in
            hovering = inside
            panel.tabHover(inside)
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in panel.tabDragChanged() }
                .onEnded { _ in panel.tabDragEnded() }
        )
        .onTapGesture { panel.open() }
        .help(unread == 0 ? "Connect. Hover to open, drag to move"
              : unread == 1 ? "A letter from \(store.partnerName)" : "\(unread) letters from \(store.partnerName)")
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
                case .compose: LetterComposer()
                case .thread(let t): ThreadView(thread: t).id(t.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: store.selectedThreadID) { _, id in
            if let id { store.markThreadRead(id) }
        }
        .onPreferenceChange(ContentHeight.self) { h in
            // header (34) + divider (1)
            if ProcessInfo.processInfo.environment["CONNECT_DEBUG"] != nil { FileHandle.standardError.write("fit \(h)\n".data(using: .utf8)!) }
            DispatchQueue.main.async { panel.fitHeight = h > 0 ? h + 35 : 0 }
        }
    }

    private var canGoBack: Bool {
        switch screen {
        case .settings, .thread: return true
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
            Text(title).font(Theme.serif(16, italic: screen.isList))
                .lineLimit(1)
            Spacer()
            if store.lastError != nil {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                    .help(store.lastError ?? "")
            }
            if store.isConfigured && !store.showSetup {
                if screen.isCompose {
                    IconButton("tray.full", help: "All letters") {
                        store.composing = false
                        store.selectedThreadID = nil
                    }
                }
                if screen.isList {
                    IconButton("square.and.pencil", help: "New letter (⌘N)") {
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
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    private var title: String {
        switch screen {
        case .setup: return "Welcome"
        case .settings: return "Settings"
        case .list: return "Letters"
        case .compose: return "A letter for \(firstName(store.partnerName))"
        case .thread(let t): return store.isMine(t.root) ? "Your letter" : "From \(firstName(t.root.senderName))"
        }
    }
}

private extension PanelView.Screen {
    var isList: Bool { if case .list = self { return true } else { return false } }
    var isCompose: Bool { if case .compose = self { return true } else { return false } }
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .frame(width: 22, height: 22)
                .background(hovering ? Theme.glass2 : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - List

/// Notes as cards, newest first. A note only becomes a thread once someone replies to it.
struct NotesList: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        if store.threads.isEmpty {
            VStack(spacing: 6) {
                Text("No letters yet").font(Theme.serif(17))
                Button("Write a letter") { store.composing = true }.buttonStyle(.pill).padding(.top, 2)
            }
            .padding(16)
            .reportHeight()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.threads) { thread in
                        NoteCardRow(thread: thread)
                            .onTapGesture {
                                if let u = thread.all.last(where: { !store.isMine($0) && $0.readAt == nil && $0.emote == nil }) {
                                    store.envelopeToOpen = u.id
                                }
                                store.selectedThreadID = thread.id
                            }
                    }
                }
                .padding(8)
                .reportHeight()
            }
        }
    }
}

struct NoteCardRow: View {
    @EnvironmentObject var store: NotesStore
    let thread: NoteThread
    @State private var hovering = false

    var body: some View {
        let note = thread.root
        let mine = store.isMine(note)
        let unread = store.unreadCount(in: thread) > 0
        let letter = note.emote == nil
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(mine ? "To \(firstName(store.partnerName))" : "From \(firstName(note.senderName))")
                    .font(Theme.marker(20))
                if unread { Circle().fill(Color(hex: 0xE5484D)).frame(width: 6, height: 6) }
                Spacer()
                Text(note.createdAt.formatted(.relative(presentation: .named)).lowercased())
                    .font(Theme.sans(9.5)).foregroundStyle(letter ? Ink.soft : Theme.ink3)
            }
            if let e = note.emote {
                HStack(spacing: 10) {
                    Text(e.symbol).font(.system(size: 20))
                    Text(mine ? "You sent \(e.phrase)" : "Sent you \(e.phrase)").font(Theme.serif(15))
                }
            } else {
                Text(note.text).font(Theme.sans(12.5)).lineLimit(2)
            }
            if !thread.replies.isEmpty {
                Label("\(thread.replies.count) \(thread.replies.count == 1 ? "reply" : "replies")",
                      systemImage: "arrowshape.turn.up.left")
                    .font(Theme.sans(9.5)).foregroundStyle(letter ? Ink.soft : Theme.ink2)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(letter ? Ink.main : Theme.ink)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(letter ? note.paper.color : (mine ? Theme.mineTint : Theme.theirTint))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(hovering ? 0.2 : 0.12), radius: hovering ? 7 : 4, y: 2)
        }
        .scaleEffect(hovering ? 1.01 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - A note (and its replies, if any)

struct ThreadView: View {
    @EnvironmentObject var store: NotesStore
    let thread: NoteThread
    @State private var draft = ""
    @State private var sending = false
    @State private var replying = false
    @FocusState private var focused: Bool
    @State private var opening: Note?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        NoteCard(note: thread.root, large: true)
                        if !thread.replies.isEmpty {
                            HStack(spacing: 6) {
                                Rectangle().fill(Theme.line).frame(width: 2, height: 10)
                                Text("Replies").font(Theme.sans(10, .semibold)).foregroundStyle(Theme.ink3)
                            }
                            .padding(.leading, 8)
                            ForEach(thread.replies) { reply in
                                NoteCard(note: reply, large: false).id(reply.id)
                                    .padding(.leading, 10)
                            }
                        }
                        if let mine = thread.all.last(where: { store.isMine($0) }), mine.readAt != nil {
                            Text("Seen").font(Theme.sans(10)).foregroundStyle(Theme.ink3)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(10)
                    .opacity(opening == nil ? 1 : 0)
                    .frame(minHeight: opening == nil ? 0 : 250, alignment: .top)
                    .overlay {
                        if let opening {
                            EnvelopeOpening(note: opening) {
                                withAnimation(.easeOut(duration: 0.3)) { self.opening = nil }
                            }
                        }
                    }
                    .reportHeight()
                }
                .onChange(of: thread.replies.count) { _, _ in
                    withAnimation { proxy.scrollTo(thread.last.id, anchor: .bottom) }
                }
            }
            VStack(spacing: 0) {
                Rectangle().fill(Theme.line).frame(height: 1)
                bottom
            }
            .reportHeight()
        }
        .onAppear {
            if let id = store.envelopeToOpen, let n = thread.all.first(where: { $0.id == id }) {
                opening = n
                store.envelopeToOpen = nil
            }
        }
    }

    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @ViewBuilder private var bottom: some View {
        if replying {
            VStack(alignment: .leading, spacing: 8) {
                MessageField(text: $draft, placeholder: "Write back…", hand: true, focused: $focused) { send() }
                HStack {
                    Text("↩ send · ⌥↩ new line").font(Theme.sans(10)).foregroundStyle(Theme.ink3)
                    Spacer()
                    Button("Cancel") { replying = false; draft = "" }
                        .buttonStyle(.plain).font(Theme.sans(11, .medium)).foregroundStyle(Theme.ink2)
                }
            }
            .padding(8)
            .onAppear { focused = true }
        } else {
            HStack(spacing: 6) {
                Button { replying = true } label: { Label("Write back", systemImage: "arrowshape.turn.up.left") }
                    .buttonStyle(.pill)
                Button {
                    store.selectedThreadID = nil
                    store.composing = true
                } label: { Label("New letter", systemImage: "square.and.pencil") }
                    .buttonStyle(.pillSecondary)
                Spacer()
            }
            .padding(8)
        }
    }

    private func send() {
        guard !sending, !empty else { return }
        let text = Paper.saved.token + "\n" + draft
        sending = true
        Task {
            if await store.send(text, replyTo: thread.root.id) { draft = ""; replying = false }
            sending = false
        }
    }
}

/// One note on its own card, tinted by who wrote it.
struct NoteCard: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var panel: PanelState
    let note: Note
    let large: Bool

    var body: some View {
        if note.emote == nil {
            LetterCard(note: note, large: large)
        } else {
            emoteCard
        }
    }

    private var emoteCard: some View {
        let mine = store.isMine(note)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(mine ? "You" : note.senderName) · \(note.createdAt.formatted(.relative(presentation: .named)))")
                .font(Theme.sans(10, .medium)).foregroundStyle(Theme.ink3)
            if let e = note.emote {
                HStack(spacing: 12) {
                    Text(e.symbol).font(.system(size: large ? 28 : 20))
                    Text(mine ? "You sent \(e.phrase)" : "Sent you \(e.phrase)")
                        .font(large ? Theme.serif(16) : Theme.serif(14))
                    Spacer()
                    Button { panel.playEmote(e) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.pillSecondary)
                        .help("Play again")
                }
            } else {
                Text(note.body)
                    .font(large ? Theme.serif(17) : Theme.serif(15))
                    .lineSpacing(1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(large ? 12 : 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(mine ? Theme.mineTint : Theme.theirTint)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                .shadow(color: Theme.shadow, radius: 4, y: 2)
        }
    }
}

/// Text box where Return sends and Option-Return adds a new line.
struct MessageField: View {
    @Binding var text: String
    let placeholder: String
    var serif = false
    var hand = false
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        TextField(placeholder, text: $text,
                  prompt: Text(placeholder).foregroundStyle(Theme.ink3), axis: .vertical)
            .textFieldStyle(.plain)
            .font(hand ? Theme.sans(13) : serif ? Theme.serif(16) : Theme.sans(13))
            .lineLimit(serif ? 2...5 : 1...5)
            .focused(focused)
            .onSubmit(onSend)
            .padding(9)
            .background(Theme.solid, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
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

// MARK: - Fitting the panel to its content

/// Heights of the measured parts of the current screen, added together.
struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

extension View {
    /// Reports this view's natural height so the panel can size itself to fit.
    func reportHeight() -> some View {
        background(GeometryReader { g in Color.clear.preference(key: ContentHeight.self, value: g.size.height) })
    }
}
