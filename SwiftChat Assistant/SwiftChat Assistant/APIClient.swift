import Foundation
import Security

struct AuthTokens: Codable, Equatable { var accessToken: String; var refreshToken: String }

protocol TokenStore { func load() -> AuthTokens?; func save(_ tokens: AuthTokens?); func clear() }

final class KeychainTokenStore: TokenStore {
    private let service = "PersonalAssistantTokens"
    private let account = "default"
    func load() -> AuthTokens? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }
    func save(_ tokens: AuthTokens?) {
        clear()
        guard let tokens = tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum APIError: Error, LocalizedError { case unauthorized, decoding, server(status: Int, message: String?), network(Error)
    var errorDescription: String? {
        switch self { case .unauthorized: return "Unauthorized"; case .decoding: return "Failed to decode response"; case .server(let s, let m): return m ?? "Server error (\(s))"; case .network(let e): return e.localizedDescription }
    }
}

final class APIClient {
    static let shared = APIClient()
    private let baseURL = URL(string: "https://personal-assistant-backend-fly.fly.dev")!
    private let apiKey = "qrG1sfVNEXSTqPvfaWDrwTEel7LMB1BI"
    private let urlSession: URLSession
    private let tokenStore: TokenStore
    private let refreshQueue = DispatchQueue(label: "api.refresh.queue")
    init(urlSession: URLSession = .shared, tokenStore: TokenStore = KeychainTokenStore()) { self.urlSession = urlSession; self.tokenStore = tokenStore }
    func loadTokens() -> AuthTokens? {
        let t = tokenStore.load()
        if let t { print("🔑 [Tokens] loadTokens -> FOUND (access: \(t.accessToken.prefix(8))…)") } else { print("🔑 [Tokens] loadTokens -> none") }
        return t
    }
    func saveTokens(_ tokens: AuthTokens?) {
        if let tokens {
            print("💾 [Tokens] saveTokens — saving access: \(tokens.accessToken.prefix(8))… refresh: \(tokens.refreshToken.prefix(8))…")
        } else {
            print("💾 [Tokens] saveTokens — saving nil (clearing)")
        }
        tokenStore.save(tokens)
    }
    func clearTokens() {
        print("🧹 [Tokens] clearTokens — deleting from Keychain")
        tokenStore.clear()
    }

    func send<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil, requiresAuth: Bool = true, retryOn401: Bool = true, responseType: T.Type = T.self) async throws -> T {
        let request = try buildRequest(path, method: method, body: body, requiresAuth: requiresAuth)
        //print("🌐 API Request: \(method) \(request.url?.absoluteString ?? "unknown")")
        if let httpBody = request.httpBody, let bodyString = String(data: httpBody, encoding: .utf8) {
            //print("📤 Request body: \(bodyString)")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
            
            //print("📡 Response status: \(http.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                //print("📥 Response body: \(responseString)")
            }
            
            if http.statusCode == 401, requiresAuth {
                let normalizedPath = path.hasPrefix("/") ? path : "/" + path
                print("🔒 [Send] 401 received for \(method) \(normalizedPath). Will attempt refresh: \(retryOn401)")
                if retryOn401, try await refreshAccessToken() {
                    return try await send(path, method: method, body: body, requiresAuth: requiresAuth, retryOn401: false, responseType: responseType)
                } else { throw APIError.unauthorized }
            }
            guard (200..<300).contains(http.statusCode) else { 
                let errorMessage = String(data: data, encoding: .utf8)
                //print("❌ Server error \(http.statusCode): \(errorMessage ?? "no message")")
                throw APIError.server(status: http.statusCode, message: errorMessage)
            }
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            
            //print("✅ Attempting to decode JSON response")
            return try JSONDecoder().decode(T.self, from: data)
        } catch { 
            //print("🚨 Network/decode error: \(error)")
            if let apiErr = error as? APIError { throw apiErr }
            throw APIError.network(error) 
        }
    }

    func buildStreamingRequest(_ path: String, method: String, body: Encodable?) throws -> URLRequest {
        return try buildRequest(path, method: method, body: body, requiresAuth: true)
    }

    private func buildRequest(_ path: String, method: String, body: Encodable?, requiresAuth: Bool) throws -> URLRequest {
        var url = baseURL
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        url.append(path: normalizedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        if requiresAuth, let token = tokenStore.load()?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("📤 [Request] Attaching Authorization header for \(method) \(normalizedPath)")
        } else if requiresAuth {
            print("⚠️ [Request] requiresAuth but no access token available for \(method) \(normalizedPath)")
        }
        if let body = body { request.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        return request
    }

    private struct RefreshRequest: Encodable { let refresh_token: String }
    private struct RefreshResponse: Decodable { let access_token: String }
    private func refreshAccessToken() async throws -> Bool {
        print("🔁 [Refresh] Attempting token refresh…")
        guard let tokens = self.tokenStore.load() else {
            print("❌ [Refresh] No tokens available to refresh")
            return false
        }
        do {
            let req = RefreshRequest(refresh_token: tokens.refreshToken)
            let newToken: RefreshResponse = try await self.send("/token/refresh", method: "POST", body: req, requiresAuth: false, retryOn401: false)
            let updated = AuthTokens(accessToken: newToken.access_token, refreshToken: tokens.refreshToken)
            self.tokenStore.save(updated)
            print("✅ [Refresh] Refresh succeeded — new access: \(updated.accessToken.prefix(8))…")
            return true
        } catch {
            print("❌ [Refresh] Refresh failed: \(error.localizedDescription)")
            return false
        }
    }
}

struct EmptyResponse: Decodable { }
private struct AnyEncodable: Encodable { let _encode: (Encoder) throws -> Void; init<T: Encodable>(_ wrapped: T) { _encode = wrapped.encode }; func encode(to encoder: Encoder) throws { try _encode(encoder) } }
