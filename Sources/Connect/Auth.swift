import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
    var name: String
}

/// Google sign-in through Supabase Auth (OAuth + PKCE), with token refresh.
@MainActor
final class AuthManager: ObservableObject {
    static let callbackScheme = "connectnotes"
    static let redirectURL = "connectnotes://auth-callback"

    @Published private(set) var session: AuthSession? = AuthManager.loadSession()

    private var webSession: ASWebAuthenticationSession?
    private let anchor = AnchorProvider()
    private var refreshTask: Task<AuthSession, Error>?

    // MARK: Sign in / out

    func signInWithGoogle(backend: Backend) async throws {
        let verifier = Self.randomString(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        guard var comps = URLComponents(string: "\(backend.url)/auth/v1/authorize") else {
            throw APIError(message: "Bad server URL")
        }
        comps.queryItems = [
            .init(name: "provider", value: "google"),
            .init(name: "redirect_to", value: Self.redirectURL),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "s256"),
        ]
        guard let authURL = comps.url else { throw APIError(message: "Bad server URL") }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: authURL, callbackURLScheme: Self.callbackScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? APIError(message: "Sign-in was cancelled")) }
            }
            s.presentationContextProvider = anchor
            s.prefersEphemeralWebBrowserSession = false
            webSession = s
            if !s.start() { cont.resume(throwing: APIError(message: "Couldn't open the sign-in window")) }
        }
        webSession = nil

        // Supabase puts the code in the query; errors may arrive in the query or the fragment.
        var params: [String: String] = [:]
        let comps2 = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        for item in comps2?.queryItems ?? [] { params[item.name] = item.value }
        if let fragment = comps2?.fragment, var f = URLComponents(string: "x:/?" + fragment) {
            f.scheme = nil
            for item in f.queryItems ?? [] { params[item.name] = item.value }
        }
        guard let code = params["code"] else {
            throw APIError(message: params["error_description"] ?? params["error"] ?? "Sign-in didn't return a code")
        }
        let s = try await Self.token(backend: backend, grant: "pkce",
                                     body: ["auth_code": code, "code_verifier": verifier])
        setSession(s)
    }

    func signOut() {
        setSession(nil)
    }

    // MARK: Tokens

    /// A non-expired access token, refreshing it first if needed.
    func validAccessToken(backend: Backend) async throws -> String {
        guard let current = session else { throw APIError(message: "Not signed in", status: 401) }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { try await Self.token(backend: backend, grant: "refresh_token",
                                               body: ["refresh_token": current.refreshToken]) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            setSession(fresh)
            return fresh.accessToken
        } catch let e as APIError where e.status == 400 || e.status == 401 {
            setSession(nil)   // refresh token no longer valid: ask to sign in again
            throw e
        }
    }

    /// Force the next request to refresh (e.g. after the server rejected the token).
    func expireNow() {
        guard var s = session else { return }
        s.expiresAt = .distantPast
        session = s
    }

    private func setSession(_ s: AuthSession?) {
        session = s
        Self.saveSession(s)
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            struct Meta: Decodable { let full_name: String?; let name: String? }
            let email: String?
            let user_metadata: Meta?
        }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User?
    }

    private static func token(backend: Backend, grant: String, body: [String: String]) async throws -> AuthSession {
        guard let url = URL(string: "\(backend.url)/auth/v1/token?grant_type=\(grant)") else {
            throw APIError(message: "Bad server URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue(backend.key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(message: "Sign-in failed (\(status)): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")",
                           status: status)
        }
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        let email = (r.user?.email ?? "").lowercased()
        guard !email.isEmpty else { throw APIError(message: "Google account has no email address") }
        let name = r.user?.user_metadata?.full_name ?? r.user?.user_metadata?.name
            ?? String(email.split(separator: "@").first ?? "")
        return AuthSession(accessToken: r.access_token, refreshToken: r.refresh_token,
                           expiresAt: Date().addingTimeInterval(r.expires_in),
                           email: email, name: name)
    }

    // MARK: Storage
    // A private file rather than the Keychain: the app is ad-hoc signed, so every
    // update would otherwise trigger a "Connect wants to use your keychain" prompt.

    private static var sessionFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Connect", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("session.json")
    }

    private static func loadSession() -> AuthSession? {
        guard let data = try? Data(contentsOf: sessionFile) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    private static func saveSession(_ s: AuthSession?) {
        let file = sessionFile
        guard let s, let data = try? JSONEncoder().encode(s) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    // MARK: PKCE helpers

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? ASPresentationAnchor()
    }
}
