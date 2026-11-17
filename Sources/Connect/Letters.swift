import AppKit
import SwiftUI

// MARK: - Paper

/// Letter paper colours. The choice travels with the letter as a "[paper:name]" first line,
/// so the database doesn't need to change.
enum Paper: String, CaseIterable, Identifiable {
    case beige, rose, sky, lilac, mint, white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .beige: return Color(hex: 0xF3E8D4)
        case .rose:  return Color(hex: 0xF7CFDF)
        case .sky:   return Color(hex: 0xC9DEE4)
        case .lilac: return Color(hex: 0xE3DCF4)
        case .mint:  return Color(hex: 0xD9ECDD)
        case .white: return Color(hex: 0xFBFAF6)
        }
    }

    /// Envelope colour that sits nicely against this paper.
    var envelope: Color { self == .sky ? Color(hex: 0xEBDDC4) : Color(hex: 0xBFD8DC) }

    var token: String { "[paper:\(rawValue)]" }

    static var saved: Paper {
        get { Paper(rawValue: UserDefaults.standard.string(forKey: "paper") ?? "") ?? .beige }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "paper") }
    }
}

/// Ink is the same on every paper, since paper is always light.
enum Ink {
    static let main = Color(hex: 0x5A3933)   // warm brown marker
    static let soft = Color(hex: 0x977A70)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension Note {
    /// Paper this letter was written on (beige if none was chosen).
    var paper: Paper {
        guard body.hasPrefix("[paper:"), let end = body.firstIndex(of: "]") else { return .beige }
        return Paper(rawValue: String(body[body.index(body.startIndex, offsetBy: 7)..<end])) ?? .beige
    }

    /// The words, without the paper marker.
    var text: String {
        guard body.hasPrefix("[paper:"), let end = body.firstIndex(of: "]") else { return body }
        return String(body[body.index(after: end)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func firstName(_ name: String) -> String {
    let n = name.split(separator: " ").first.map(String.init) ?? name
    return n.prefix(1).uppercased() + n.dropFirst()
}

// MARK: - Letter pieces

/// A sheet of letter paper.
struct PaperSheet<Content: View>: View {
    let paper: Paper
    var padding: CGFloat = 14
    var seed: UInt64 = 1
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(paper.color)
                    .overlay(PaperGrain(seed: seed).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            .foregroundStyle(Ink.main)
            // Paper is always light, so fields, cursor and placeholder use light-mode colours.
            .environment(\.colorScheme, .light)
    }
}

/// A finished letter: doodles, "Dear …," in marker, the words in a clean sans, and the signature.
struct LetterCard: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    var large = true

    var body: some View {
        let mine = store.isMine(note)
        let to = firstName(mine ? store.partnerName : store.myName)
        let from = firstName(mine ? store.myName : note.senderName)
        PaperSheet(paper: note.paper, padding: large ? 16 : 12, seed: note.id.seed) {
            VStack(alignment: .leading, spacing: large ? 6 : 4) {
                Text(note.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()).lowercased())
                    .font(Theme.sans(9.5)).foregroundStyle(Ink.soft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if large {
                    Doodles(seed: note.id.seed).frame(height: 42)
                    Text("Dear \(to),").font(Theme.marker(30)).padding(.bottom, 2)
                }
                Text(note.text)
                    .font(Theme.sans(large ? 13.5 : 12.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("love, \(from.lowercased())").font(Theme.marker(large ? 23 : 19))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
        }
    }
}

extension UUID {
    /// Stable number from the id, so a letter always gets the same doodles and grain.
    var seed: UInt64 {
        withUnsafeBytes(of: uuid) { $0.load(as: UInt64.self) } | 1
    }
}

/// Tiny deterministic random numbers (SplitMix64).
struct Rand {
    var state: UInt64
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

/// Soft speckle so the paper reads as paper, not a flat fill.
struct PaperGrain: View {
    let seed: UInt64
    var body: some View {
        Canvas { ctx, size in
            var r = Rand(state: seed)
            let count = Int(size.width * size.height / 70)
            for _ in 0..<count {
                let x = r.range(0, size.width), y = r.range(0, size.height)
                let d = r.range(0.5, 1.5)
                let dark = r.next() < 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                         with: .color(dark ? .black.opacity(r.range(0.03, 0.08)) : .white.opacity(r.range(0.2, 0.45))))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Doodles

/// A band of hand-drawn doodles (clouds, sun, hearts, flowers, sparkles) in marker brown.
struct Doodles: View {
    let seed: UInt64

    enum Kind: CaseIterable { case cloud, sun, heart, flower, sparkle }

    var body: some View {
        Canvas { ctx, size in
            var r = Rand(state: seed &* 31)
            let extra: [Kind] = [.heart, .flower, .sparkle]
            var kinds: [Kind] = [.cloud, .cloud, .sun, extra[Int(r.next() * 3) % 3]]
            // Shuffle the four into the four slots.
            for i in stride(from: kinds.count - 1, to: 0, by: -1) {
                kinds.swapAt(i, Int(r.next() * Double(i + 1)) % (i + 1))
            }
            let slots: [(Double, Double)] = [(0.10, 0.62), (0.37, 0.30), (0.63, 0.66), (0.88, 0.32)]
            for (kind, slot) in zip(kinds, slots) {
                let cx = (slot.0 + r.range(-0.04, 0.04)) * size.width
                let cy = (slot.1 + r.range(-0.12, 0.12)) * size.height
                let h: CGFloat = kind == .cloud ? r.range(21, 25) : r.range(17, 21)
                let w: CGFloat = kind == .cloud ? h * 1.6 : h
                var c = ctx
                c.translateBy(x: cx, y: cy)
                c.rotate(by: .degrees(r.range(-10, 10)))
                let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                c.stroke(Self.path(kind, in: rect), with: .color(Ink.main),
                         style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }

    static func path(_ kind: Kind, in r: CGRect) -> Path {
        var p = Path()
        let h = r.height
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * h, y: r.minY + y * h) }
        /// Arc over the top, from angle a down to b (degrees, maths convention, y up).
        func arc(_ cx: Double, _ cy: Double, _ rad: Double, _ a: Double, _ b: Double, start: Bool = false) {
            let steps = 14
            for i in 0...steps {
                let t = (a + (b - a) * Double(i) / Double(steps)) * .pi / 180
                let q = pt(cx + rad * cos(t), cy - rad * sin(t))
                if start && i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
        }
        switch kind {
        case .cloud:
            arc(0.38, 0.64, 0.28, 215, 80, start: true)
            arc(0.80, 0.44, 0.36, 160, 20)
            arc(1.22, 0.62, 0.28, 110, -35)
            p.closeSubpath()
            // a little curl inside, like the reference
            arc(0.80, 0.62, 0.12, 180, 20, start: true)
        case .sun:
            let c = pt(0.5, 0.5)
            p.addEllipse(in: CGRect(x: c.x - h * 0.2, y: c.y - h * 0.2, width: h * 0.4, height: h * 0.4))
            for i in 0..<8 {
                let t = Double(i) * .pi / 4 + 0.2
                p.move(to: CGPoint(x: c.x + cos(t) * h * 0.33, y: c.y + sin(t) * h * 0.33))
                p.addLine(to: CGPoint(x: c.x + cos(t) * h * 0.5, y: c.y + sin(t) * h * 0.5))
            }
        case .heart:
            p.move(to: pt(0.5, 0.92))
            p.addCurve(to: pt(0.06, 0.34), control1: pt(0.25, 0.75), control2: pt(0.0, 0.58))
            p.addCurve(to: pt(0.5, 0.26), control1: pt(0.12, 0.04), control2: pt(0.42, 0.04))
            p.addCurve(to: pt(0.94, 0.34), control1: pt(0.58, 0.04), control2: pt(0.88, 0.04))
            p.addCurve(to: pt(0.5, 0.92), control1: pt(1.0, 0.58), control2: pt(0.75, 0.75))
        case .flower:
            let c = pt(0.5, 0.5)
            for i in 0..<5 {
                let t = Double(i) * 2 * .pi / 5 - .pi / 2
                let pc = CGPoint(x: c.x + cos(t) * h * 0.27, y: c.y + sin(t) * h * 0.27)
                p.addEllipse(in: CGRect(x: pc.x - h * 0.17, y: pc.y - h * 0.17, width: h * 0.34, height: h * 0.34))
            }
            p.addEllipse(in: CGRect(x: c.x - h * 0.08, y: c.y - h * 0.08, width: h * 0.16, height: h * 0.16))
        case .sparkle:
            let c = pt(0.5, 0.5)
            p.move(to: pt(0.5, 0.0))
            p.addQuadCurve(to: pt(1.0, 0.5), control: c)
            p.addQuadCurve(to: pt(0.5, 1.0), control: c)
            p.addQuadCurve(to: pt(0.0, 0.5), control: c)
            p.addQuadCurve(to: pt(0.5, 0.0), control: c)
        }
        return p
    }
}

// MARK: - Writing a letter

struct LetterComposer: View {
    @EnvironmentObject var store: NotesStore
    @State private var draft = ""
    @State private var paper = Paper.saved
    @State private var doodleSeed = UInt64.random(in: 1...UInt64.max)
    @State private var sending = false
    @State private var sent = false
    @State private var sentLabel = "Sent"
    @FocusState private var focused: Bool

    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSheet(paper: paper, padding: 16, seed: doodleSeed) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now.formatted(.dateTime.day().month(.abbreviated)).lowercased())
                        .font(Theme.sans(9.5)).foregroundStyle(Ink.soft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Doodles(seed: doodleSeed).frame(height: 42)
                    Text("Dear \(firstName(store.partnerName)),").font(Theme.marker(30)).padding(.bottom, 2)
                    TextField("", text: $draft,
                              prompt: Text("write your letter…").foregroundStyle(Ink.soft), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(13.5))
                        .lineSpacing(3)
                        .lineLimit(3...8)
                        .focused($focused)
                        .onSubmit(send)
                    Text("love, \(firstName(store.myName).lowercased())").font(Theme.marker(23))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                }
            }
            .animation(.easeOut(duration: 0.2), value: paper)

            HStack(spacing: 5) {
                ForEach(Paper.allCases) { p in
                    Circle().fill(p.color)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: paper == p ? 1.5 : 0).padding(-3))
                        .frame(width: 15, height: 15)
                        .contentShape(Circle())
                        .onTapGesture { paper = p; Paper.saved = p }
                        .help(p.rawValue.capitalized)
                }
                Spacer()
                if sent {
                    Label(sentLabel, systemImage: "checkmark").font(Theme.sans(11, .semibold))
                        .foregroundStyle(Theme.ink2).transition(.opacity)
                }
                Button(sending ? "Sending…" : "Send") { send() }
                    .buttonStyle(.pill)
                    .disabled(sending || empty)
            }
            .padding(.horizontal, 3)

            Rectangle().fill(Theme.line).frame(height: 1)
            EmoteBar { sendEmote($0) }
                .disabled(sending)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .reportHeight()
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }

    private func send() {
        guard !sending, !empty else { return }
        sending = true
        let body = paper.token + "\n" + draft
        Task {
            if await store.send(body, replyTo: nil, openAfter: false) {
                draft = ""
                doodleSeed = UInt64.random(in: 1...UInt64.max)
                flash("Sent")
            }
            sending = false
        }
    }

    private func sendEmote(_ e: Emote) {
        guard !sending else { return }
        sending = true
        Task {
            if await store.send(e.token, replyTo: nil, openAfter: false) { flash("Sent \(e.symbol)") }
            sending = false
        }
    }

    private func flash(_ label: String) {
        sentLabel = label
        withAnimation { sent = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { sent = false }
        }
    }
}

// MARK: - Envelope

/// Flat envelope drawing: body, front pocket, flap that can open, and a heart seal.
struct Envelope: View {
    var color: Color
    var flapOpen: Double = 0          // 0 closed … 1 fully open
    var showSeal = true

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.92))
                Pocket().fill(color)
                    .overlay(Pocket().stroke(Color.black.opacity(0.08), lineWidth: 1))
                Flap()
                    .fill(color.shade(0.94))
                    .overlay(Flap().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .frame(height: h * 0.58)
                    .overlay(alignment: .bottom) {
                        if showSeal && flapOpen < 0.5 {
                            Image(systemName: "heart.fill")
                                .font(.system(size: max(6, w * 0.08)))
                                .foregroundStyle(.white)
                                .frame(width: w * 0.16, height: w * 0.16)
                                .background(Color(hex: 0xD9576F), in: Circle())
                                .offset(y: w * 0.06)
                        }
                    }
                    .rotation3DEffect(.degrees(180 * flapOpen), axis: (x: 1, y: 0, z: 0),
                                      anchor: .top, perspective: 0.4)
                    .zIndex(flapOpen > 0.5 ? -1 : 1)
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        }
    }

    private struct Pocket: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.68))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }

    private struct Flap: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}

extension Color {
    func shade(_ k: Double) -> Color {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return Color(.sRGB, red: c.redComponent * k, green: c.greenComponent * k, blue: c.blueComponent * k, opacity: 1)
    }
}

/// Plays once over a letter that's just arrived: the envelope's flap lifts, the letter slides
/// up and out, then it hands over to the letter itself.
struct EnvelopeOpening: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    let done: () -> Void
    @State private var flap = 0.0
    @State private var rise: CGFloat = 0
    @State private var fade = 1.0

    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width - 60, 210)
            let h = w * 0.62
            ZStack {
                // Envelope back, letter, then the front pocket on top so the letter looks inside.
                Envelope(color: note.paper.envelope, flapOpen: flap, showSeal: true)
                    .frame(width: w, height: h)
                PaperSheet(paper: note.paper, padding: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dear \(firstName(store.myName)),").font(Theme.marker(17))
                        Text(note.text).font(Theme.sans(9.5)).lineLimit(2)
                    }
                }
                .frame(width: w - 20, height: h - 14)
                .offset(y: -rise)
                .mask(alignment: .bottom) {
                    // Hide the part of the letter still inside the envelope pocket.
                    Rectangle().frame(height: h * 0.68 + rise + 200).offset(y: -h * 0.32 + 100)
                }
                EnvelopePocketFront(color: note.paper.envelope)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
            }
            .frame(width: g.size.width, height: g.size.height)
            .offset(y: 34 + rise * 0.2)
        }
        .opacity(fade)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.45)) { flap = 1 }
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { rise = 70 }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeIn(duration: 0.25)) { fade = 0 }
            try? await Task.sleep(for: .milliseconds(250))
            done()
        }
    }
}

/// Just the front pocket of the envelope, drawn over the letter while it slides out.
private struct EnvelopePocketFront: View {
    let color: Color
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            Path { p in
                p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
                p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.68))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.closeSubpath()
            }
            .fill(color)
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
                    p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.68))
                    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
                }
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

/// The little envelope on the top tab when a letter is waiting: hops every couple of seconds
/// with a red count badge.
struct JumpingEnvelope: View {
    let count: Int
    let color: Color

    var body: some View {
        PhaseAnimator([0.0, -7.0, 0.0, -3.0, 0.0, 0.0, 0.0]) { y in
            Envelope(color: color, showSeal: true)
                .frame(width: 32, height: 21)
                .rotationEffect(.degrees(y * 0.8))
                .offset(y: y)
                .overlay(alignment: .topTrailing) {
                    Text("\(count)")
                        .font(Theme.sans(9, .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Color(hex: 0xE5484D), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                        .offset(x: 7, y: -7 + y)
                }
        } animation: { y in
            y == 0 ? .spring(response: 0.25, dampingFraction: 0.5) : .easeOut(duration: 0.16)
        }
    }
}
