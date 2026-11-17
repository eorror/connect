import SwiftUI

// MARK: - Screen

/// Everything games-related in the panel, by phase.
struct GamesScreen: View {
    @EnvironmentObject var games: GameCenter

    var body: some View {
        Group {
            switch games.phase {
            case .idle: GamesHome()
            case .inviting: WaitingCard()
            case .invited: InvitedCard()
            case .lobby: GamePicker()
            case .playing: GamePlay()
            case .partnerLeft: LeftCard()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .reportHeight()
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: games.phase)
    }
}

// MARK: - Bits

/// Big soft capsule button.
struct CuteButtonStyle: ButtonStyle {
    var color = Players.color[0]
    var filled = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(13, .semibold))
            .foregroundStyle(filled ? .white : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(filled ? color : Theme.glass2)
                    .overlay(Capsule().strokeBorder(filled ? .white.opacity(0.35) : Theme.line, lineWidth: 1))
                    .shadow(color: filled ? color.opacity(0.45) : .clear, radius: 6, y: 3)
            }
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// "Abbey's here" / "Abbey's away" with a little dot.
struct PresencePill: View {
    @EnvironmentObject var games: GameCenter
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(games.partnerOnline ? Color(hex: 0x5BC48A) : Theme.ink3.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(games.partnerOnline ? "\(games.partnerFirst)'s here" : "\(games.partnerFirst)'s away")
                .font(Theme.sans(11, .medium)).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.glass2, in: Capsule())
    }
}

/// An emoji that keeps doing a happy little wiggle.
struct Wiggle: View {
    let text: String
    var size: CGFloat = 40
    var body: some View {
        PhaseAnimator([0.0, -10.0, 8.0, -4.0, 0.0, 0.0]) { a in
            Text(text).font(.system(size: size))
                .rotationEffect(.degrees(a))
                .offset(y: a == 0 ? 0 : -3)
        } animation: { _ in .spring(response: 0.22, dampingFraction: 0.55) }
    }
}

/// Three hearts bouncing in turn, for waiting.
struct BouncingHearts: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                PhaseAnimator([0.0, -8.0, 0.0]) { y in
                    Text(Players.token[i % 2]).font(.system(size: 18)).offset(y: y)
                } animation: { y in
                    y == 0 ? .easeIn(duration: 0.25) : .easeOut(duration: 0.25).delay(Double(i) * 0.15)
                }
            }
        }
    }
}

// MARK: - Before playing

struct GamesHome: View {
    @EnvironmentObject var games: GameCenter

    var body: some View {
        VStack(spacing: 10) {
            PresencePill()
            Wiggle(text: "🎮")
            Text("Play something together?").font(Theme.marker(24))
            Text("Send \(games.partnerFirst) a little ping. When they say yes, pick a game and play live from your own laptops.")
                .font(Theme.sans(11.5)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { games.invite() } label: {
                Label("Ask \(games.partnerFirst) to play", systemImage: "heart.fill")
            }
            .buttonStyle(CuteButtonStyle())
            .padding(.top, 2)
            if let notice = games.notice {
                Text(notice).font(Theme.sans(11)).foregroundStyle(Theme.ink2).transition(.opacity)
            }
            HStack(spacing: 8) {
                ForEach(GameKind.allCases) { k in
                    Text(k.emoji).font(.system(size: 15))
                        .frame(width: 30, height: 30)
                        .background(k.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .help(k.name)
                }
            }
            .padding(.top, 4)
        }
    }
}

struct WaitingCard: View {
    @EnvironmentObject var games: GameCenter
    var body: some View {
        VStack(spacing: 10) {
            PresencePill()
            BouncingHearts().padding(.top, 6)
            Text("Waiting for \(games.partnerFirst)…").font(Theme.marker(22))
            Text(games.partnerOnline ? "Their laptop is pinging now ✨"
                 : "They're away, so they'll get it as soon as they're back.")
                .font(Theme.sans(11)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Never mind") { games.cancelInvite() }
                .buttonStyle(CuteButtonStyle(filled: false))
        }
    }
}

struct InvitedCard: View {
    @EnvironmentObject var games: GameCenter
    var body: some View {
        VStack(spacing: 10) {
            Wiggle(text: "💌", size: 44)
            Text("\(games.partnerFirst) wants to play!").font(Theme.marker(26))
            Text("Say yes and you'll pick a game together.")
                .font(Theme.sans(11.5)).foregroundStyle(Theme.ink2)
            HStack(spacing: 8) {
                Button("Let's play! 🎮") { games.accept() }.buttonStyle(CuteButtonStyle())
                Button("Not now") { games.decline() }.buttonStyle(CuteButtonStyle(filled: false))
            }
            .padding(.top, 2)
        }
    }
}

struct GamePicker: View {
    @EnvironmentObject var games: GameCenter
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            Text("Pick a game").font(Theme.marker(24))
            Text("Either of you can choose. \(games.partnerFirst) is looking too 👀")
                .font(Theme.sans(11)).foregroundStyle(Theme.ink2)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(GameKind.allCases) { k in GameTile(kind: k) { games.choose(k) } }
            }
            Button("Leave") { games.leave() }
                .buttonStyle(.plain).font(Theme.sans(11, .medium)).foregroundStyle(Theme.ink3)
        }
    }
}

private struct GameTile: View {
    let kind: GameKind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(kind.emoji).font(.system(size: 24))
                Text(kind.name).font(Theme.sans(11.5, .semibold)).foregroundStyle(Ink.main)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(kind.blurb).font(Theme.sans(9.5)).foregroundStyle(Ink.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(kind.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 6 : 3, y: 2)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
    }
}

struct LeftCard: View {
    @EnvironmentObject var games: GameCenter
    var body: some View {
        VStack(spacing: 10) {
            Text("🫶").font(.system(size: 38))
            Text("\(games.partnerFirst) left the game").font(Theme.marker(22))
            Button("OK") { games.backHome() }.buttonStyle(CuteButtonStyle())
        }
    }
}

// MARK: - Playing

struct GamePlay: View {
    @EnvironmentObject var games: GameCenter

    var body: some View {
        if let b = games.board {
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    PlayerChip(name: "You", index: games.myIndex, score: b.scores[games.myIndex],
                               showScore: showsScore(b), active: activeIndex(b) == games.myIndex)
                    Spacer()
                    PlayerChip(name: games.partnerFirst, index: games.theirIndex, score: b.scores[games.theirIndex],
                               showScore: showsScore(b), active: activeIndex(b) == games.theirIndex)
                }
                Text(status(b))
                    .font(Theme.marker(b.result == nil ? 20 : 25))
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: status(b))

                Group {
                    switch b.kind {
                    case .tictactoe: TicTacToeBoard(board: b)
                    case .connect4: ConnectFourBoard(board: b)
                    case .memory: MemoryBoard(board: b)
                    case .rps: RPSBoard(board: b)
                    case .dots: DotsBoard(board: b)
                    }
                }
                .padding(.vertical, 2)

                if b.result != nil {
                    HStack(spacing: 8) {
                        Button("Play again") { games.rematch() }.buttonStyle(CuteButtonStyle())
                        Button("Other games") { games.otherGames() }.buttonStyle(CuteButtonStyle(filled: false))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                Button("Leave game") { games.leave() }
                    .buttonStyle(.plain).font(Theme.sans(10.5, .medium)).foregroundStyle(Theme.ink3)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: b)
        }
    }

    private func showsScore(_ b: Board) -> Bool { b.kind == .memory || b.kind == .rps || b.kind == .dots }

    private func activeIndex(_ b: Board) -> Int? {
        guard b.result == nil else { return nil }
        if b.kind == .rps { return nil }
        return b.turn
    }

    private func status(_ b: Board) -> String {
        let them = games.partnerFirst
        if let r = b.result {
            if r == 2 { return "It's a tie 🤝" }
            return r == games.myIndex ? "You won! 🎉" : "\(them) won 🥹"
        }
        if b.kind == .rps {
            if b.picks[games.myIndex] < 0 { return b.round == 0 ? "Pick one!" : "Round \(b.round + 1): pick one!" }
            return "Waiting for \(them)…"
        }
        if b.memoryMismatch { return b.turn == games.myIndex ? "Not a pair 🙈" : "Not a pair!" }
        return b.turn == games.myIndex ? "Your turn 💕" : "\(them)'s turn…"
    }
}

/// Name, heart and score, glowing while it's their go.
private struct PlayerChip: View {
    let name: String
    let index: Int
    let score: Int
    let showScore: Bool
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(Players.token[index]).font(.system(size: 13))
            Text(name).font(Theme.sans(11.5, .semibold)).lineLimit(1)
            if showScore {
                Text("\(score)").font(Theme.sans(11.5, .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Players.color[index], in: Capsule())
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(active ? Players.soft[index] : Theme.glass2, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? Players.color[index] : Theme.line, lineWidth: active ? 1.5 : 1))
        .foregroundStyle(active ? Ink.main : Theme.ink)
        .scaleEffect(active ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active)
    }
}

// MARK: Tic tac toe

private struct TicTacToeBoard: View {
    @EnvironmentObject var games: GameCenter
    let board: Board

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(66), spacing: 7), count: 3)
        LazyVGrid(columns: cols, spacing: 7) {
            ForEach(0..<9, id: \.self) { i in
                let v = board.cells[i]
                let win = board.winLine.contains(i)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(win ? Players.soft[max(v, 0)] : Color(hex: 0xF7EFE3))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(win ? Players.color[max(v, 0)] : .black.opacity(0.06), lineWidth: win ? 2 : 1))
                    .overlay {
                        if v >= 0 {
                            Text(Players.token[v]).font(.system(size: 34)).transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .frame(width: 66, height: 66)
                    .contentShape(Rectangle())
                    .onTapGesture { games.tapCell(i) }
                    .scaleEffect(win ? 1.06 : 1)
            }
        }
        .frame(width: 66 * 3 + 14)
    }
}

// MARK: Connect four

private struct ConnectFourBoard: View {
    @EnvironmentObject var games: GameCenter
    let board: Board
    @State private var hoverColumn: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { c in
                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { r in
                        let v = board.cells[r * 7 + c]
                        Circle()
                            .fill(v >= 0 ? Players.color[v] : Color(hex: 0xFBF6EE))
                            .overlay(Circle().strokeBorder(board.winLine.contains(r * 7 + c) ? .white : .clear, lineWidth: 2.5))
                            .overlay {
                                if v >= 0 { Text("♥").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.85)) }
                            }
                            .frame(width: 28, height: 28)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 2)
                .background(hoverColumn == c && games.isMyTurn ? Color.white.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hoverColumn = $0 ? c : (hoverColumn == c ? nil : hoverColumn) }
                .onTapGesture { games.dropDisc(c) }
            }
        }
        .padding(6)
        .background(Color(hex: 0xA9C9EC), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: Memory

private struct MemoryBoard: View {
    @EnvironmentObject var games: GameCenter
    let board: Board

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(54), spacing: 7), count: 4)
        LazyVGrid(columns: cols, spacing: 7) {
            ForEach(0..<16, id: \.self) { i in
                MemoryCard(face: Board.memoryFaces[board.faces[i]],
                           up: board.flipped.contains(i) || board.owner[i] >= 0,
                           owner: board.owner[i])
                    .onTapGesture { games.flipCard(i) }
            }
        }
        .frame(width: 54 * 4 + 21)
    }
}

private struct MemoryCard: View {
    let face: String
    let up: Bool
    let owner: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: 0xFBF6EE))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(owner >= 0 ? Players.color[owner] : .black.opacity(0.06), lineWidth: owner >= 0 ? 2 : 1))
                .overlay(Text(face).font(.system(size: 26)))
                .opacity(up ? 1 : 0)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF6B8CF), Color(hex: 0xEE8FB4)], startPoint: .top, endPoint: .bottom))
                .overlay(Text("♡").font(.system(size: 20, weight: .bold)).foregroundStyle(.white.opacity(0.9)))
                .opacity(up ? 0 : 1)
        }
        .frame(width: 54, height: 54)
        .rotation3DEffect(.degrees(up ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: up)
        .contentShape(Rectangle())
    }
}

// MARK: Rock paper scissors

private struct RPSBoard: View {
    @EnvironmentObject var games: GameCenter
    let board: Board

    var body: some View {
        VStack(spacing: 10) {
            if board.round > 0 {
                // The round that was just revealed.
                HStack(spacing: 14) {
                    hand(board.lastPicks[games.myIndex], won: board.lastWinner == games.myIndex)
                    Text("vs").font(Theme.marker(18)).foregroundStyle(Theme.ink2)
                    hand(board.lastPicks[games.theirIndex], won: board.lastWinner == games.theirIndex)
                }
                .id(board.round)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                Text(board.lastWinner == 2 ? "Same! 🤝" : board.lastWinner == games.myIndex ? "You got that one" : "\(games.partnerFirst) got that one")
                    .font(Theme.sans(11)).foregroundStyle(Theme.ink2)
            }
            if board.result == nil {
                let mine = board.picks[games.myIndex]
                if mine < 0 {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { h in
                            Button { games.pickHand(h) } label: {
                                VStack(spacing: 2) {
                                    Text(Board.rpsHands[h]).font(.system(size: 30))
                                    Text(Board.rpsNames[h]).font(Theme.sans(9.5, .medium)).foregroundStyle(Ink.soft)
                                }
                                .frame(width: 70, height: 66)
                                .background(GameKind.rps.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(HandButtonStyle())
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("You picked \(Board.rpsHands[mine])").font(Theme.sans(12, .medium))
                        if board.picks[games.theirIndex] < 0 { BouncingHearts() }
                    }
                }
                if mine < 0, board.picks[games.theirIndex] >= 0 {
                    Text("\(games.partnerFirst) has picked 🤫").font(Theme.sans(11)).foregroundStyle(Theme.ink2)
                }
            }
        }
    }

    private func hand(_ h: Int, won: Bool) -> some View {
        Text(h >= 0 ? Board.rpsHands[h] : "❔").font(.system(size: 38))
            .frame(width: 64, height: 64)
            .background(won ? Players.soft[0] : Theme.glass2, in: Circle())
            .overlay(Circle().strokeBorder(won ? Players.color[0] : .clear, lineWidth: 2))
    }
}

private struct HandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: Dots & boxes

private struct DotsBoard: View {
    @EnvironmentObject var games: GameCenter
    let board: Board
    private let cell: CGFloat = 62
    private let margin: CGFloat = 12

    var body: some View {
        let size = cell * 3 + margin * 2
        ZStack(alignment: .topLeading) {
            // Closed boxes.
            ForEach(0..<9, id: \.self) { b in
                if board.boxes[b] >= 0 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Players.soft[board.boxes[b]])
                        .overlay(Text(Players.token[board.boxes[b]]).font(.system(size: 22)))
                        .frame(width: cell - 8, height: cell - 8)
                        .position(x: margin + CGFloat(b % 3) * cell + cell / 2, y: margin + CGFloat(b / 3) * cell + cell / 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Lines: across (0–11), then down (12–23).
            ForEach(0..<24, id: \.self) { e in
                let f = frame(e)
                let owner = board.lines[e]
                LineSlot(owner: owner, across: e < 12, canPlay: games.isMyTurn)
                    .frame(width: f.width, height: f.height)
                    .position(x: f.midX, y: f.midY)
                    .onTapGesture { games.drawLine(e) }
            }
            // Dots on top.
            ForEach(0..<16, id: \.self) { d in
                Circle().fill(Ink.main)
                    .frame(width: 8, height: 8)
                    .position(x: margin + CGFloat(d % 4) * cell, y: margin + CGFloat(d / 4) * cell)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .background(Color(hex: 0xF7EFE3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Tap area for a line, a little fatter than the line itself.
    private func frame(_ e: Int) -> CGRect {
        let t: CGFloat = 16
        if e < 12 {
            let r = e / 3, c = e % 3
            return CGRect(x: margin + CGFloat(c) * cell + 6, y: margin + CGFloat(r) * cell - t / 2, width: cell - 12, height: t)
        } else {
            let k = e - 12, r = k / 4, c = k % 4
            return CGRect(x: margin + CGFloat(c) * cell - t / 2, y: margin + CGFloat(r) * cell + 6, width: t, height: cell - 12)
        }
    }
}

private struct LineSlot: View {
    let owner: Int
    let across: Bool
    let canPlay: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
            Capsule()
                .fill(owner >= 0 ? Players.color[owner] : (hovering && canPlay ? Ink.soft.opacity(0.6) : Ink.soft.opacity(0.18)))
                .frame(width: across ? nil : 5, height: across ? 5 : nil)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: owner)
    }
}

// MARK: - Tab

/// On the top tab: a game pad hopping about, with a red badge, when there's a ping or it's my go.
struct JumpingGamePad: View {
    let invite: Bool

    var body: some View {
        PhaseAnimator([0.0, -7.0, 0.0, -3.0, 0.0, 0.0, 0.0]) { y in
            Text("🎮").font(.system(size: 22))
                .frame(width: 34, height: 26)
                .background(Players.soft[0], in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .rotationEffect(.degrees(y * -0.9))
                .offset(y: y)
                .overlay(alignment: .topTrailing) {
                    Text(invite ? "!" : "♥")
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
