import CryptoKit
import Foundation

/// One message between the two apps about games. Everything travels as this.
struct GameMsg: Codable {
    /// hello / here (online), invite / accept / decline / cancel, board, rps, ball, pad, lobby, leave
    var t: String
    var from: String
    var to: String
    var sid: String? = nil
    var seq: Int? = nil
    var board: Board? = nil
    var pick: Int? = nil
    /// Pong: ball [x, y, vx, vy, wait] and my paddle.
    var ball: [Double]? = nil
    var pad: Double? = nil
}

/// Live connection to the other laptop over Supabase Realtime broadcast: a WebSocket room only
/// the two of you know the name of. Nothing is stored in the database; letters are untouched.
@MainActor
final class GameLink {
    var onMessage: ((GameMsg) -> Void)?
    var onConnected: (() -> Void)?
    private(set) var connected = false

    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var topic = ""
    private var ref = 0
    private var heartbeat: Timer?
    private var retry: Double = 2
    /// Bumped whenever a socket is replaced, so callbacks from an old one are ignored.
    private var generation = 0

    /// Same name on both laptops, hard to guess for anyone else.
    static func room(_ a: String, _ b: String) -> String {
        let key = [a.lowercased(), b.lowercased()].sorted().joined(separator: "|") + "|connect-games-v1"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "connect-" + hash.prefix(32)
    }

    func connect(backend: Backend, room: String) {
        disconnect()
        let ws = backend.url.replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let u = URL(string: "\(ws)/realtime/v1/websocket?apikey=\(backend.key)&vsn=1.0.0") else { return }
        url = u
        topic = "realtime:" + room
        retry = 2
        open()
    }

    func disconnect() {
        generation += 1
        url = nil
        heartbeat?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }

    func send(_ msg: GameMsg) {
        guard connected, let data = try? JSONEncoder().encode(msg),
              let inner = try? JSONSerialization.jsonObject(with: data) else { return }
        sendRaw(["topic": topic, "event": "broadcast", "ref": nextRef(), "join_ref": "1",
                 "payload": ["type": "broadcast", "event": "game", "payload": inner]])
    }

    // MARK: Socket

    private func open() {
        guard let url else { return }
        generation += 1
        let gen = generation
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        sendRaw(["topic": topic, "event": "phx_join", "ref": nextRef(), "join_ref": "1",
                 "payload": ["config": ["broadcast": ["self": false, "ack": false],
                                        "presence": ["key": ""], "private": false]]])
        receive(t, gen)
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sendRaw(["topic": "phoenix", "event": "heartbeat", "payload": [String: Any](), "ref": self.nextRef()])
            }
        }
    }

    private func receive(_ t: URLSessionWebSocketTask, _ gen: Int) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch result {
                case .failure:
                    self.dropped()
                case .success(let m):
                    if case .string(let s) = m { self.handle(s) }
                    self.receive(t, gen)
                }
            }
        }
    }

    private func handle(_ s: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let event = obj["event"] as? String else { return }
        switch event {
        case "phx_reply":
            if !connected, (obj["topic"] as? String) == topic,
               let p = obj["payload"] as? [String: Any], (p["status"] as? String) == "ok" {
                connected = true
                retry = 2
                onConnected?()
            }
        case "broadcast":
            if let p = obj["payload"] as? [String: Any], let inner = p["payload"],
               let data = try? JSONSerialization.data(withJSONObject: inner),
               let msg = try? JSONDecoder().decode(GameMsg.self, from: data) {
                onMessage?(msg)
            }
        case "phx_error", "phx_close":
            if (obj["topic"] as? String) == topic { dropped() }
        default:
            break
        }
    }

    /// Lost the connection (sleep, Wi-Fi): try again, waiting a little longer each time.
    private func dropped() {
        connected = false
        heartbeat?.invalidate()
        task?.cancel()
        task = nil
        generation += 1
        let delay = retry
        retry = min(retry * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.task == nil, self.url != nil else { return }
            self.open()
        }
    }

    private func sendRaw(_ o: [String: Any]) {
        guard let task, let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    private func nextRef() -> String {
        ref += 1
        return String(ref)
    }
}
