import SwiftUI

/// Launch splash that shows the Roam wordmark and network symbol
/// with a scale-up + fade-in animation, then transitions out.
struct SplashView: View {
    @State private var isAnimating = false
    @State private var isFinished = false

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                Text("ROAM")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .tracking(8)
                    .foregroundStyle(.primary)
            }
            .scaleEffect(isAnimating ? 1.0 : 0.7)
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .opacity(isFinished ? 0.0 : 1.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeIn(duration: 0.3)) {
                    isFinished = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onFinished()
                }
            }
        }
    }
}
