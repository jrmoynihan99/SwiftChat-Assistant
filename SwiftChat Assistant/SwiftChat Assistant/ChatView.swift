import SwiftUI
import MarkdownUI

struct ChatView: View {
    @Bindable var session: SessionViewModel
    @Binding var showDrawer: Bool   // still passed in, even if not used here now
    @State private var scrollProxy: ScrollViewProxy?
    @Namespace private var glassNS
    @FocusState private var isComposerFocused: Bool
    @State private var isScrolledToBottom = true
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        ZStack {
            // Main content layer
            ZStack {
                // Full-screen black background that ignores ALL safe areas
                Color.black
                    .ignoresSafeArea(.all, edges: .all)
                
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                    if session.messages.isEmpty {
                                        VStack(spacing: 12) {
                                            Image(systemName: "bubble.left.and.bubble.right")
                                                .font(.system(size: 28, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.7))
                                            Text("Start a new conversation")
                                                .foregroundStyle(.white.opacity(0.8))
                                                .font(.headline)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 80)
                                    }
                                    
                                    ForEach(session.messages) { message in
                                        MessageBubble(
                                            message: message,
                                            streamingAssistantId: session.streamingAssistantId,
                                            parser: session.markdownParser,
                                            animatedCharacters: session.animatedCharacters
                                        )
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom)
                                                .combined(with: .opacity)
                                                .combined(with: .scale(scale: 0.95)),
                                            removal: .identity
                                        ))
                                    }
                                    
                                    // Hidden marker at the bottom to detect scroll position
                                    GeometryReader { geometry in
                                        Color.clear
                                            .frame(height: 1)
                                            .id("bottom")
                                            .onChange(of: geometry.frame(in: .named("scroll")).minY) { _, newY in
                                                // Check if bottom marker is visible in scroll view
                                                isScrolledToBottom = newY < UIScreen.main.bounds.height
                                            }
                                    }
                                    .frame(height: 1)
                                }
                                .padding(.horizontal, 0)
                                .padding(.bottom, 16)
                                .padding(.top, 80)
                                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: session.messages.count)
                                .onAppear {
                                    scrollProxy = proxy
                                }
                        }
                        .coordinateSpace(name: "scroll")
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: session.messages.count) { _, _ in
                            scrollToBottomIfNeeded()
                        }
                        .onChange(of: isComposerFocused) { _, focused in
                            if focused {
                                scrollToBottomAnimated()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                                keyboardHeight = keyboardFrame.height
                                scrollToBottomAnimated()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                            keyboardHeight = 0
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                                keyboardHeight = frame.height
                            }
                        }
                    }
                }
                
                // Edge fades above content, below composer/menu
                LinearGradient(
                    colors: [Color.black.opacity(0.9), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .zIndex(1)
                
                GeometryReader { proxy in
                    let bottomInset = proxy.safeAreaInsets.bottom
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                    .zIndex(1)
                }
            }
            .safeAreaInset(edge: .bottom) {
                GlassEffectContainer(spacing: 12) {
                    composer
                        .padding(.bottom, isComposerFocused ? 10 : 2)
                }
            }
            .overlay(alignment: .bottom) {
                // Scroll to bottom button - positioned above composer without affecting layout
                if !isScrolledToBottom {
                    Button {
                        scrollToBottomAnimated()
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .glassEffect(.regular.interactive())
                            .glassEffectID("scrollButton", in: glassNS)
                    }
                    .transition(.scale.combined(with: .opacity))
                    .padding(.bottom, 60) // Position above composer
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isScrolledToBottom)
            .onChange(of: session.shouldFocusComposer) { _, newValue in
                if newValue {
                    DispatchQueue.main.async {
                        isComposerFocused = true
                        // Reset the flag so it only fires once per new chat
                        session.shouldFocusComposer = false
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {  // Changed from .center to .bottom
            TextField("Message", text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .lineLimit(1...4)
                .focused($isComposerFocused)

            Button {
                // Dismiss keyboard immediately
                isComposerFocused = false
                
                Task { await session.send() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 34, height: 34)
                    if session.sending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.sending)
            .opacity((session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.sending) ? 0.5 : 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))// Add fixed cornerRadius
        .glassEffectID("", in: glassNS)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            isComposerFocused = true
        }
    }
    
    private func scrollToBottomAnimated() {
        guard let proxy = scrollProxy else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        
        isScrolledToBottom = true
    }
    
    private func scrollToBottomIfNeeded() {
        if isScrolledToBottom {
            scrollToBottomAnimated()
        }
    }
}

// ✅ MessageBubble with animated character rendering
private struct MessageBubble: View {
    let message: Message
    let streamingAssistantId: String?
    @Bindable var parser: StreamingMarkdownParser
    let animatedCharacters: [AnimatedCharacter]
    
    // State to hold the incrementally built AttributedString
    @State private var displayedAttributedString = AttributedString("")
    
    var isUser: Bool { message.role.lowercased() == "user" }
    var isTyping: Bool { message.content.isEmpty && !isUser }
    var isStreaming: Bool { streamingAssistantId == message.id }
    
    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 40)
            }

            if isUser {
                // USER: keep bubble styling
                VStack(alignment: .leading, spacing: 6) {
                    if isTyping {
                        TypingIndicator()
                    } else {
                        Text(message.content)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue)
                )
                .padding(.horizontal, 16)
            } else {
                // ASSISTANT: full width, no bubble/background
                VStack(alignment: .leading, spacing: 0) {
                    if isTyping {
                        TypingIndicator()
                    } else if isStreaming {
                        // STREAMING: Completed blocks as Markdown, current text as animated characters
                        VStack(alignment: .leading, spacing: 8) {
                            // Completed blocks → MarkdownUI (retroactively formatted)
                            ForEach(parser.completedBlocks) { block in
                                Markdown(block.content)
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                            }
                            
                            // Current streaming text → Animated characters with fade-in
                            if !animatedCharacters.isEmpty {
                                Text(displayedAttributedString)
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                                    .onChange(of: animatedCharacters.count) { oldCount, newCount in
                                        // Immediately clear if array was emptied
                                        if newCount == 0 {
                                            displayedAttributedString = AttributedString("")
                                            return
                                        }
                                        
                                        // Only append the new character(s) incrementally
                                        if newCount > oldCount {
                                            for i in oldCount..<newCount {
                                                let char = animatedCharacters[i]
                                                var charString = AttributedString(char.character)
                                                charString.foregroundColor = .white.opacity(char.opacity)
                                                displayedAttributedString += charString
                                            }
                                        }
                                    }
                                    .onChange(of: animatedCharacters.map { $0.opacity }) { _, _ in
                                        // Only update if we have characters
                                        guard !animatedCharacters.isEmpty else { return }
                                        
                                        // Update opacity of characters when they animate
                                        var updated = AttributedString("")
                                        for char in animatedCharacters {
                                            var charString = AttributedString(char.character)
                                            charString.foregroundColor = .white.opacity(char.opacity)
                                            updated += charString
                                        }
                                        withAnimation(.easeIn(duration: 0.5)) {
                                            displayedAttributedString = updated
                                        }
                                    }
                            } else {
                                // Ensure state is cleared when array is empty
                                Color.clear.frame(height: 0)
                                    .onAppear {
                                        displayedAttributedString = AttributedString("")
                                    }
                            }
                        }
                    } else {
                        // FINAL: Pure MarkdownUI with decoded content
                        let decoded = decodeContent(message.rawContent ?? message.content)
                        Markdown(decoded)
                            .id("final-\(message.id)")
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .padding(.top, 40)
            }
        }
    }
    
    private func decodeContent(_ text: String) -> String {
        let decoded = decodeUnicodeEscapes(in: text)
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\r", with: "\n")
        return decoded
    }
    
    private func decodeUnicodeEscapes(in text: String) -> String {
        let wrapped = "\"" + text.replacingOccurrences(of: "\\\"", with: "\\\\\"") + "\""
        if let data = wrapped.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return text
    }
}

private struct TypingIndicator: View {
    @State private var animationPhase: Int = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(animationPhase == index ? 1.0 : 0.3))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2), value: animationPhase)
            }
        }
        .onAppear {
            animationPhase = 0
            withAnimation { animationPhase = 2 }
        }
    }
}

