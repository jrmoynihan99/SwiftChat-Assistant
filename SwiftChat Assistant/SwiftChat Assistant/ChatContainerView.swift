import UIKit
import SwiftUI

struct ChatContainerView: View {
    @State var session: SessionViewModel
    @State private var showDrawer = false

    private let drawerWidth: CGFloat = 280

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatView(session: session, showDrawer: $showDrawer)

            if !showDrawer {
                GlassEffectContainer(spacing: 12) {
                    Button {
                        withAnimation(.snappy) { showDrawer.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 8)
                }
                .zIndex(2)
            }
        }
    }
}

#Preview { ChatContainerView(session: SessionViewModel()) }
