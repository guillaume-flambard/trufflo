import SwiftUI

// The app's motion, in one place: what moves, how much, and never under Reduce
// Motion beyond an opacity change. Short, springy, and only to say something
// happened (a press, a value that changed, a screen that arrived).

/// The press feedback every tappable card, row and button shares: a slight
/// shrink and dim while pressed; only the dim under Reduce Motion.
struct TruffloPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// Arrives once, a few points below and transparent, then settles; the
    /// `order` staggers a screen's blocks by 60 ms each.
    func truffloAppear(order: Int = 0) -> some View {
        modifier(TruffloAppear(order: order))
    }

    /// A slow, small float for an illustration standing alone (empty states).
    func truffloFloat() -> some View {
        modifier(TruffloFloat())
    }
}

private struct TruffloAppear: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(order) * 0.06)) {
                    shown = true
                }
            }
    }
}

private struct TruffloFloat: ViewModifier {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { up = true }
            }
    }
}

/// A small capsule button for in-card actions (accept, refuse, I was there):
/// forest when it is the expected answer, mint otherwise.
struct TruffloCapsuleStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Color.white : Color.truffloForest)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(prominent ? Color.truffloForest : Color(red: 0.89, green: 0.94, blue: 0.90), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
