import SwiftUI

struct ChatContainerView: View {
    @State var session: SessionViewModel
    @State private var showDrawer = false
    @State private var dragOffset: CGFloat = 0

    private let drawerWidth: CGFloat = 280

    var body: some View {
        ZStack {
            // MAIN CHAT
            ChatView(session: session, showDrawer: $showDrawer)
                .offset(x: showDrawer ? drawerWidth : 0)
                .offset(x: dragOffset)
                .gesture(
                    showDrawer ?
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -100 {
                                withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                                    showDrawer = false
                                    dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                                    dragOffset = 0
                                }
                            }
                        }
                    : nil
                )
                .zIndex(1)

            // TOP BAR BUTTONS
            if !showDrawer {
                VStack {
                    HStack {
                        // HAMBURGER BUTTON
                        GlassEffectContainer(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                                    showDrawer = true
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive())
                            }
                        }

                        Spacer()

                        // NEW CHAT BUTTON
                        GlassEffectContainer(spacing: 12) {
                            Button {
                                Task { await session.createNewChat() }
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()
                }
                .zIndex(2)
                .offset(x: showDrawer ? drawerWidth : 0)
                .offset(x: dragOffset)
            }

            // DIM BACKGROUND
            if showDrawer {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                            showDrawer = false
                        }
                    }
                    .zIndex(3)
            }

            // DRAWER
            HStack(spacing: 0) {
                DrawerView(session: session, showDrawer: $showDrawer)
                    .frame(width: drawerWidth)
                    .offset(x: showDrawer ? 0 : -drawerWidth)
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.width < 0 {
                                    dragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                if value.translation.width < -100 {
                                    withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                                        showDrawer = false
                                        dragOffset = 0
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )

                Spacer()
            }
            .ignoresSafeArea()
            .zIndex(4)
        }
    }
}

#Preview { ChatContainerView(session: SessionViewModel()) }
