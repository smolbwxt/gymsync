import SwiftUI

// Moved out of GroupSessionLiveView (2026-07-30, solo port): the solo
// workout's entry card uses the identical accelerating stepper, and a
// fileprivate struct can't cross files. Behaviour unchanged.
// MARK: - TurnAutoRepeatButton (2026-07-30)
// Press-and-hold stepper for the my-turn entry card. User spec: "a press
// and hold should continue to count up the pounds, accelerating to 50 lbs
// per second at max velocity."
//
// Mechanics: one step fires on touch-down (so a tap still steps exactly
// once); holding past 400ms starts repeating at ~3.5 steps/s and each
// repeat shortens the interval by ×0.82 down to a 100ms floor — with the
// 5 lb weight step that is 10 steps/s = 50 lb/s at max velocity, reached
// about 1.2s into the hold. Release cancels instantly.
//
// A DragGesture(minimumDistance: 0) carries the press. That is legal HERE
// because the fixed my-turn page has no vertical ScrollView for it to
// fight — the exact conflict WorkoutSessionView.swift documents against
// hand-rolled gestures inside scrolls does not exist on this page.
struct TurnAutoRepeatButton: View {
    let glyph: String
    let detail: String?
    let theme: GSTheme
    let step: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.text.opacity(isPressed ? 1 : 0.78))
            if let detail {
                Text(detail)
                    .font(GSFont.bold(15, relativeTo: .subheadline).monospacedDigit())
                    .foregroundStyle(theme.neutral700)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginPressIfNeeded() }
                .onEnded { _ in endPress() }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(glyph == "plus" ? "Increase" : "Decrease")
    }

    private func beginPressIfNeeded() {
        guard repeatTask == nil else { return }
        isPressed = true
        step()  // touch-down step: a tap always steps exactly once
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            var interval = 280.0
            while !Task.isCancelled {
                step()
                try? await Task.sleep(for: .milliseconds(Int(interval)))
                interval = max(100, interval * 0.82)
            }
        }
    }

    private func endPress() {
        isPressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}
