import SwiftUI

/// Floats above the tray on the thumb side. Clear glass base, hairline ring, ink knob.
struct JoystickPad: View {
    var onChange: (CGVector) -> Void

    @State private var dragOffset: CGSize = .zero
    private let radius: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: 148, height: 148)
                .traceGlass(.clear, in: Circle())

            Circle()
                .stroke(TraceTheme.separator, lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)

            Circle()
                .fill(TraceTheme.ink)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                .offset(dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragOffset == .zero { Haptics.tap() }
                            let limited = clamp(value.translation, radius: radius)
                            dragOffset = limited
                            onChange(CGVector(dx: limited.width / radius, dy: limited.height / radius))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                                dragOffset = .zero
                            }
                            onChange(.zero)
                        }
                )
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joystick")
        .accessibilityHint("Drag to move in any direction.")
    }

    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard length > radius else { return translation }
        let scale = radius / length
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
