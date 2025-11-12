#if false
import Foundation

struct User: Decodable {
    let email: String
    let firstName: String
    let lastName: String
    let phoneNumber: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case phoneNumber = "phone_number"
        case userId = "user_id"
    }
}

struct LoginResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

enum AuthError: Error, LocalizedError {
    case server(String)
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .invalidResponse:
            return "Invalid response from server."
        case .network(let err):
            return err.localizedDescription
        }
    }
}

final class AuthService {
    static let shared = AuthService()
    private init() {}

    private let apiKeyHeaderName = "X-API-Key"
    private let apiKeyValue = "qrG1sfVNEXSTqPvfaWDrwTEel7LMB1BI"

    private let baseSignupURL = URL(string: "https://personal-assistant-backend-fly.fly.dev/signup")!
    private let baseLoginURL = URL(string: "https://personal-assistant-backend-fly.fly.dev/login")!

    func signup(firstName: String, lastName: String, email: String, password: String, phoneNumber: String) async throws -> User {
        var request = URLRequest(url: baseSignupURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKeyValue, forHTTPHeaderField: apiKeyHeaderName)

        let body: [String: String] = [
            "first_name": firstName,
            "last_name": lastName,
            "email": email,
            "password": password,
            "phone_number": phoneNumber
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            if (200..<300).contains(http.statusCode) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .useDefaultKeys
                return try decoder.decode(User.self, from: data)
            } else {
                throw AuthError.server(parseServerError(from: data) ?? "Signup failed (\(http.statusCode)).")
            }
        } catch {
            if let authErr = error as? AuthError { throw authErr }
            throw AuthError.network(error)
        }
    }

    func login(email: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: baseLoginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKeyValue, forHTTPHeaderField: apiKeyHeaderName)

        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            if (200..<300).contains(http.statusCode) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .useDefaultKeys
                return try decoder.decode(LoginResponse.self, from: data)
            } else {
                throw AuthError.server(parseServerError(from: data) ?? "Login failed (\(http.statusCode)).")
            }
        } catch {
            if let authErr = error as? AuthError { throw authErr }
            throw AuthError.network(error)
        }
    }

    private func parseServerError(from data: Data) -> String? {
        // Try common fields: error, message
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["error"] as? String { return msg }
            if let msg = obj["message"] as? String { return msg }
        }
        return nil
    }
}

#endif
