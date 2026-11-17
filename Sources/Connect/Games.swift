import AppKit
import Foundation
import SwiftUI

// MARK: - The games

enum GameKind: String, Codable, CaseIterable, Identifiable {
    case tictactoe, connect4, memory, rps, dots, pong

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tictactoe: return "Tic tac toe"
        case .connect4: return "Connect four"
        case .memory: return "Memory match"
        case .rps: return "Rock paper scissors"
        case .dots: return "Dots & boxes"
        case .pong: return "Pong"
        }
    }

    var emoji: String {
        switch self {
        case .tictactoe: return "🎀"
        case .connect4: return "🫧"
        case .memory: return "🧸"
        case .rps: return "✌️"
        case .dots: return "✏️"
        case .pong: return "🏓"
        }
    }

    var blurb: String {
        switch self {
        case .tictactoe: return "three in a row"
        case .connect4: return "four in a row"
        case .memory: return "find the pairs"
        case .rps: return "first to 3"
        case .dots: return "close the most boxes"
        case .pong: return "first to 5, live"
        }
    }

    /// Soft tile colour in the picker.
    var tint: Color {
        switch self {
        case .tictactoe: return Color(hex: 0xF9D5E2)
        case .connect4: return Color(hex: 0xD3E6F3)
        case .memory: return Color(hex: 0xF6E3C6)
        case .rps: return Color(hex: 0xE2DBF4)
        case .dots: return Color(hex: 0xD8EEDC)
        case .pong: return Color(hex: 0xFBE0CF)
        }
    }
}

/// Player 0 is pink hearts, player 1 is blue hearts.
enum Players {
    static let token = ["💗", "💙"]
    static let color = [Color(hex: 0xEE8FB4), Color(hex: 0x7FB6E3)]
    static let soft = [Color(hex: 0xFBDCE8), Color(hex: 0xD8E9F7)]
}

/// The whole state of one game. Sent in full after every move, so both laptops always agree.
struct Board: Codable, Equatable {
    var kind: GameKind
    /// Emails; index 0 or 1 is how the rest of the state refers to a player.
    var players: [String]
    var starter: Int
    var turn: Int
    /// nil while playing; 0 or 1 won; 2 is a tie.
    var result: Int?
    var scores = [0, 0]
    /// Tic tac toe (9) and connect four (42): -1 empty, else the player.
    var cells: [Int] = []
    var winLine: [Int] = []
    /// Memory: what's on each card, who matched it, which are face up right now.
    var faces: [Int] = []
    var owner: [Int] = []
    var flipped: [Int] = []
    /// Rock paper scissors: this round's picks (-1 = not yet), the last revealed round.
    var picks = [-1, -1]
    var lastPicks = [-1, -1]
    var lastWinner = -1
    var round = 0
    /// Dots & boxes: 24 lines and 9 boxes, -1 or the player who drew/closed it.
    var lines: [Int] = []
    var boxes: [Int] = []

    init(kind: GameKind, players: [String], starter: Int, seed: UInt64) {
        self.kind = kind
        self.players = players
        self.starter = starter
        self.turn = starter
        switch kind {
        case .tictactoe: cells = Array(repeating: -1, count: 9)
        case .connect4: cells = Array(repeating: -1, count: 42)
        case .memory:
            var deck = Array(0..<8) + Array(0..<8)
            var r = Rand(state: seed)
            for i in stride(from: deck.count - 1, to: 0, by: -1) {
                deck.swapAt(i, Int(r.next() * Double(i + 1)) % (i + 1))
            }
            faces = deck
            owner = Array(repeating: -1, count: 16)
        case .rps, .pong: break
        case .dots:
            lines = Array(repeating: -1, count: 24)
            boxes = Array(repeating: -1, count: 9)
        }
    }

    static let memoryFaces = ["🍓", "🌸", "🧸", "🐰", "🍰", "🌈", "⭐️", "🐱"]
    static let rpsHands = ["✊", "✋", "✌️"]
    static let rpsNames = ["rock", "paper", "scissors"]

    private var other: Int { 1 - turn }

    // MARK: Tic tac toe

    mutating func ticTacToe(_ i: Int) -> Bool {
        guard result == nil, cells.indices.contains(i), cells[i] < 0 else { return false }
        cells[i] = turn
        let wins = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
        if let line = wins.first(where: { $0.allSatisfy { cells[$0] == turn } }) {
            winLine = line
            result = turn
        } else if !cells.contains(-1) {
            result = 2
        } else {
            turn = other
        }
        return true
    }

    // MARK: Connect four (7 wide, 6 tall, row 0 at the top)

    mutating func connectFour(column c: Int) -> Bool {
        guard result == nil, (0..<7).contains(c),
              let r = (0..<6).reversed().first(where: { cells[$0 * 7 + c] < 0 }) else { return false }
        cells[r * 7 + c] = turn
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var line = [r * 7 + c]
            for sign in [1, -1] {
                var rr = r + dr * sign, cc = c + dc * sign
                while (0..<6).contains(rr), (0..<7).contains(cc), cells[rr * 7 + cc] == turn {
                    line.append(rr * 7 + cc)
                    rr += dr * sign
                    cc += dc * sign
                }
            }
            if line.count >= 4 {
                winLine = line
                result = turn
                return true
            }
        }
        if !cells.contains(-1) { result = 2 } else { turn = other }
        return true
    }

    // MARK: Memory

    /// Two face-up cards that don't match, waiting to be turned back over.
    var memoryMismatch: Bool { kind == .memory && flipped.count == 2 }

    mutating func flip(_ i: Int) -> Bool {
        guard result == nil, owner.indices.contains(i), owner[i] < 0, !flipped.contains(i), flipped.count < 2
        else { return false }
        flipped.append(i)
        if flipped.count == 2, faces[flipped[0]] == faces[flipped[1]] {
            // A pair: keep it and go again.
            for f in flipped { owner[f] = turn }
            scores[turn] += 1
            flipped = []
            if !owner.contains(-1) { result = scores[0] == scores[1] ? 2 : (scores[0] > scores[1] ? 0 : 1) }
        }
        return true
    }

    mutating func turnBackMismatch() {
        guard memoryMismatch else { return }
        flipped = []
        turn = other
    }

    // MARK: Rock paper scissors (both pick, then it's revealed)

    mutating func rps(player p: Int, pick: Int) {
        guard result == nil, (0..<3).contains(pick), picks[p] < 0 else { return }
        picks[p] = pick
        guard picks[0] >= 0, picks[1] >= 0 else { return }
        let a = picks[0], b = picks[1]
        lastWinner = a == b ? 2 : ((a - b + 3) % 3 == 1 ? 0 : 1)
        if lastWinner < 2 { scores[lastWinner] += 1 }
        lastPicks = picks
        picks = [-1, -1]
        round += 1
        if scores[0] >= 3 { result = 0 } else if scores[1] >= 3 { result = 1 }
    }

    // MARK: Dots & boxes (3×3 boxes; lines 0–11 across, 12–23 down)

    static func boxLines(_ b: Int) -> [Int] {
        let r = b / 3, c = b % 3
        return [r * 3 + c, (r + 1) * 3 + c, 12 + r * 4 + c, 12 + r * 4 + c + 1]
    }

    mutating func drawLine(_ e: Int) -> Bool {
        guard result == nil, lines.indices.contains(e), lines[e] < 0 else { return false }
        lines[e] = turn
        var closed = false
        for b in 0..<9 where boxes[b] < 0 && Self.boxLines(b).contains(e)
            && Self.boxLines(b).allSatisfy({ lines[$0] >= 0 }) {
            boxes[b] = turn
            scores[turn] += 1
            closed = true
        }
        if !boxes.contains(-1) {
            result = scores[0] == scores[1] ? 2 : (scores[0] > scores[1] ? 0 : 1)
        } else if !closed {
            turn = other
        }
        return true
    }
}

// MARK: - Playing together

/// Invites, picking a game and the moves, kept in step with the other laptop over `GameLink`.
@MainActor
final class GameCenter: ObservableObject {
    enum Phase: Equatable { case idle, inviting, invited, lobby, playing, partnerLeft }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partnerOnline = false
    @Published private(set) var board: Board? { didSet { syncPong() } }
    /// The live ball and paddles while playing Pong.
    let pong = PongLive()
    /// A short line for the home screen, like "Abbey can't play right now".
    @Published var notice: String?

    /// Ping arrived (sound + bouncing tab), or the game changed while the panel was shut.
    var onAttentionChange: (() -> Void)?
    var onInvite: (() -> Void)?

    let store: NotesStore
    private let link = GameLink()
    private var sid = ""
    private var seq = 0
    private var lastSeen: Date?
    private var timer: Timer?
    private var room = ""
    private var ticks = 0

    init(store: NotesStore) {
        self.store = store
        link.onConnected = { [weak self] in self?.say("hello") }
        link.onMessage = { [weak self] m in self?.received(m) }
        pong.onHit = { [weak self] b in self?.say("ball", ball: b) }
        pong.onPad = { [weak self] x in self?.say("pad", pad: x) }
        pong.onMiss = { [weak self] p in self?.pongMissed(by: p) }
    }

    var me: String { store.myEmail }
    var partner: String { store.partnerEmail }
    var partnerFirst: String { firstName(store.partnerName) }

    var myIndex: Int { board?.players.firstIndex(of: me) ?? 0 }
    var theirIndex: Int { 1 - myIndex }

    var isMyTurn: Bool {
        guard phase == .playing, let b = board, b.result == nil else { return false }
        if b.kind == .rps { return b.picks[myIndex] < 0 }
        if b.kind == .pong { return false }
        return b.turn == myIndex && !b.memoryMismatch
    }

    /// Something for me to do: a ping to answer, or my move.
    var needsAttention: Bool { phase == .invited || isMyTurn }

    // MARK: Connection

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    private func tick() {
        guard store.isConfigured, let backend = store.backend, !me.isEmpty else {
            link.disconnect()
            room = ""
            setOnline(false)
            return
        }
        let r = GameLink.room(me, partner)
        if r != room {
            room = r
            link.connect(backend: backend, room: r)
        }
        ticks += 1
        if ticks % 2 == 0 { say("hello") }   // every 20s
        setOnline(lastSeen.map { Date().timeIntervalSince($0) < 50 } ?? false)
    }

    private func setOnline(_ on: Bool) {
        if partnerOnline != on { partnerOnline = on }
    }

    private func say(_ t: String, board: Board? = nil, pick: Int? = nil, ball: [Double]? = nil, pad: Double? = nil) {
        guard !me.isEmpty, !partner.isEmpty else { return }
        link.send(GameMsg(t: t, from: me, to: partner, sid: sid.isEmpty ? nil : sid,
                          seq: board == nil ? nil : seq, board: board, pick: pick, ball: ball, pad: pad))
    }

    private func setPhase(_ p: Phase) {
        guard phase != p else { return }
        phase = p
        onAttentionChange?()
    }

    // MARK: Incoming

    private func received(_ m: GameMsg) {
        guard m.to == me, m.from == partner else { return }
        lastSeen = Date()
        setOnline(true)
        let sameSession = m.sid == sid && !sid.isEmpty

        switch m.t {
        case "hello":
            // They just came online: say hi back and catch them up on anything in progress.
            say("here")
            switch phase {
            case .inviting: say("invite")
            case .lobby: say("lobby")
            case .playing:
                if let board {
                    say("board", board: board)
                    if board.kind == .pong, pong.running { say("ball", ball: pong.snapshot) }
                }
            default: break
            }
        case "invite":
            guard let s = m.sid else { return }
            if phase == .inviting {
                // Both pinged at once: that's a yes from both.
                sid = min(sid, s)
                say("accept")
                setPhase(.lobby)
            } else if phase == .idle || phase == .partnerLeft || (phase == .invited && !sameSession) {
                sid = s
                notice = nil
                setPhase(.invited)
                onInvite?()
            }
        case "accept":
            if phase == .inviting, sameSession { setPhase(.lobby) }
        case "decline":
            if phase == .inviting, sameSession {
                notice = "\(partnerFirst) can't play right now 🥺"
                setPhase(.idle)
            }
        case "cancel":
            if phase == .invited, sameSession { setPhase(.idle) }
        case "lobby":
            guard let s = m.sid else { return }
            sid = s
            board = nil
            setPhase(.lobby)
        case "board":
            guard let s = m.sid, let b = m.board, let n = m.seq, b.players.contains(me) else { return }
            // Newer state wins; if both moved at the same moment, the same one wins on both laptops.
            let newer = s != sid || n > seq || (n == seq && m.from < me && b != board)
            guard newer else { return }
            sid = s
            seq = max(seq, n)
            board = b
            setPhase(.playing)
            onAttentionChange?()
        case "rps":
            guard sameSession, let p = m.pick, var b = board else { return }
            b.rps(player: theirIndex, pick: p)
            board = b
            onAttentionChange?()
        case "ball":
            if sameSession, let a = m.ball, board?.kind == .pong { pong.setBall(a) }
        case "pad":
            if sameSession, let x = m.pad { pong.theirPad(x) }
        case "leave":
            if sameSession, phase != .idle {
                board = nil
                setPhase(.partnerLeft)
            }
        default:
            break
        }
    }

    // MARK: Actions

    func invite() {
        sid = UUID().uuidString
        seq = 0
        notice = nil
        setPhase(.inviting)
        say("invite")
    }

    func cancelInvite() {
        say("cancel")
        setPhase(.idle)
    }

    func accept() {
        say("accept")
        setPhase(.lobby)
    }

    func decline() {
        say("decline")
        setPhase(.idle)
    }

    /// Either of you picks a game; the other person goes first.
    func choose(_ kind: GameKind) {
        newBoard(kind, starter: 1)
    }

    func rematch() {
        guard let b = board else { return }
        newBoard(b.kind, starter: 1 - b.starter)
    }

    private func newBoard(_ kind: GameKind, starter: Int) {
        let players = board?.players ?? [me, partner]
        board = Board(kind: kind, players: players, starter: starter, seed: UInt64.random(in: 1...UInt64.max))
        seq += 1
        setPhase(.playing)
        say("board", board: board)
        if kind == .pong { say("ball", ball: pong.serve(toward: starter)) }
        onAttentionChange?()
    }

    // MARK: Pong

    /// Start or stop the live court to match the board.
    private func syncPong() {
        let live = phase == .playing || board != nil
        if let b = board, b.kind == .pong, b.result == nil, live {
            pong.practice = sid == "preview"
            if !pong.running { pong.start(me: myIndex) }
        } else if pong.running {
            pong.stop()
        }
    }

    private func pongMissed(by p: Int) {
        guard var b = board, b.kind == .pong, b.result == nil else { return }
        if pong.practice {
            _ = pong.serve(toward: p)
            return
        }
        b.scores[1 - p] += 1
        if b.scores[1 - p] >= PongLive.winScore { b.result = 1 - p }
        board = b
        seq += 1
        say("board", board: b)
        if b.result == nil { say("ball", ball: pong.serve(toward: p)) }
        onAttentionChange?()
    }

    func otherGames() {
        board = nil
        setPhase(.lobby)
        say("lobby")
    }

    func leave() {
        say("leave")
        board = nil
        sid = ""
        setPhase(.idle)
    }

    func backHome() {
        board = nil
        sid = ""
        setPhase(.idle)
    }

    /// Apply my move and send the new state.
    private func play(_ move: (inout Board) -> Bool) {
        guard isMyTurn, var b = board, move(&b) else { return }
        board = b
        seq += 1
        say("board", board: b)
        onAttentionChange?()
        if b.memoryMismatch {
            // Let both of you see the two cards, then turn them back over.
            let at = seq
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, self.seq == at, var b = self.board, b.memoryMismatch else { return }
                b.turnBackMismatch()
                self.board = b
                self.seq += 1
                self.say("board", board: b)
                self.onAttentionChange?()
            }
        }
    }

    func tapCell(_ i: Int) { play { $0.ticTacToe(i) } }
    func dropDisc(_ c: Int) { play { $0.connectFour(column: c) } }
    func flipCard(_ i: Int) { play { $0.flip(i) } }
    func drawLine(_ e: Int) { play { $0.drawLine(e) } }

    func pickHand(_ h: Int) {
        guard isMyTurn, var b = board, b.kind == .rps else { return }
        b.rps(player: myIndex, pick: h)
        board = b
        say("rps", pick: h)
        onAttentionChange?()
    }

    // MARK: Debug previews (CONNECT_PREVIEW=game-<kind> / invite)

    func preview(_ kind: GameKind?) {
        sid = "preview"
        guard let kind else { setPhase(.invited); return }
        var b = Board(kind: kind, players: [me, partner], starter: 0, seed: 42)
        switch kind {
        case .tictactoe: _ = b.ticTacToe(4); _ = b.ticTacToe(0); _ = b.ticTacToe(2)
        case .connect4: for c in [3, 3, 4, 2, 4, 5] { _ = b.connectFour(column: c) }
        case .memory: if let j = b.faces.indices.first(where: { $0 > 0 && b.faces[$0] == b.faces[0] }) { _ = b.flip(0); _ = b.flip(j) }; _ = b.flip(5)
        case .rps: b.rps(player: 0, pick: 0); b.rps(player: 1, pick: 2); b.rps(player: 1, pick: 1)
        case .dots: for e in [0, 12, 13, 3, 7, 20] { _ = b.drawLine(e) }
        case .pong: b.scores = [2, 1]
        }
        board = b
        setPhase(.playing)
        if kind == .pong { _ = pong.serve(toward: 1) }
    }
}
