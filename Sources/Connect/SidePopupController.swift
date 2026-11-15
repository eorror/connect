import AppKit
import SwiftUI

/// The little card that slides in from the right edge of the screen when a note arrives.
@MainActor
final class SidePopupController {
    var onOpen: ((Note) -> Void)?
    private var panel: NSPanel?
    private let size = NSSize(width: 330, height: 100)

    func show(notes: [Note]) {
        guard let latest = notes.last, let screen = NSScreen.main else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: PopupView(
            notes: notes,
            onOpen: { [weak self] in self?.onOpen?(latest) },
            onDismiss: { [weak self] in self?.hide() }
        ))

        let area = screen.visibleFrame
        let shown = NSRect(x: area.maxX - size.width - 16,
                           y: area.minY + area.height * 0.62,
                           width: size.width, height: size.height)

        if !panel.isVisible {
            panel.setFrame(shown.offsetBy(dx: size.width + 40, dy: 0), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(shown, display: true)
            panel.animator().alphaValue = 1
        }
        NSSound(named: "Purr")?.play()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        let out = panel.frame.offsetBy(dx: size.width + 40, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(out, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        return p
    }
}
