import Foundation

final class ChatService {
    static let shared = ChatService()
    private init() {}

    func fetchChats() async throws -> [Chat] {
        let resp: ChatListResponse = try await APIClient.shared.send("/chats", method: "GET")
        return resp.chats
    }

    func createChat(title: String? = nil) async throws -> Chat {
        let req = CreateChatRequest(title: title)
        let resp: ChatCreateResponse = try await APIClient.shared.send("/chats", method: "POST", body: req)
        return resp.chat
    }

    func fetchMessages(chatID: String) async throws -> [Message] {
        try await APIClient.shared.send("/chats/\(chatID)/messages", method: "GET")
    }

    func sendMessage(chatID: String, content: String, onToken: @escaping @MainActor (String) -> Void) async throws -> (userMessage: Message, finalAssistantMessage: Message) {
        let req = SendMessageRequest(content: content)
        
        // Build request manually for streaming
        let request = try APIClient.shared.buildStreamingRequest("/chats/\(chatID)/messages", method: "POST", body: req)
        
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.decoding
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(status: httpResponse.statusCode, message: "Streaming request failed")
        }
        
        var assistantContent = ""
        var userMessage: Message?
        
        // Parse SSE stream
        // Parse SSE stream
        for try await line in asyncBytes.lines {
            //print("📡 RAW SSE LINE: \(line.debugDescription)")
            
            if line.hasPrefix("event:message") {
                continue // Skip event lines
            } else if line.hasPrefix("data:") {
                let token = String(line.dropFirst(5)) // Remove "data:" prefix
                if token != "[DONE]" {
                    let finalToken = token.isEmpty ? "\n" : token  // Convert empty lines to newlines
                    assistantContent += finalToken
                    await onToken(finalToken)
                }
            } else if line.hasPrefix("event:done") {
                break // End of stream
            }
        }
        
        // After streaming is complete, fetch the actual messages from the backend
        // This ensures we get the proper message IDs and timestamps
        let messages = try await fetchMessages(chatID: chatID)
        
        // Find the most recent user and assistant messages
        let recentMessages = messages.suffix(2)
        guard let user = recentMessages.first(where: { $0.role.lowercased() == "user" }),
              let assistant = recentMessages.first(where: { $0.role.lowercased() == "assistant" }) else {
            throw APIError.decoding
        }
        
        return (userMessage: user, finalAssistantMessage: assistant)
    }
}
