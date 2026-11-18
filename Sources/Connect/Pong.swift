import AppKit
import SwiftUI

/// Live Pong: the ball and both paddles, moving 60 times a second.
///
/// Only the important moments travel between laptops. Both laptops move the ball the same way between them.
/// Whoever the ball is heading towards decides whether their paddle hit it, using their own paddle so
/// nothing feels laggy, then sends the new direction (or the point).
/// The court is 1 wide and 1.3 tall. Player 0 defends the bottom and player 1 the top.
/// Each of you sees your own paddle at the bottom.
@MainActor
final class PongLive: ObservableObject {
    static let width = 1.0
    static let height = 1.3
    static let padWidth = 0.26
    static let padInset = 0.07
    static let radius = 0.03
    static let winScore = 5

    @Published private(set) var ball = CGPoint(x: 0.5, y: height / 2)
    /// Paddle centres (x) for player 0 and player 1.
    @Published private(set) var pads = [0.5, 0.5]
    /// Seconds until the ball moves again. Very large means it's waiting for a serve.
    @Published private(set) var waiting = 1e9

    private(set) var running = false
    private(set) var me = 0
    /// Playing alone (debug preview): the other paddle follows the ball.
    var practice = false

    /// I hit it: tell the other laptop where the ball is going.
    var onHit: (([Double]) -> Void)?
    /// Someone missed: the index of who missed.
    var onMiss: ((Int) -> Void)?
    var onPad: ((Double) -> Void)?

    private var vel = CGVector.zero
    private var target = 0.5
    private var theirTarget = 0.5
    private var timer: Timer?
    private var last: CFTimeInterval = 0
    private var lastPadSent: CFTimeInterval = 0
    private var sentPad = 0.5
    private var missedBy: Int?
    private var frozenSince: CFTimeInterval?

    // MARK: Control

    func start(me: Int) {
        self.me = me
        running = true
        ball = CGPoint(x: 0.5, y: Self.height / 2)
        vel = .zero
        waiting = 1e9
        missedBy = nil
        frozenSince = nil
        pads = [0.5, 0.5]
        target = 0.5
        theirTarget = 0.5
        last = CACurrentMediaTime()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        vel = .zero
        waiting = 1e9
    }

    /// Where my mouse is, across the court (0…1, in court terms).
    func move(to x: Double) {
        let half = Self.padWidth / 2
        target = min(max(x, half), Self.width - half)
    }

    func theirPad(_ x: Double) { theirTarget = x }

    /// Ball state as [x, y, vx, vy, wait].
    var snapshot: [Double] { [ball.x, ball.y, vel.dx, vel.dy, min(waiting, 30)] }

    func setBall(_ a: [Double]) {
        guard a.count >= 4 else { return }
        ball = CGPoint(x: a[0], y: a[1])
        vel = CGVector(dx: a[2], dy: a[3])
        waiting = a.count > 4 ? a[4] : 0
        missedBy = nil
        frozenSince = nil
    }

    /// A fresh ball from the middle, heading towards `player`, after a short pause.
    func serve(toward player: Int) -> [Double] {
        let angle = Double.random(in: -0.45...0.45)
        let speed = 0.7
        let s = [0.5, Self.height / 2, speed * sin(angle), (player == 0 ? 1 : -1) * speed * cos(angle), 1.6]
        setBall(s)
        return s
    }

    // MARK: Simulation

    private func step() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.05)
        last = now

        // Paddles: mine follows the mouse, theirs glides to where they said.
        if practice { theirTarget = ball.x }
        let them = 1 - me
        pads[me] += (target - pads[me]) * min(1, dt * 30)
        pads[them] += (theirTarget - pads[them]) * min(1, dt * 14)
        if !practice, abs(pads[me] - sentPad) > 0.004, now - lastPadSent > 0.066 {
            sentPad = pads[me]
            lastPadSent = now
            onPad?(pads[me])
        }

        if waiting > 0 {
            waiting = max(0, waiting - dt)
            return
        }
        if let since = frozenSince {
            // Waiting to hear whether they hit it; if nothing comes, decide here so play never stalls.
            guard now - since > 1.0 else { return }
            frozenSince = nil
            resolveCrossing(at: vel.dy > 0 ? 0 : 1, sendHit: true)
            return
        }

        let r = Self.radius
        var x = ball.x + vel.dx * dt
        var y = ball.y + vel.dy * dt
        if x < r { x = 2 * r - x; vel.dx = -vel.dx }
        if x > Self.width - r { x = 2 * (Self.width - r) - x; vel.dx = -vel.dx }

        let toward = vel.dy > 0 ? 0 : 1
        let contact = toward == 0 ? Self.height - Self.padInset - r : Self.padInset + r
        let crossed = toward == 0 ? (ball.y < contact && y >= contact) : (ball.y > contact && y <= contact)

        if crossed, missedBy == nil {
            ball = CGPoint(x: x, y: contact)
            if toward == me || practice {
                resolveCrossing(at: toward, sendHit: toward == me && !practice)
            } else {
                frozenSince = now
            }
            return
        }

        ball = CGPoint(x: x, y: y)
        if let p = missedBy, y > Self.height + 3 * r || y < -3 * r {
            missedBy = nil
            vel = .zero
            waiting = 1e9
            onMiss?(p)
        }
    }

    /// The ball has reached `player`'s paddle line: bounce it back, or let it through.
    private func resolveCrossing(at player: Int, sendHit: Bool) {
        let reach = Self.padWidth / 2 + Self.radius
        let offset = (ball.x - pads[player]) / reach
        guard abs(offset) <= 1 else {
            missedBy = player
            return
        }
        let speed = min(hypot(vel.dx, vel.dy) * 1.07, 1.9)
        let angle = offset * 1.0
        vel = CGVector(dx: speed * sin(angle), dy: (player == 0 ? -1 : 1) * speed * cos(angle))
        if sendHit { onHit?(snapshot) }
    }
}

// MARK: - Court

struct PongBoard: View {
    @EnvironmentObject var games: GameCenter
    @ObservedObject var live: PongLive
    let board: Board

    private let w: CGFloat = 250
    private var h: CGFloat { w * PongLive.height }

    var body: some View {
        let me = games.myIndex
        ZStack {
            // Court
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x18181B))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            Path { p in p.move(to: CGPoint(x: 10, y: h / 2)); p.addLine(to: CGPoint(x: w - 10, y: h / 2)) }
                .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))

            // Scores, big and faint, in each half
            Text("\(board.scores[1 - me])").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.18))
                .position(x: w / 2, y: h * 0.27)
            Text("\(board.scores[me])").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.18))
                .position(x: w / 2, y: h * 0.73)

            // Paddles
            paddle(for: 1 - me)
            paddle(for: me)

            // Ball
            Rectangle().fill(.white)
                .frame(width: 2 * PongLive.radius * w, height: 2 * PongLive.radius * w)
                .position(view(live.ball))
                .opacity(board.result == nil ? 1 : 0)

            if board.result == nil, live.waiting > 0 {
                Text(live.waiting > 100 ? "…" : live.waiting > 0.8 ? "Ready?" : "Go!")
                    .font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color(hex: 0x18181B))
                    .position(x: w / 2, y: h / 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active(let p) = phase { aim(p.x) }
        }
        .gesture(DragGesture(minimumDistance: 0).onChanged { aim($0.location.x) })
        .environment(\.colorScheme, .light)
    }

    private func paddle(for p: Int) -> some View {
        let y = p == 0 ? PongLive.height - PongLive.padInset : PongLive.padInset
        return Rectangle()
            .fill(p == games.myIndex ? Color.white : Color.white.opacity(0.75))
            .frame(width: PongLive.padWidth * w, height: 8)
            .position(view(CGPoint(x: live.pads[p], y: y)))
    }

    /// Court point → where it sits on screen (turned round for player 1, so you're always at the bottom).
    private func view(_ c: CGPoint) -> CGPoint {
        let s = w / PongLive.width
        return games.myIndex == 0
            ? CGPoint(x: c.x * s, y: c.y * s)
            : CGPoint(x: (PongLive.width - c.x) * s, y: (PongLive.height - c.y) * s)
    }

    private func aim(_ viewX: CGFloat) {
        let x = Double(viewX / w) * PongLive.width
        live.move(to: games.myIndex == 0 ? x : PongLive.width - x)
    }
}
