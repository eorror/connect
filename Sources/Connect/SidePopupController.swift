import AppKit
import Combine
import Sparkle
import SwiftUI

/// What the SwiftUI side of the panel needs to know and do.
@MainActor
final class PanelState: ObservableObject {
    @Published var expanded = false
    /// Natural height of what's on screen, so the panel can hug it.
    @Published var fitHeight: CGFloat = 0
    var open: () -> Void = {}
    var collapse: () -> Void = {}
    var quit: () -> Void = {}
    /// Rain an emote across the screen.
    var playEmote: (Emote) -> Void = { _ in }
    /// Mouse entered/left the edge tab or the open panel.
    var tabHover: (Bool) -> Void = { _ in }
    var panelHover: (Bool) -> Void = { _ in }
    /// Dragging the tab along the top edge: began / moved / ended.
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

    /// Opened by hovering and not clicked yet, so it closes again when the mouse leaves.
    private var pinned = false
    private var hoverOpenWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// How far the tab sits in from the top-right corner, in points (remembered; drag to change).
    private var inset: CGFloat = {
        let v = UserDefaults.standard.object(forKey: "tabInsetRight") as? Double
        return CGFloat(v ?? 24)
    }()
    private var dragStart: (mouseX: CGFloat, frameX: CGFloat)?

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
        let host = NSHostingView(rootView: PanelRoot()
            .environmentObject(store)
            .environmentObject(state))
        host.sizingOptions = []   // the controller decides the size; don't let SwiftUI push it bigger
        panel.contentView = host

        state.open = { [weak self] in self?.open() }
        state.collapse = { [weak self] in self?.collapse() }
        state.tabHover = { [weak self] inside in self?.tabHovered(inside) }
        state.panelHover = { [weak self] inside in self?.panelHovered(inside) }
        state.tabDragChanged = { [weak self] in self?.dragChanged() }
        state.tabDragEnded = { [weak self] in self?.dragEnded() }

        // Each screen gets its own size; follow along while the panel is open.
        Publishers.CombineLatest4(store.$composing, store.$selectedThreadID, store.$showSettings, store.$showSetup)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode == .open else { return }
                let target = self.openFrame
                if target != self.panel.frame { self.slide(to: target, duration: 0.3) }
            }
            .store(in: &cancellables)
        state.$fitHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode == .open else { return }
                let target = self.openFrame
                if target != self.panel.frame { self.slide(to: target, duration: 0.25) }
            }
            .store(in: &cancellables)

        // Any click or keypress inside the panel keeps it open.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            if let self, e.window === self.panel, self.mode == .open { self.pin() }
            return e
        }
    }

    var isOpen: Bool { mode == .open }

    /// Middle of the note on screen, where emotes burst out of.
    var burstPoint: NSPoint {
        let f = mode == .open ? openFrame : panel.frame
        return NSPoint(x: f.midX, y: f.midY)
    }

    // MARK: Geometry

    private var area: NSRect { (NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    /// Hangs down from the top edge, just under the menu bar near the right corner.
    /// Slim handle normally; a bigger tab with her initial when something is unread.
    /// The frame is taller than what's drawn so the mouse only has to get close.
    private var tabSize: NSSize {
        store.unreadIncoming.isEmpty ? NSSize(width: 84, height: 24) : NSSize(width: 60, height: 62)
    }

    private var tabFrame: NSRect {
        let s = tabSize
        let x = min(max(area.maxX - inset - s.width, area.minX + 8), area.maxX - s.width)
        return NSRect(x: x, y: area.maxY - s.height, width: s.width, height: s.height)
    }

    /// As small as it can be: notes, the list and the writing card hug their content
    /// (up to a cap, then they scroll). Setup and settings have fixed sizes.
    private var openSize: NSSize {
        if !store.isConfigured || store.showSetup { return NSSize(width: 320, height: 500) }
        if store.showSettings { return NSSize(width: 290, height: 410) }
        let h = state.fitHeight > 0 ? min(max(state.fitHeight, 100), 440) : 200
        return NSSize(width: 270, height: ceil(h))
    }

    private var openFrame: NSRect {
        let h = min(openSize.height, area.height - 24)
        let w = openSize.width
        // Drop down from the tab: right edges line up, kept on screen.
        let tabRight = area.maxX - inset
        let x = min(max(tabRight - w + 12, area.minX + 8), area.maxX - w - 8)
        return NSRect(x: x, y: area.maxY - h - 8, width: w, height: h)
    }

    // MARK: States

    /// Put the resting tab on screen (at launch, and whenever the panel closes).
    func showTab() {
        mode = .tab
        state.expanded = false
        let target = tabFrame
        panel.setFrame(target, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
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
        var emoteToPlay: Emote?
        if mode != .open, !store.showSettings {
            if let unread = store.unreadIncoming.last {
                emoteToPlay = unread.emote
                // Something new: open straight to it.
                store.composing = false
                store.selectedThreadID = unread.threadID
            } else if store.selectedThreadID == nil {
                // Nothing new: open straight to a blank note.
                store.composing = true
            }
        }
        if let id = store.selectedThreadID { store.markThreadRead(id) }

        if mode != .open {
            mode = .open
            state.expanded = true
            let target = openFrame
            // Drops down a little from the top while fading in.
            panel.setFrame(target.offsetBy(dx: 0, dy: 14), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        }
        if self.pinned { takeFocus() }
        if let emoteToPlay {
            // Let the note settle in first, then burst out of it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.state.playEmote(emoteToPlay) }
        }
    }

    func toggle() { mode == .open ? collapse() : open() }

    /// Slide the panel back into the edge and leave the tab.
    func collapse() {
        guard mode == .open else { return }
        mode = .tab
        pinned = false
        store.showSettings = false
        store.selectedThreadID = nil
        hoverOpenWork?.cancel()
        leaveWork?.cancel()
        let out = panel.frame.offsetBy(dx: 0, dy: 14)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(out, display: true)
            panel.animator().alphaValue = 0
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
        if ProcessInfo.processInfo.environment["CONNECT_DEBUG"] != nil { FileHandle.standardError.write("slide \(frame.height) fit \(state.fitHeight)\n".data(using: .utf8)!) }
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
        let mouseX = NSEvent.mouseLocation.x
        if dragStart == nil { dragStart = (mouseX, panel.frame.minX) }
        guard let start = dragStart else { return }
        var f = panel.frame
        f.origin.x = min(max(start.frameX + (mouseX - start.mouseX), area.minX + 8), area.maxX - f.width)
        panel.setFrame(f, display: true)
    }

    private func dragEnded() {
        guard dragStart != nil else { return }
        dragStart = nil
        inset = area.maxX - panel.frame.maxX
        UserDefaults.standard.set(Double(inset), forKey: "tabInsetRight")
    }

    // MARK: NSWindowDelegate

    /// Clicking anywhere else closes the panel, except during setup, when Google's sign-in
    /// window needs to take focus for a moment.
    func windowDidResignKey(_ notification: Notification) {
        guard mode == .open, pinned, store.isConfigured, !store.showSetup else { return }
        collapse()
    }
}
