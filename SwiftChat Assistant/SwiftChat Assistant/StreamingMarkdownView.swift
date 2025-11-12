import SwiftUI
import MarkdownUI
import Combine

/// Live Markdown renderer for streaming text.
/// Renders progressively while throttling re-parses to avoid frame drops.
struct StreamingMarkdownView: View {
    let text: String
    var throttle: TimeInterval = 0.12   // update every ~120 ms

    @State private var latestRaw: String = ""
    @State private var displayed: String = ""
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        Markdown(displayed)
            .markdownTheme(.gitHub)
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .onAppear {
                latestRaw = text
                displayed = text
                startTimer()
            }
            .onDisappear { stopTimer() }
            .onChange(of: text) { _, newValue in
                latestRaw = newValue
            }
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: throttle, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if displayed != latestRaw {
                    displayed = latestRaw
                }
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}
