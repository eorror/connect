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

// MARK: - Burst animation

/// A small click-through window over the note that the emote bursts out of.
@MainActor
final class EmoteOverlay {
    private var window: NSWindow?
    private var closeWork: DispatchWorkItem?
    private let side: CGFloat = 640

    /// `point` is the burst centre in screen coordinates (the middle of the note).
    func play(_ emote: Emote, at point: NSPoint) {
        closeWork?.cancel()
        window?.orderOut(nil)

        let frame = NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.contentView = NSHostingView(rootView: EmoteBurst(emote: emote, side: side))
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
        window = w

        let work = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + EmoteBurst.length + 0.15, execute: work)
    }
}

/// Emoji popping out of the middle in every direction (mostly up), then falling and fading.
struct EmoteBurst: View {
    static let length: Double = 1.9

    let emote: Emote
    let side: CGFloat
    @State private var start = Date()
    @State private var bits: [Bit] = []

    struct Bit {
        let symbol: String
        let vx: CGFloat
        let vy: CGFloat
        let delay: Double
        let life: Double
        let fontSize: CGFloat
        let spin: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, canvas in
                let c0 = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let gravity: CGFloat = 620
                for b in bits {
                    let age = t - b.delay
                    guard age > 0, age < b.life else { continue }
                    let a = CGFloat(age)
                    let x = c0.x + b.vx * a
                    let y = c0.y + b.vy * a + 0.5 * gravity * a * a
                    let p = age / b.life
                    let pop = min(1, age / 0.12)              // grows in quickly
                    let fade = p > 0.6 ? (1 - p) / 0.4 : 1    // fades out at the end
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(b.spin * age))
                    c.scaleBy(x: 0.4 + 0.6 * pop, y: 0.4 + 0.6 * pop)
                    c.draw(Text(b.symbol).font(.system(size: b.fontSize)), at: .zero)
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .onAppear {
            start = Date()
            bits = (0..<26).map { _ in
                // Mostly upward: angle around straight up (-90°), spread ±80°.
                let angle = (-90 + Double.random(in: -80...80)) * .pi / 180
                let speed = CGFloat.random(in: 220...440)
                return Bit(symbol: emote.particles.randomElement()!,
                           vx: cos(angle) * speed,
                           vy: sin(angle) * speed,
                           delay: .random(in: 0...0.12),
                           life: .random(in: 1.2...1.75),
                           fontSize: .random(in: 18...32),
                           spin: .random(in: -120...120))
            }
        }
    }
}

// MARK: - Picker

/// The row of emote buttons under the note box.
struct EmoteBar: View {
    let onSend: (Emote) -> Void
    var body: some View {
        HStack(spacing: 2) {
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
                .font(.system(size: 15))
                .frame(width: 30, height: 24)
                .background(hovering ? Theme.glass2 : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .scaleEffect(hovering ? 1.15 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
        .help("Send \(emote.phrase)")
    }
}
