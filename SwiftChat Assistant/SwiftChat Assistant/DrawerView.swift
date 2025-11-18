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
    @State private var showAccountSheet = false

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
                        Task {
                            await session.createNewChat()
                            await MainActor.run {
                                withAnimation(.spring(response: 0.33, dampingFraction: 0.85)) {
                                    showDrawer = false
                                }
                            }
                        }
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
                            // Colored icon when selected
                            Image(systemName: chat.id == session.currentChat?.id ? "message.fill" : "message")
                                .foregroundColor(.white)
                                .frame(width: 20)

                            Text(chat.title.isEmpty ? "Untitled" : chat.title)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    (chat.id == session.currentChat?.id)
                                    ? Color.white.opacity(0.08)
                                    : Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            chatToDelete = chat
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        .tint(.red)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .refreshable {
                await refreshChats()
            }
            
            // ACCOUNT FOOTER
            Button {
                showAccountSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(session.user?.first_name ?? "") \(session.user?.last_name ?? "")")
                        .foregroundStyle(.white)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.up")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.all)
        .alert("Are you sure?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                chatToDelete = nil
            }
            Button("Delete", role: .destructive) {
                let chat = chatToDelete
                chatToDelete = nil
                guard let chat else { return }
                Task {
                    await session.deleteChat(chat)
                }
            }
        } message: {
            Text("This chat will be permanently deleted.")
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountSheet(session: session)
                .presentationDetents([.fraction(0.33), .medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    @MainActor
    private func refreshChats() async {
        do {
            try await session.loadChats()
        } catch {
            print("Failed to refresh chats: \(error)")
        }
    }
}

private struct AccountSheet: View {
    @Bindable var session: SessionViewModel

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("\(session.user?.first_name ?? "") \(session.user?.last_name ?? "")")
                    .font(.headline)
                if let email = session.user?.email, !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Spacer()

            Button(role: .destructive) {
                session.signOut()
            } label: {
                Text("Log Out")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
    }
}

