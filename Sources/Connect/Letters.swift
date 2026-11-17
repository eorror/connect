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

/// A letter's body: optional "[paper:…]" and "[doodle:…]" lines, then the words.
struct LetterBody {
    var paper = Paper.beige
    var strokes: [[CGPoint]] = []
    var text = ""

    init(_ body: String) {
        var rest = Substring(body)
        while rest.hasPrefix("["), let end = rest.firstIndex(of: "]") {
            let tag = rest[rest.index(after: rest.startIndex)..<end]
            if tag.hasPrefix("paper:") {
                paper = Paper(rawValue: String(tag.dropFirst(6))) ?? .beige
            } else if tag.hasPrefix("doodle:") {
                strokes = Doodle.decode(String(tag.dropFirst(7)))
            } else {
                break
            }
            rest = rest[rest.index(after: end)...].drop(while: { $0 == "\n" })
        }
        text = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Note {
    /// Paper this letter was written on (beige if none was chosen).
    var paper: Paper { LetterBody(body).paper }
    /// Anything drawn on it.
    var doodle: [[CGPoint]] { LetterBody(body).strokes }
    /// The words, without the markers.
    var text: String { LetterBody(body).text }
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
    var doodle: [[CGPoint]] = []
    @ViewBuilder let content: Content

    /// Tall enough to show the lowest point of the drawing.
    private var doodleBottom: CGFloat {
        let maxY = doodle.joined().map(\.y).max() ?? 0
        return maxY > 0 ? (maxY + 24) * Doodle.sheetWidth / Doodle.units : 0
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: doodleBottom, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(paper.color)
                    .overlay(PaperGrain(seed: seed).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            .overlay { if !doodle.isEmpty { DoodleLayer(strokes: doodle) } }
            .foregroundStyle(Ink.main)
            // Paper is always light, so fields, cursor and placeholder use light-mode colours.
            .environment(\.colorScheme, .light)
    }
}

/// A finished letter: "Dear …," in marker, the words in a clean sans, and the signature.
struct LetterCard: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    var large = true

    var body: some View {
        let mine = store.isMine(note)
        let to = firstName(mine ? store.partnerName : store.myName)
        let from = firstName(mine ? store.myName : note.senderName)
        let letter = LetterBody(note.body)
        PaperSheet(paper: letter.paper, padding: large ? 16 : 12, seed: note.id.seed, doodle: letter.strokes) {
            VStack(alignment: .leading, spacing: large ? 6 : 4) {
                Text(note.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()).lowercased())
                    .font(Theme.sans(9.5)).foregroundStyle(Ink.soft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if large {
                    Text("Dear \(to),").font(Theme.marker(30)).padding(.bottom, 2)
                }
                ZStack(alignment: .topLeading) {
                    // Same three-line minimum as the writing box, so a drawing sits where it was drawn.
                    if !letter.strokes.isEmpty { Text("\n\n ").hidden() }
                    Text(letter.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.sans(large ? 13.5 : 12.5))
                .lineSpacing(3)
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

// MARK: - Hand-drawn doodles

/// Drawings travel inside the letter as a "[doodle:x,y x,y|x,y …]" line. Points are in units where
/// the paper is 1000 wide, so they land in the same place on any screen.
enum Doodle {
    static let units: CGFloat = 1000
    /// Paper width inside the panel, used to make room for drawings below the words.
    static let sheetWidth: CGFloat = 270

    static func encode(_ strokes: [[CGPoint]]) -> String {
        strokes.filter { !$0.isEmpty }
            .map { $0.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }.joined(separator: " ") }
            .joined(separator: "|")
    }

    static func decode(_ s: String) -> [[CGPoint]] {
        s.split(separator: "|").map { stroke in
            stroke.split(separator: " ").compactMap { pair -> CGPoint? in
                let c = pair.split(separator: ",")
                guard c.count == 2, let x = Double(c[0]), let y = Double(c[1]) else { return nil }
                return CGPoint(x: x, y: y)
            }
        }
    }

    /// Smooth path through the points (midpoint quad curves), scaled to the paper.
    static func path(_ strokes: [[CGPoint]], scale k: CGFloat) -> Path {
        var p = Path()
        for s in strokes {
            let pts = s.map { CGPoint(x: $0.x * k, y: $0.y * k) }
            guard let first = pts.first else { continue }
            p.move(to: first)
            if pts.count == 1 { p.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)); continue }
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                p.addQuadCurve(to: mid, control: pts[i - 1])
            }
            p.addLine(to: pts[pts.count - 1])
        }
        return p
    }
}

/// Draws strokes in marker brown over the whole sheet.
struct DoodleLayer: View {
    let strokes: [[CGPoint]]
    var body: some View {
        Canvas { ctx, size in
            ctx.stroke(Doodle.path(strokes, scale: size.width / Doodle.units), with: .color(Ink.main),
                       style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Writing a letter

struct LetterComposer: View {
    @EnvironmentObject var store: NotesStore
    @State private var draft = ""
    @State private var paper = Paper.saved
    @State private var doodleSeed = UInt64.random(in: 1...UInt64.max)
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var drawing = false
    @State private var crosshair = false
    @State private var sending = false
    @State private var sent = false
    @State private var sentLabel = "Sent"
    @FocusState private var focused: Bool

    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && strokes.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSheet(paper: paper, padding: 16, seed: doodleSeed,
                       doodle: current.isEmpty ? strokes : strokes + [current]) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now.formatted(.dateTime.day().month(.abbreviated)).lowercased())
                        .font(Theme.sans(9.5)).foregroundStyle(Ink.soft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
            .overlay { if drawing { drawSurface } }
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
                Rectangle().fill(Theme.line).frame(width: 1, height: 14).padding(.horizontal, 2)
                ToolButton(symbol: "scribble.variable", on: drawing, help: drawing ? "Stop drawing" : "Draw on the letter") {
                    drawing.toggle()
                    focused = !drawing
                }
                if !strokes.isEmpty {
                    ToolButton(symbol: "arrow.uturn.backward", help: "Undo last line") { _ = strokes.popLast() }
                }
                Spacer(minLength: 0)
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
        var body = paper.token + "\n"
        if !strokes.isEmpty { body += "[doodle:\(Doodle.encode(strokes))]\n" }
        body += draft
        Task {
            if await store.send(body, replyTo: nil, openAfter: false) {
                draft = ""
                strokes = []
                drawing = false
                doodleSeed = UInt64.random(in: 1...UInt64.max)
                flash("Sent")
            }
            sending = false
        }
    }

    /// Catches the pen while drawing: a dashed edge says "draw here", the crosshair follows the mouse.
    private var drawSurface: some View {
        GeometryReader { g in
            let k = Doodle.units / max(g.size.width, 1)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Ink.soft.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            let p = CGPoint(x: v.location.x * k, y: v.location.y * k)
                            if let last = current.last, hypot(last.x - p.x, last.y - p.y) < 5 { return }
                            current.append(p)
                        }
                        .onEnded { _ in
                            if !current.isEmpty { strokes.append(current) }
                            current = []
                        }
                )
                .onHover { inside in setCrosshair(inside) }
                .onDisappear { setCrosshair(false) }
        }
    }

    private func setCrosshair(_ on: Bool) {
        guard on != crosshair else { return }
        crosshair = on
        if on { NSCursor.crosshair.push() } else { NSCursor.pop() }
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

/// Small round tool button under the letter (pencil, undo); filled when switched on.
struct ToolButton: View {
    let symbol: String
    var on = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Theme.onInk : Theme.ink2)
                .frame(width: 24, height: 24)
                .background(on ? Theme.ink : (hovering ? Theme.glass2 : .clear), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
