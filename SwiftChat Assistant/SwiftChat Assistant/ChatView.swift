import SwiftUI
import MarkdownUI

struct ChatView: View {
    @Bindable var session: SessionViewModel
    @Binding var showDrawer: Bool
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
                            ScrollViewReader { scrollReader in
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(session.messages) { message in
                                        MessageBubble(
                                            message: message,
                                            streamingAssistantId: session.streamingAssistantId,
                                            parser: session.markdownParser
                                        ).id(message.id)
                                    }
                                    
                                    // Hidden marker at the bottom to detect scroll position
                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom")
                                        .onAppear {
                                            isScrolledToBottom = true
                                        }
                                        .onDisappear {
                                            isScrolledToBottom = false
                                        }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                                .onAppear {
                                    scrollProxy = scrollReader
                                }
                            }
                        }
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
                    }
                }
                
                // Edge fades above content, below composer/menu
                LinearGradient(
                    colors: [Color.black.opacity(0.9), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
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
                    .frame(height: 180)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                    .zIndex(1)
                }
            }
            .safeAreaInset(edge: .bottom) {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 8) {
                        // Scroll to bottom button - centered above input
                        if !isScrolledToBottom {
                            HStack {
                                Spacer()
                                Button {
                                    scrollToBottomAnimated()
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .glassEffect(.regular.interactive())
                                        .glassEffectID("scrollButton", in: glassNS)
                                }
                                Spacer()
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrolledToBottom)
                        }
                        
                        composer
                            .padding(.bottom, isComposerFocused ? 10 : 2)
                    }
                }
            }
            
            // Drawer overlay layer
            if showDrawer {
                Color.black.opacity(0.5)
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.snappy) { showDrawer = false }
                    }
                    .transition(.opacity)

                HStack {
                    drawer
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    Spacer()
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Message", text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .lineLimit(1...4)
                .focused($isComposerFocused)

            Button {
                Task { await session.send() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 32, height: 32)
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
            .padding(.trailing, 6)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("composer", in: glassNS)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    private var drawer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    Task { await session.createNewChat() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)
            .padding(.top, 60)
            .padding(.bottom, 20)
            
            List {
                ForEach(session.chats) { chat in
                    Button {
                        Task {
                            try? await session.selectChat(chat)
                            withAnimation(.snappy) { showDrawer = false }
                        }
                    } label: {
                        HStack {
                            Image(systemName: chat.id == session.currentChat?.id ? "message.fill" : "message")
                                .foregroundColor(.white)
                            Text(chat.title.isEmpty ? "Untitled" : chat.title)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.all)
    }
    
    private func scrollToBottomAnimated() {
        guard let proxy = scrollProxy else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)) {
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

// ✅ MessageBubble with mixed rendering (completed blocks as Markdown, current block as Text)
private struct MessageBubble: View {
    let message: Message
    let streamingAssistantId: String?
    @Bindable var parser: StreamingMarkdownParser
    
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
                        // ✅ STREAMING: Render completed blocks as Markdown, current block as Text
                        VStack(alignment: .leading, spacing: 8) {
                            // Completed blocks → MarkdownUI (retroactively formatted)
                            ForEach(parser.completedBlocks) { block in
                                Markdown(block.content)
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                            }
                            
                            // Current incomplete block → Plain Text (typewriter with raw markdown symbols)
                            if !parser.currentBlock.isEmpty {
                                Text(parser.currentBlock)
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        // ✅ FINAL: Pure MarkdownUI with decoded content
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
