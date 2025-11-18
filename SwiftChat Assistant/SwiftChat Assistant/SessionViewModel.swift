import Foundation
import Observation
import UIKit  // ✅ Add this import

// ✅ ADD THIS HELPER
enum HapticFeedback {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// ✅ Character with animation state
struct AnimatedCharacter: Identifiable {
    let id = UUID()
    let character: String
    var opacity: Double = 0.0
}

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
    
    // ✅ Animated characters for fade-in effect
    var animatedCharacters: [AnimatedCharacter] = []

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

        // ✅ Haptic #1: Message sent
        HapticFeedback.light()
        
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
        
        // ✅ Reset parser, buffers, and animated characters for new message
        markdownParser.reset()
        masterBuffer = ""
        displayedSoFar = ""
        animatedCharacters = []
        
        var hasFiredStartHaptic = false
        
        // ✅ Start typewriter timer
        startTypewriterTimer()
        
        do {
            
            let (userMsg, finalAssistantMsg) = try await ChatService.shared.sendMessage(
                chatID: chat.id,
                content: content
            ) { @MainActor token in
                // ✅ Just accumulate in master buffer
                self.masterBuffer += token
                
                // ✅ Haptic #2: First token received (message started)
                if !hasFiredStartHaptic {
                    HapticFeedback.light()
                    hasFiredStartHaptic = true
                }
            }
            
            print("✅ Streaming complete, master buffer length: \(self.masterBuffer.count)")
            
            // Wait for typewriter to finish before showing final message
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
            animatedCharacters = []
            
            // Restore the draft so user can retry
            draft = content
        }
        
        sending = false
    }
    
    // ✅ UPDATED: Character-by-character typewriter with fade-in animation
    @MainActor
    private func startTypewriterTimer() {
        typewriterTimer?.invalidate()
        
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Check if we've displayed everything
            if self.displayedSoFar.count >= self.masterBuffer.count {
                return
            }
            
            // ✅ Get next chunk (up to 5 characters, or whatever's left)
            let startIndex = self.masterBuffer.index(
                self.masterBuffer.startIndex,
                offsetBy: self.displayedSoFar.count
            )
            let remainingCount = self.masterBuffer.count - self.displayedSoFar.count
            let chunkSize = min(5, remainingCount)

            let endIndex = self.masterBuffer.index(
                startIndex,
                offsetBy: chunkSize
            )

            let char = String(self.masterBuffer[startIndex..<endIndex])
            self.displayedSoFar += char
            
            // ✅ Feed to parser (for markdown detection)
            self.markdownParser.addToken(char)
            
            // ✅ Add to animated characters array with fade-in
            let animChar = AnimatedCharacter(character: char, opacity: 0.0)
            self.animatedCharacters.append(animChar)
            
            // Animate the newly added character
            if let lastIndex = self.animatedCharacters.indices.last {
                self.animatedCharacters[lastIndex].opacity = 1.0
            }
            
            // ✅ Clear animated characters when parser completes a block
            if self.markdownParser.shouldClearAnimatedChars {
                self.animatedCharacters = []
                self.markdownParser.shouldClearAnimatedChars = false
            }
            
            // Force UI update by mutating messages array
            if let id = self.currentTypingMessageId,
               let index = self.messages.firstIndex(where: { $0.id == id }) {
                var updatedMessage = self.messages[index]
                // Dummy change to trigger SwiftUI diff
                updatedMessage.content = String(self.displayedSoFar.count)
                self.messages[index] = updatedMessage
            }
        }
        
        RunLoop.current.add(timer, forMode: .common)
        typewriterTimer = timer
    }
    
    // ✅ Stop typewriter timer
    @MainActor
    private func stopTypewriterTimer() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }
    
    // ✅ Finalize message with server IDs after typewriter completes
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
                let pristine = finalAssistantMsg.content
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
            
            // ✅ Haptic #3: Message finished (final markdown render)
            HapticFeedback.success()
            
            // Clear streaming state and animated characters
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.streamingAssistantId = nil
                self.currentTypingMessageId = nil
                self.markdownParser.reset()
                self.masterBuffer = ""
                self.displayedSoFar = ""
                self.animatedCharacters = []
            }
            
        }
    }
}
