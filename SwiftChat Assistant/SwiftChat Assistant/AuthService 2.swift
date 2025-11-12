import Foundation

final class AuthService {
    static let shared = AuthService()
    private init() {}

    func login(email: String, password: String) async throws -> AuthWithTokensResponse {
        let req = LoginRequest(email: email, password: password)
        let resp: AuthWithTokensResponse = try await APIClient.shared.send("/login", method: "POST", body: req, requiresAuth: false)
        APIClient.shared.saveTokens(AuthTokens(accessToken: resp.access_token, refreshToken: resp.refresh_token))
        return resp
    }

    func signup(firstName: String, lastName: String, email: String, password: String, phoneNumber: String) async throws -> AuthWithTokensResponse {
        let req = SignupRequest(email: email, first_name: firstName, last_name: lastName, password: password, phone_number: phoneNumber)
        let resp: AuthWithTokensResponse = try await APIClient.shared.send("/signup", method: "POST", body: req, requiresAuth: false)
        APIClient.shared.saveTokens(AuthTokens(accessToken: resp.access_token, refreshToken: resp.refresh_token))
        return resp
    }

    func authCheck() async throws -> AuthCheckResponse {
        try await APIClient.shared.send("/auth", method: "GET", requiresAuth: true)
    }

    func signOut() { APIClient.shared.clearTokens() }
}
