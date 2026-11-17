import AppKit
import Combine
import Sparkle
import SwiftUI

/// What the SwiftUI side of the panel needs to know and do.
@MainActor
final class PanelState: ObservableObject {
    @Published var expanded = false
    var open: () -> Void = {}
    var collapse: () -> Void = {}
    var quit: () -> Void = {}
    let updater: SPUUpdater
    init(updater: SPUUpdater) { self.updater = updater }
}

/// Borderless panel that can still take typing.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The whole app lives here, pinned to the right edge of the screen:
/// hidden → a little tab when a note arrives → the full panel when clicked.
@MainActor
final class SidePanelController: NSObject, NSWindowDelegate {
    enum Mode { case hidden, tab, open }
    private(set) var mode: Mode = .hidden

    let state: PanelState
    private let store: NotesStore
    private let panel: KeyPanel
    private let tabSize = NSSize(width: 58, height: 50)
    private let openSize = NSSize(width: 360, height: 560)

    init(store: NotesStore, updater: SPUUpdater) {
        self.store = store
        self.state = PanelState(updater: updater)
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // SwiftUI draws the shadow so the corners stay clean
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelRoot()
            .environmentObject(store)
            .environmentObject(state))

        state.open = { [weak self] in self?.open() }
        state.collapse = { [weak self] in self?.collapse() }
    }

    var isOpen: Bool { mode == .open }

    // MARK: Geometry

    private var area: NSRect { (NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    private var tabFrame: NSRect {
        NSRect(x: area.maxX - tabSize.width, y: area.minY + area.height * 0.62,
               width: tabSize.width, height: tabSize.height)
    }

    private var openFrame: NSRect {
        let h = min(openSize.height, area.height - 24)
        let y = max(area.minY + 12, min(area.minY + area.height * 0.62 + tabSize.height - h + 60, area.maxY - h - 12))
        return NSRect(x: area.maxX - openSize.width - 12, y: y, width: openSize.width, height: h)
    }

    // MARK: States

    /// A note came in: show the little tab (unless the panel is already open).
    func showTab(sound: Bool = true) {
        if mode == .open { return }
        if sound { NSSound(named: "Purr")?.play() }
        guard mode != .tab else { return }
        mode = .tab
        state.expanded = false
        let target = tabFrame
        panel.setFrame(target.offsetBy(dx: target.width + 20, dy: 0), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        animate(to: target, duration: 0.45)
    }

    func open() {
        let wasVisible = panel.isVisible
        mode = .open
        state.expanded = true
        if let unread = store.unreadIncoming.last, store.selectedThreadID == nil, !store.composing {
            store.selectedThreadID = unread.threadID
        }
        if let id = store.selectedThreadID { store.markThreadRead(id) }
        let target = openFrame
        if !wasVisible {
            panel.setFrame(target.offsetBy(dx: target.width + 20, dy: 0), display: false)
            panel.alphaValue = 1
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        animate(to: target, duration: 0.42)
    }

    func toggle() { mode == .open ? collapse() : open() }

    /// Close the panel back to the tab if there's still something unread, otherwise tuck it away.
    func collapse() {
        guard mode == .open else { return }
        if store.unreadIncoming.isEmpty {
            hide()
        } else {
            mode = .tab
            fadeSwap { self.state.expanded = false; self.panel.setFrame(self.tabFrame, display: true) }
        }
    }

    func hide() {
        guard panel.isVisible else { mode = .hidden; return }
        mode = .hidden
        let out = panel.frame.offsetBy(dx: panel.frame.width + 20, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(out, display: true)
        }, completionHandler: {
            Task { @MainActor in
                if self.mode == .hidden { self.panel.orderOut(nil); self.state.expanded = false }
            }
        })
    }

    /// Unread count changed: drop the tab once everything's been read.
    func unreadChanged(_ count: Int) {
        if count == 0, mode == .tab { hide() }
    }

    private func animate(to frame: NSRect, duration: Double) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func fadeSwap(_ change: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                change()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.panel.animator().alphaValue = 1
                }
            }
        })
    }

    // MARK: NSWindowDelegate

    /// Clicking anywhere else closes the panel — except during setup, when Google's sign-in
    /// window needs to take focus for a moment.
    func windowDidResignKey(_ notification: Notification) {
        guard mode == .open, store.isConfigured, !store.showSetup else { return }
        collapse()
    }
}
