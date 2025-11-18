import SwiftUI

struct RootView: View {
    @State private var session = SessionViewModel()

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                LoginView { tokens, _ in
                    if let tokens = tokens {
                        Task { await session.didAuthenticate(tokens) }
                    }
                }
            case .signedIn:
                ChatContainerView(session: session)
            }
        }
    }
}

#Preview { RootView() }

