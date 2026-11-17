import AppKit
import Combine
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let auth: AuthManager
    let store: NotesStore
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var statusItem: NSStatusItem!
    private var panel: SidePanelController!
    private let emotes = EmoteOverlay()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        auth = AuthManager()
        store = NotesStore(auth: auth)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        NSApp.setActivationPolicy(.accessory)
        panel = SidePanelController(store: store, updater: updater.updater)
        panel.state.quit = { NSApp.terminate(nil) }
        panel.state.playEmote = { [weak self] e in
            guard let self else { return }
            self.emotes.play(e, at: self.panel.burstPoint)
        }
        setupStatusItem()

        store.onIncoming = { [weak self] _ in self?.panel.noteArrived() }
        store.isViewingThread = { [weak self] id in
            guard let self else { return false }
            return self.panel.isOpen && self.store.selectedThreadID == id
        }
        store.$notes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)

        // Start at login so notes always arrive (can be turned off in Settings).
        if !UserDefaults.standard.bool(forKey: "askedLoginItem") {
            UserDefaults.standard.set(true, forKey: "askedLoginItem")
            try? SMAppService.mainApp.register()
        }

        store.start()
        // For checking the animation without sending anything: CONNECT_PLAY_EMOTE=flowers
        if let name = ProcessInfo.processInfo.environment["CONNECT_PLAY_EMOTE"], let e = Emote(rawValue: name) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.panel.open(); self.panel.state.playEmote(e) }
        }
        // Debug look-checks: CONNECT_PREVIEW=compose | letter | tab (tab and letter add a local fake letter)
        if let what = ProcessInfo.processInfo.environment["CONNECT_PREVIEW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if what != "compose" {
                    self.store.injectPreviewLetter(paper: Paper(rawValue: ProcessInfo.processInfo.environment["CONNECT_PAPER"] ?? "") ?? .beige)
                    self.panel.unreadChanged(self.store.unreadIncoming.count)
                }
                if what != "tab" { self.panel.open() }
            }
        }
        if store.isConfigured { panel.showTab() } else { panel.open() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.open()
        return true
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "heart.text.square", accessibilityDescription: "Connect")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Left click opens the side panel; right click (or ctrl-click) shows the small menu.
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            menu.delegate = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle()
        }
    }

    private func updateBadge() {
        let count = store.unreadIncoming.count
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.image = NSImage(systemSymbolName: count > 0 ? "heart.text.square.fill" : "heart.text.square",
                                           accessibilityDescription: "Connect")
        panel.unreadChanged(count)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let unread = store.unreadIncoming.count
        menu.addItem(item(unread > 0 ? "Open Notes (\(unread) new)" : "Open Notes", #selector(openNotes), "o"))
        menu.addItem(item("New Note…", #selector(newNote), "n"))
        menu.addItem(.separator())
        if let s = auth.session {
            let who = NSMenuItem(title: "Signed in as \(s.email)", action: nil, keyEquivalent: "")
            who.isEnabled = false
            menu.addItem(who)
        }
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        let login = item("Open at Login", #selector(toggleLogin), "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let update = NSMenuItem(title: "Check for Updates…",
                                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let v = NSMenuItem(title: "Connect \(version)", action: nil, keyEquivalent: "")
        v.isEnabled = false
        menu.addItem(v)
        menu.addItem(.separator())
        menu.addItem(item("Quit Connect", #selector(quit), "q"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openNotes() { panel.open() }

    @objc private func newNote() {
        store.showSettings = false
        store.selectedThreadID = nil
        store.composing = true
        panel.open()
    }

    @objc private func openSettings() {
        store.showSettings = true
        panel.open()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
