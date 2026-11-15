import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Minimal client for the Supabase REST (PostgREST) endpoint.
struct NotesAPI {
    let backend: Backend

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(backend.url)/rest/v1/\(path)") else {
            throw APIError(message: "Bad server URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(backend.key, forHTTPHeaderField: "apikey")
        // Legacy anon keys are JWTs and also go in Authorization; new publishable keys must not.
        if backend.key.hasPrefix("eyJ") {
            req.setValue("Bearer \(backend.key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "GET" { req.setValue("return=minimal", forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "No response") }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError(message: "Server error \(http.statusCode): \(text.prefix(200))")
        }
        return data
    }

    func fetchNotes() async throws -> [Note] {
        let data = try await request("notes?select=*&order=created_at.desc&limit=500")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Bad date \(s)"))
            }
            return date
        }
        return try decoder.decode([Note].self, from: data).reversed()
    }

    func insert(_ note: NewNote) async throws {
        _ = try await request("notes", method: "POST", body: JSONEncoder().encode(note))
    }

    func markRead(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        let now = ISO8601DateFormatter().string(from: Date())
        let body = try JSONSerialization.data(withJSONObject: ["read_at": now])
        _ = try await request("notes?id=in.(\(list))", method: "PATCH", body: body)
    }
}

/// Postgres returns microseconds ("...:00.123456+00:00"); ISO8601DateFormatter wants milliseconds.
func parseDate(_ raw: String) -> Date? {
    var s = raw.replacingOccurrences(of: " ", with: "T")
    if let dot = s.firstIndex(of: ".") {
        let afterDot = s.index(after: dot)
        let end = s[afterDot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) ?? s.endIndex
        let ms = String((String(s[afterDot..<end]) + "000").prefix(3))
        s.replaceSubrange(afterDot..<end, with: ms)
    }
    if !s.hasSuffix("Z"), s.range(of: #"[+-]\d\d(:?\d\d)?$"#, options: .regularExpression) == nil { s += "Z" }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}
