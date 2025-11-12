import Foundation

struct BackendUser: Codable, Equatable, Identifiable {
    let id: String
    let email: String
    let first_name: String
    let last_name: String
    let phone_number: String
    let created_at: String
}

struct AuthWithTokensResponse: Codable {
    let access_token: String
    let refresh_token: String
    let user: BackendUser
}

struct AuthCheckResponse: Codable {
    let user: BackendUser
}

struct Chat: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let created_at: String
}

struct ChatListResponse: Codable {
    let chats: [Chat]
}

struct ChatCreateResponse: Codable {
    let chat: Chat
}

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let chat_id: String
    let role: String
    var content: String        // ← kept var (mutable) for streaming updates
    let created_at: String

    // 🆕 Added field — stores the pristine, unaltered markdown
    var rawContent: String?
}

struct MessageResponse: Codable {
    let assistant_message: Message
    let user_message: Message
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct SignupRequest: Encodable {
    let email: String
    let first_name: String
    let last_name: String
    let password: String
    let phone_number: String
}

struct CreateChatRequest: Encodable {
    let title: String?
}

struct SendMessageRequest: Encodable {
    let content: String
}
