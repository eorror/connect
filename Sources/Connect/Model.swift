import Foundation

struct Note: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let senderEmail: String
    let senderName: String
    let recipientEmail: String
    let body: String
    let replyTo: UUID?
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body
        case createdAt = "created_at"
        case senderEmail = "sender_email"
        case senderName = "sender_name"
        case recipientEmail = "recipient_email"
        case replyTo = "reply_to"
        case readAt = "read_at"
    }

    /// Thread this note belongs to (replies always point at the root note).
    var threadID: UUID { replyTo ?? id }
}

struct NewNote: Encodable {
    let id: UUID
    let senderEmail: String
    let senderName: String
    let recipientEmail: String
    let body: String
    let replyTo: UUID?

    enum CodingKeys: String, CodingKey {
        case id, body
        case senderEmail = "sender_email"
        case senderName = "sender_name"
        case recipientEmail = "recipient_email"
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

/// The Supabase project the notes live in. Normally built into the app (version.env);
/// can be overridden on a laptop from the setup screen.
struct Backend: Equatable {
    var url: String
    var key: String

    init(url: String, key: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        self.url = u
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var builtIn: Backend? {
        let info = Bundle.main.infoDictionary
        guard let url = info?["ConnectSupabaseURL"] as? String, url.hasPrefix("http"),
              let key = info?["ConnectSupabaseKey"] as? String, !key.isEmpty else { return nil }
        return Backend(url: url, key: key)
    }

    static func load() -> Backend? {
        let d = UserDefaults.standard
        if let url = d.string(forKey: "backendURL"), let key = d.string(forKey: "backendKey"),
           !url.isEmpty, !key.isEmpty {
            return Backend(url: url, key: key)
        }
        return builtIn
    }

    func save() {
        UserDefaults.standard.set(url, forKey: "backendURL")
        UserDefaults.standard.set(key, forKey: "backendKey")
    }
}
