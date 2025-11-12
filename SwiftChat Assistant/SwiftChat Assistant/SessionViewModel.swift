import Foundation
import Observation

@Observable
final class SessionViewModel {
    enum State { case loading, signedOut, signedIn }
    var state: State = .loading
    var user: BackendUser?
    var chats: [Chat] = []
    var currentChat: Chat?
    var messages: [Message] = []
    var draft: String = ""
    var sending: Bool = false
    var streamingAssistantId: String?
    
    // ✅ Streaming markdown parser
    var markdownParser = StreamingMarkdownParser()

    // ✅ NEW: Decoupled buffering system
    private var masterBuffer: String = ""           // Fast GPT accumulation
    private var displayedSoFar: String = ""         // What's been typed out to UI
    private var typewriterTimer: Timer?
    private var currentTypingMessageId: String?

    init() { Task { await self.bootstrap() } }

    @MainActor
    func bootstrap() async {
        if APIClient.shared.loadTokens() == nil { self.state = .signedOut; return }
        do {
            let resp = try await AuthService.shared.authCheck()
            self.user = resp.user
            self.state = .signedIn
            try await loadOrCreateFirstChat()
        } catch { self.state = .signedOut }
    }

    @MainActor
    func signOut() {
        AuthService.shared.signOut()
        user = nil; chats = []; currentChat = nil; messages = []; draft = ""; state = .signedOut
    }

    @MainActor
    func didAuthenticate(_ resp: AuthWithTokensResponse) async {
        self.user = resp.user
        self.state = .signedIn
        try? await loadOrCreateFirstChat()
    }

    @MainActor
    func loadChats() async throws { chats = try await ChatService.shared.fetchChats() }

    @MainActor
    func loadOrCreateFirstChat() async throws {
        try await loadChats()
        if let first = chats.first { try await selectChat(first) }
        else { let new = try await ChatService.shared.createChat(title: nil); chats = [new]; try await selectChat(new) }
    }

    @MainActor
    func createNewChat() async { if let chat = try? await ChatService.shared.createChat(title: nil) { chats.insert(chat, at: 0); try? await selectChat(chat) } }

    @MainActor
    func selectChat(_ chat: Chat) async throws { currentChat = chat; messages = try await ChatService.shared.fetchMessages(chatID: chat.id) }

    @MainActor
    func send() async {
        guard let chat = currentChat else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        // Clear the draft and set sending state
        sending = true
        draft = ""
        
        // Create a temporary user message to show immediately
        let tempUserMessage = Message(
            id: UUID().uuidString,
            chat_id: chat.id,
            role: "user",
            content: content,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        
        // Add user message immediately to UI
        messages = messages + [tempUserMessage]
        
        // Create a temporary assistant message for streaming
        let tempAssistantId = UUID().uuidString
        let tempAssistantMessage = Message(
            id: tempAssistantId,
            chat_id: chat.id,
            role: "assistant",
            content: "", // Start empty for streaming
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        
        // Add empty assistant message for streaming
        messages = messages + [tempAssistantMessage]
        self.streamingAssistantId = tempAssistantId
        self.currentTypingMessageId = tempAssistantId
        
        // ✅ Reset parser and buffers for new message
        markdownParser.reset()
        masterBuffer = ""
        displayedSoFar = ""
        
        // ✅ Start typewriter timer
        startTypewriterTimer()
        
        do {
            
            let (userMsg, finalAssistantMsg) = try await ChatService.shared.sendMessage(
                chatID: chat.id,
                content: content
            ) { @MainActor token in
                // ✅ NEW: Just accumulate in master buffer (no parser yet)
                self.masterBuffer += token
            }
            
            print("✅ Streaming complete, master buffer length: \(self.masterBuffer.count)")
            print("📦 FULL MASTER BUFFER:")
            print(self.masterBuffer.debugDescription)
            print("🔍 CHECKING FOR NEWLINES:")
            print("Contains \\n: \(self.masterBuffer.contains("\n"))")
            print("First 300 chars with unicode scalars:")
            for (index, char) in self.masterBuffer.prefix(300).enumerated() {
                if char == "\n" {
                    print("  Index \(index): NEWLINE CHARACTER FOUND")
                }
            }
            
            // Wait for typewriter to finish before showing final message
            // The timer will stop itself when displayedSoFar == masterBuffer
            
            // Update messages with server IDs after typewriter completes
            // We'll do this in the timer's completion handler
            self.finalizeMessage(
                tempUserMessageId: tempUserMessage.id,
                tempAssistantId: tempAssistantId,
                userMsg: userMsg,
                finalAssistantMsg: finalAssistantMsg
            )
            
        } catch {
            print("❌ Error details: \(error)")
            print("❌ Error localized: \(error.localizedDescription)")
            
            // Stop typewriter on error
            stopTypewriterTimer()
            
            // Handle error - remove the temporary messages and show error
            messages = messages.filter { $0.id != tempUserMessage.id && $0.id != tempAssistantId }
            
            // Create an error message
            let errorMessage = Message(
                id: UUID().uuidString,
                chat_id: chat.id,
                role: "assistant",
                content: "Sorry, I encountered an error sending your message. Please try again.",
                created_at: ISO8601DateFormatter().string(from: Date())
            )
            messages = messages + [errorMessage]
            self.streamingAssistantId = nil
            markdownParser.reset()
            
            // Restore the draft so user can retry
            draft = content
        }
        
        sending = false
    }
    
    // ✅ NEW: Start typewriter timer that feeds parser at controlled pace
    @MainActor
    private func startTypewriterTimer() {
        typewriterTimer?.invalidate()
        
        // Create timer that runs even during scrolling
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Check if we've displayed everything
            if self.displayedSoFar.count >= self.masterBuffer.count {
                // Typewriter is done
                return
            }
            
            // Get next chunk of characters (5 chars for smoother but not too fast)
            let chunkSize = 5
            let startIndex = self.masterBuffer.index(
                self.masterBuffer.startIndex,
                offsetBy: self.displayedSoFar.count
            )
            let endIndex = self.masterBuffer.index(
                startIndex,
                offsetBy: min(chunkSize, self.masterBuffer.count - self.displayedSoFar.count)
            )
            
            let chunk = String(self.masterBuffer[startIndex..<endIndex])
            self.displayedSoFar += chunk
            
            // Feed to parser
            self.markdownParser.addToken(chunk)
            
            // Force UI update by mutating messages array
            if let id = self.currentTypingMessageId,
               let index = self.messages.firstIndex(where: { $0.id == id }) {
                var updatedMessage = self.messages[index]
                // Dummy change to trigger SwiftUI diff
                updatedMessage.content = String(self.displayedSoFar.count)
                self.messages[index] = updatedMessage
            }
        }
        
        // Add timer to common run loop mode so it continues during scrolling
        RunLoop.current.add(timer, forMode: .common)
        typewriterTimer = timer
    }
    
    // ✅ NEW: Stop typewriter timer
    @MainActor
    private func stopTypewriterTimer() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }
    
    // ✅ NEW: Finalize message with server IDs after typewriter completes
    @MainActor
    private func finalizeMessage(
        tempUserMessageId: String,
        tempAssistantId: String,
        userMsg: Message,
        finalAssistantMsg: Message
    ) {
        // Check periodically if typewriter is done
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Wait until typewriter finishes
            guard self.displayedSoFar.count >= self.masterBuffer.count else {
                return
            }
            
            timer.invalidate()
            
            // Stop typewriter
            self.stopTypewriterTimer()
            
            // Update messages with server IDs
            var updatedMessages = self.messages
            if let userIndex = updatedMessages.firstIndex(where: { $0.id == tempUserMessageId }) {
                updatedMessages[userIndex] = Message(
                    id: userMsg.id,
                    chat_id: userMsg.chat_id,
                    role: userMsg.role,
                    content: updatedMessages[userIndex].content,
                    created_at: userMsg.created_at
                )
            }
            if let assistantIndex = updatedMessages.firstIndex(where: { $0.id == tempAssistantId }) {
                // Use pristine server text for final render
                let pristine = finalAssistantMsg.content
                print("📄 FULL RAW MESSAGE FROM SERVER:")
                print("First 200 chars with escapes shown:")
                print(pristine.prefix(200).debugDescription)
                print("🔍 FINAL MESSAGE - Contains \\n: \(pristine.contains("\n"))")  // ADD THIS
                print(pristine)
                print("📄 END OF MESSAGE")
                updatedMessages[assistantIndex] = Message(
                    id: finalAssistantMsg.id,
                    chat_id: finalAssistantMsg.chat_id,
                    role: finalAssistantMsg.role,
                    content: pristine.isEmpty ? updatedMessages[assistantIndex].content : pristine,
                    created_at: finalAssistantMsg.created_at
                )
            }
            self.messages = updatedMessages.map { msg in
                if msg.id == finalAssistantMsg.id {
                    var done = msg
                    done.rawContent = msg.content
                    done.content += " " // tiny mutation to trigger SwiftUI diff
                    return done
                }
                return msg
            }
            
            // Clear streaming state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.streamingAssistantId = nil
                self.currentTypingMessageId = nil
                self.markdownParser.reset()
                self.masterBuffer = ""
                self.displayedSoFar = ""
            }
            
        }
    }
}
