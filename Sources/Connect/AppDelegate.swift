import AppKit
import Combine
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = NotesStore()
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private let popup = SidePopupController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        popup.onOpen = { [weak self] note in self?.openThread(note.threadID) }
        store.onIncoming = { [weak self] notes in self?.popup.show(notes: notes) }
        store.isViewingThread = { [weak self] id in
            guard let self, let window = self.window else { return false }
            return window.isVisible && NSApp.isActive && self.store.selectedThreadID == id
        }
        store.$notes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)

        // Start at login so notes always arrive (asked once; can be turned off from the menu).
        if !UserDefaults.standard.bool(forKey: "askedLoginItem") {
            UserDefaults.standard.set(true, forKey: "askedLoginItem")
            try? SMAppService.mainApp.register()
        }

        store.start()
        if !store.isConfigured { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "heart.text.square", accessibilityDescription: "Connect")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateBadge() {
        let count = store.unreadIncoming.count
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.image = NSImage(systemSymbolName: count > 0 ? "heart.text.square.fill" : "heart.text.square",
                                           accessibilityDescription: "Connect")
        if count == 0 { popup.hide() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let unread = store.unreadIncoming.count
        menu.addItem(item(unread > 0 ? "Open Notes (\(unread) new)" : "Open Notes", #selector(openNotes), "o"))
        menu.addItem(item("New Note…", #selector(newNote), "n"))
        menu.addItem(.separator())
        if let backend = store.backend {
            let copy = item("Copy Pairing Code", #selector(copyPairingCode), "")
            copy.representedObject = backend.pairingCode
            menu.addItem(copy)
        }
        menu.addItem(item("Name & Connection…", #selector(openSetup), ""))
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

    @objc private func openNotes() {
        if let latest = store.unreadIncoming.last { openThread(latest.threadID) } else { showWindow() }
    }

    @objc private func newNote() {
        store.selectedThreadID = nil
        showWindow()
    }

    @objc private func openSetup() {
        store.showSetup = true
        showWindow()
    }

    @objc private func copyPairingCode(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Window

    func openThread(_ id: UUID) {
        popup.hide()
        store.selectedThreadID = id
        store.markThreadRead(id)
        showWindow()
    }

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Connect"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: RootView().environmentObject(store))
            w.center()
            w.setFrameAutosaveName("ConnectMainWindow")
            window = w
        }
        NSApp.setActivationPolicy(.regular)   // show in Dock / ⌘-Tab while the window is open
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
