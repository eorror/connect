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
    /// Mouse entered/left the edge tab or the open panel.
    var tabHover: (Bool) -> Void = { _ in }
    var panelHover: (Bool) -> Void = { _ in }
    /// Dragging the tab up and down the edge: began / moved / ended.
    var tabDragChanged: () -> Void = {}
    var tabDragEnded: () -> Void = {}
    let updater: SPUUpdater
    init(updater: SPUUpdater) { self.updater = updater }
}

/// Borderless panel that can still take typing.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The whole app lives here, pinned to the right edge of the screen.
/// Resting: a slim tab poking out of the edge (a bigger one with her initial when a note is unread).
/// Hover the tab and the panel slides out; move away and it slides back in.
/// Click inside the panel and it stays open until you click elsewhere or press Esc.
@MainActor
final class SidePanelController: NSObject, NSWindowDelegate {
    enum Mode { case tab, open }
    private(set) var mode: Mode = .tab

    let state: PanelState
    private let store: NotesStore
    private let panel: KeyPanel
    private let openSize = NSSize(width: 360, height: 560)

    /// Opened by hovering and not clicked yet, so it closes again when the mouse leaves.
    private var pinned = false
    private var hoverOpenWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    private var monitor: Any?

    /// Where the tab sits on the edge, as a fraction of the screen height (remembered).
    private var anchor: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "tabAnchor")
        return v > 0 ? CGFloat(v) : 0.62
    }()
    private var dragStart: (mouseY: CGFloat, frameY: CGFloat)?

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
        panel.hasShadow = false   // SwiftUI draws the edges so the corners stay clean
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelRoot()
            .environmentObject(store)
            .environmentObject(state))

        state.open = { [weak self] in self?.open() }
        state.collapse = { [weak self] in self?.collapse() }
        state.tabHover = { [weak self] inside in self?.tabHovered(inside) }
        state.panelHover = { [weak self] inside in self?.panelHovered(inside) }
        state.tabDragChanged = { [weak self] in self?.dragChanged() }
        state.tabDragEnded = { [weak self] in self?.dragEnded() }

        // Any click or keypress inside the panel keeps it open.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            if let self, e.window === self.panel, self.mode == .open { self.pin() }
            return e
        }
    }

    var isOpen: Bool { mode == .open }

    // MARK: Geometry

    private var area: NSRect { (NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    /// Slim handle normally; a bigger tab with her initial when something is unread.
    /// The frame is wider than what's drawn so the mouse only has to get close.
    private var tabSize: NSSize {
        store.unreadIncoming.isEmpty ? NSSize(width: 26, height: 84) : NSSize(width: 66, height: 60)
    }

    private var tabFrame: NSRect {
        let s = tabSize
        return NSRect(x: area.maxX - s.width, y: area.minY + area.height * anchor - s.height / 2,
                      width: s.width, height: s.height)
    }

    private var openFrame: NSRect {
        let h = min(openSize.height, area.height - 24)
        let center = area.minY + area.height * anchor
        let y = max(area.minY + 12, min(center - h / 2, area.maxY - h - 12))
        return NSRect(x: area.maxX - openSize.width - 12, y: y, width: openSize.width, height: h)
    }

    // MARK: States

    /// Put the resting tab on screen (at launch, and whenever the panel closes).
    func showTab() {
        mode = .tab
        state.expanded = false
        let target = tabFrame
        panel.setFrame(target.offsetBy(dx: target.width, dy: 0), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        slide(to: target, duration: 0.45)
    }

    /// A note came in: chime, and grow the tab to show it.
    func noteArrived() {
        NSSound(named: "Purr")?.play()
        if mode == .tab { resizeTab() }
    }

    /// Open from a click, the menu bar or a shortcut: take focus and stay open.
    func open() { open(pinned: true) }

    private func open(pinned: Bool) {
        hoverOpenWork?.cancel()
        leaveWork?.cancel()
        self.pinned = pinned || self.pinned
        if let unread = store.unreadIncoming.last, store.selectedThreadID == nil, !store.composing {
            store.selectedThreadID = unread.threadID
        }
        if let id = store.selectedThreadID { store.markThreadRead(id) }

        if mode != .open {
            mode = .open
            state.expanded = true
            let target = openFrame
            panel.setFrame(target.offsetBy(dx: target.width + 20, dy: 0), display: false)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            slide(to: target, duration: 0.4)
        }
        if self.pinned { takeFocus() }
    }

    func toggle() { mode == .open ? collapse() : open() }

    /// Slide the panel back into the edge and leave the tab.
    func collapse() {
        guard mode == .open else { return }
        mode = .tab
        pinned = false
        hoverOpenWork?.cancel()
        leaveWork?.cancel()
        let out = panel.frame.offsetBy(dx: panel.frame.width + 20, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(out, display: true)
        }, completionHandler: {
            Task { @MainActor in
                guard self.mode == .tab else { return }
                self.showTab()
            }
        })
    }

    /// Unread count changed: the tab grows or shrinks to match.
    func unreadChanged(_ count: Int) {
        if mode == .tab { resizeTab() }
    }

    private func resizeTab() {
        guard panel.isVisible else { return }
        slide(to: tabFrame, duration: 0.35)
    }

    private func pin() {
        guard !pinned else { return }
        pinned = true
        leaveWork?.cancel()
        takeFocus()
    }

    private func takeFocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    private func slide(to frame: NSRect, duration: Double) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Hover

    private func tabHovered(_ inside: Bool) {
        hoverOpenWork?.cancel()
        guard inside, mode == .tab, dragStart == nil else { return }
        // A short pause so just sweeping past the edge doesn't pop it open.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .tab, self.dragStart == nil else { return }
            self.open(pinned: false)
        }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func panelHovered(_ inside: Bool) {
        leaveWork?.cancel()
        guard !inside, mode == .open, !pinned else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .open, !self.pinned else { return }
            self.collapse()
        }
        leaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Dragging

    /// Uses the real mouse position on screen, since the window moves under the cursor.
    private func dragChanged() {
        guard mode == .tab else { return }
        hoverOpenWork?.cancel()
        let mouseY = NSEvent.mouseLocation.y
        if dragStart == nil { dragStart = (mouseY, panel.frame.minY) }
        guard let start = dragStart else { return }
        var f = panel.frame
        f.origin.y = min(max(start.frameY + (mouseY - start.mouseY), area.minY + 8), area.maxY - f.height - 8)
        panel.setFrame(f, display: true)
    }

    private func dragEnded() {
        guard dragStart != nil else { return }
        dragStart = nil
        anchor = (panel.frame.midY - area.minY) / area.height
        UserDefaults.standard.set(Double(anchor), forKey: "tabAnchor")
    }

    // MARK: NSWindowDelegate

    /// Clicking anywhere else closes the panel, except during setup, when Google's sign-in
    /// window needs to take focus for a moment.
    func windowDidResignKey(_ notification: Notification) {
        guard mode == .open, pinned, store.isConfigured, !store.showSetup else { return }
        collapse()
    }
}
