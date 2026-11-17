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
        case .sky:   return Color(hex: 0xCFE4E7)
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
    static let main = Color(hex: 0x3A3330)
    static let soft = Color(hex: 0x8B7F77)
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
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(paper.color)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            .foregroundStyle(Ink.main)
            // Paper is always light, so fields, cursor and placeholder use light-mode colours.
            .environment(\.colorScheme, .light)
    }
}

/// A finished letter: date, "Dear …," the words in handwriting, and the signature.
struct LetterCard: View {
    @EnvironmentObject var store: NotesStore
    let note: Note
    var large = true

    var body: some View {
        let mine = store.isMine(note)
        let to = firstName(mine ? store.partnerName : store.myName)
        let from = firstName(mine ? store.myName : note.senderName)
        PaperSheet(paper: note.paper, padding: large ? 14 : 11) {
            VStack(alignment: .leading, spacing: large ? 6 : 4) {
                Text(note.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()).lowercased())
                    .font(Theme.mono(9)).foregroundStyle(Ink.soft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if large { Text("Dear \(to),").font(Theme.script(25)) }
                Text(note.text)
                    .font(Theme.hand(large ? 17 : 15))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("— \(from)").font(Theme.script(large ? 22 : 18))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Writing a letter

struct LetterComposer: View {
    @EnvironmentObject var store: NotesStore
    @State private var draft = ""
    @State private var paper = Paper.saved
    @State private var sending = false
    @State private var sent = false
    @State private var sentLabel = "Sent"
    @FocusState private var focused: Bool

    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSheet(paper: paper) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.day().month(.abbreviated)).lowercased())
                        .font(Theme.mono(9)).foregroundStyle(Ink.soft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Dear \(firstName(store.partnerName)),").font(Theme.script(25))
                    TextField("", text: $draft,
                              prompt: Text("write your letter…").foregroundStyle(Ink.soft), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.hand(17))
                        .lineLimit(3...8)
                        .focused($focused)
                        .onSubmit(send)
                    Text("— \(firstName(store.myName))").font(Theme.script(22))
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                        Text("Dear \(firstName(store.myName)),").font(Theme.script(16))
                        Text(note.text).font(Theme.hand(11)).lineLimit(2)
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
