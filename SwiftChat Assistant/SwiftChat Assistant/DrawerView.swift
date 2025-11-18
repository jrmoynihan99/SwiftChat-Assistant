//
//  DrawerView.swift
//  SwiftChat Assistant
//
//  Created by Jason Moynihan on 11/14/25.
//

import SwiftUI

struct DrawerView: View {
    @Bindable var session: SessionViewModel
    @Binding var showDrawer: Bool
    @State private var chatToDelete: Chat?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text("Chats")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
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
            .padding(.horizontal)
            .padding(.top, 60)
            .padding(.bottom, 20)

            // CHAT LIST
            List {
                ForEach(session.chats) { chat in
                    Button {
                        Task {
                            try? await session.selectChat(chat)
                            withAnimation(.snappy) { showDrawer = false }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: chat.id == session.currentChat?.id ? "message.fill" : "message")
                                .foregroundColor(.white)
                                .frame(width: 20)
                            
                            Text(chat.title.isEmpty ? "Untitled" : chat.title)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible, edges: .bottom)
                    .listRowSeparatorTint(Color.white.opacity(0.2))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            chatToDelete = chat
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.all)
        .alert("Are you sure?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                chatToDelete = nil
            }
            Button("Delete", role: .destructive) {
                // Delete action will go here in the future
                chatToDelete = nil
            }
        } message: {
            Text("This chat will be permanently deleted.")
        }
    }
}
