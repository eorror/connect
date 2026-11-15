import Foundation

struct Note: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let sender: String
    let body: String
    let replyTo: UUID?
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sender, body
        case createdAt = "created_at"
        case replyTo = "reply_to"
        case readAt = "read_at"
    }

    /// Thread this note belongs to (replies always point at the root note).
    var threadID: UUID { replyTo ?? id }
}

struct NewNote: Encodable {
    let id: UUID
    let sender: String
    let body: String
    let replyTo: UUID?

    enum CodingKeys: String, CodingKey {
        case id, sender, body
        case replyTo = "reply_to"
    }
}

struct NoteThread: Identifiable, Hashable {
    let root: Note
    let replies: [Note]
    var id: UUID { root.id }
    var all: [Note] { [root] + replies }
    var last: Note { replies.last ?? root }
}

/// Where notes are stored. Kept on each laptop, never baked into the app.
struct Backend: Equatable {
    var url: String
    var key: String

    static func load() -> Backend? {
        let d = UserDefaults.standard
        guard let url = d.string(forKey: "backendURL"), let key = d.string(forKey: "backendKey"),
              !url.isEmpty, !key.isEmpty else { return nil }
        return Backend(url: url, key: key)
    }

    func save() {
        UserDefaults.standard.set(url, forKey: "backendURL")
        UserDefaults.standard.set(key, forKey: "backendKey")
    }

    /// A single string you can send to the other laptop so it connects to the same notes.
    var pairingCode: String { Data("\(url)\n\(key)".utf8).base64EncodedString() }

    init(url: String, key: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        self.url = u
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(pairingCode: String) {
        guard let data = Data(base64Encoded: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].hasPrefix("http") else { return nil }
        self.init(url: parts[0], key: parts[1])
    }
}
