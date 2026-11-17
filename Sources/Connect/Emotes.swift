import AppKit
import SwiftUI

/// Little things you can send instead of words. They travel as ordinary notes whose body is
/// "[emote:<name>]", so the database doesn't need to change.
enum Emote: String, CaseIterable, Identifiable {
    case hearts, flowers, kisses, sparkles, sunflower, hug

    var id: String { rawValue }

    /// Shown on the button and in the list.
    var symbol: String {
        switch self {
        case .hearts: return "❤️"
        case .flowers: return "🌸"
        case .kisses: return "💋"
        case .sparkles: return "✨"
        case .sunflower: return "🌻"
        case .hug: return "🤗"
        }
    }

    /// What falls across the screen when it's opened.
    var particles: [String] {
        switch self {
        case .hearts: return ["❤️", "💕", "💗", "💖", "❤️"]
        case .flowers: return ["🌸", "🌷", "🌹", "🌼", "💐"]
        case .kisses: return ["💋", "😘", "💋", "💕"]
        case .sparkles: return ["✨", "⭐️", "🌟", "💫"]
        case .sunflower: return ["🌻", "🌻", "🌼", "☀️"]
        case .hug: return ["🤗", "🫶", "💞", "🧸"]
        }
    }

    /// "Abbey sent you flowers"
    var phrase: String {
        switch self {
        case .hearts: return "hearts"
        case .flowers: return "flowers"
        case .kisses: return "kisses"
        case .sparkles: return "sparkles"
        case .sunflower: return "a sunflower"
        case .hug: return "a hug"
        }
    }

    var token: String { "[emote:\(rawValue)]" }

    init?(body: String) {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard b.hasPrefix("[emote:"), b.hasSuffix("]") else { return nil }
        self.init(rawValue: String(b.dropFirst(7).dropLast()))
    }
}

extension Note {
    var emote: Emote? { Emote(body: body) }
}

// MARK: - Full-screen animation

/// A click-through window over the whole screen that rains the emote for a few seconds.
@MainActor
final class EmoteOverlay {
    private var window: NSWindow?
    private var closeWork: DispatchWorkItem?

    func play(_ emote: Emote) {
        guard let screen = NSScreen.main else { return }
        closeWork?.cancel()
        window?.orderOut(nil)

        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.contentView = NSHostingView(rootView: EmoteRain(emote: emote, size: screen.frame.size))
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w

        let work = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + EmoteRain.length + 0.2, execute: work)
    }
}

/// Emoji drifting down from the top with a little sway and spin, fading at the end.
struct EmoteRain: View {
    static let length: Double = 4.2

    let emote: Emote
    let size: CGSize
    @State private var start = Date()
    @State private var drops: [Drop] = []

    struct Drop {
        let symbol: String
        let x: CGFloat
        let delay: Double
        let fall: Double
        let fontSize: CGFloat
        let sway: CGFloat
        let swaySpeed: Double
        let spin: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, canvas in
                for d in drops {
                    let p = (t - d.delay) / d.fall
                    guard p > 0, p < 1 else { continue }
                    let y = -60 + (canvas.height + 120) * CGFloat(p)
                    let x = d.x + sin((t - d.delay) * d.swaySpeed) * d.sway
                    let fade = p > 0.75 ? (1 - p) / 0.25 : min(1, p / 0.08)
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(d.spin * (t - d.delay)))
                    c.draw(Text(d.symbol).font(.system(size: d.fontSize)), at: .zero)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .onAppear {
            start = Date()
            drops = (0..<70).map { _ in
                Drop(symbol: emote.particles.randomElement()!,
                     x: .random(in: 0...size.width),
                     delay: .random(in: 0...1.6),
                     fall: .random(in: 2.0...2.6),
                     fontSize: .random(in: 26...54),
                     sway: .random(in: 10...40),
                     swaySpeed: .random(in: 1.5...3.5),
                     spin: .random(in: -40...40))
            }
        }
    }
}

// MARK: - Picker

/// The row of emote buttons under the note box.
struct EmoteBar: View {
    let onSend: (Emote) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Emote.allCases) { e in EmoteButton(emote: e) { onSend(e) } }
        }
    }
}

private struct EmoteButton: View {
    let emote: Emote
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(emote.symbol)
                .font(.system(size: 18))
                .frame(width: 34, height: 30)
                .background(hovering ? Theme.glass2 : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .scaleEffect(hovering ? 1.15 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
        .help("Send \(emote.phrase)")
    }
}
