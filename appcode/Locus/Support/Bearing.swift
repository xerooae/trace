import SwiftUI

/// The Bearing on its 60 x 80 frame. Corners come from branding/source/build.mjs.
struct BearingShape: Shape {
    enum Half { case glass, light, both }
    var half: Half = .both

    func path(in rect: CGRect) -> Path {
        // Glass half (left, where you are) and light half (right, 4 units ahead).
        let glass: [CGPoint] = [.init(x: 30, y: 4), .init(x: 0, y: 80), .init(x: 30, y: 61)]
        let light: [CGPoint] = [.init(x: 30, y: 0), .init(x: 30, y: 57), .init(x: 60, y: 76)]
        let polygons: [[CGPoint]]
        switch half {
        case .glass: polygons = [glass]
        case .light: polygons = [light]
        case .both: polygons = [glass, light]
        }
        let scale = min(rect.width / 60, rect.height / 80)
        let origin = CGPoint(x: rect.midX - 30 * scale, y: rect.midY - 40 * scale)
        var path = Path()
        for polygon in polygons {
            path.addLines(polygon.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
            path.closeSubpath()
        }
        return path
    }
}

/// The rendered Bearing. The light half glows and casts a soft shadow across
/// the glass half and onto the ground; `lit: false` gives the flat two-tone mark.
struct BearingMark: View {
    var lit = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width / 60, geo.size.height / 80)
            let glow = lit && !reduceTransparency
            ZStack {
                BearingShape(half: .glass)
                    .fill(glow
                          ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.66), .white.opacity(0.30)],
                                                         startPoint: .topTrailing, endPoint: .bottomLeading))
                          : AnyShapeStyle(TraceTheme.glassHalf))
                if glow {
                    BearingShape(half: .light)
                        .fill(.black.opacity(0.55))
                        .offset(x: -2.6 * u, y: 0.9 * u)
                        .blur(radius: 1.3 * u)
                        .mask(BearingShape(half: .glass))
                }
                BearingShape(half: .light)
                    .fill(LinearGradient(colors: [.white, Color(white: glow ? 0.886 : 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .white.opacity(glow ? 0.3 : 0), radius: 1.8 * u)
                    .shadow(color: .white.opacity(glow ? 0.12 : 0), radius: 8 * u)
            }
            .shadow(color: .black.opacity(glow ? 0.85 : 0), radius: 3.6 * u, x: -1.4 * u, y: 4 * u)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }
}

enum PositionState: Equatable {
    case off, candidate, connecting, live, interrupted
}

/// The position marker. The only element in Trace that may emit light.
struct PositionMarker: View {
    var state: PositionState
    var heading: Angle = .zero
    var width: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        marker
            .frame(width: width, height: width * 4 / 3)
            .rotationEffect(state == .live ? heading : .zero)
            .animation(.spring(duration: 0.3, bounce: 0), value: heading)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .off:
            BearingShape().fill(TraceTheme.ink3)
        case .candidate:
            BearingShape().fill(TraceTheme.ink2)
        case .connecting:
            if reduceMotion {
                BearingShape().fill(TraceTheme.ink2)
            } else {
                BearingShape().fill(TraceTheme.accent)
                    .phaseAnimator([1.0, 0.35]) { mark, opacity in
                        mark.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.8) }
            }
        case .live:
            BearingMark()
        case .interrupted:
            BearingShape().fill(TraceTheme.signal)
        }
    }
}

/// Your real position: always grey, always a diamond.
struct RealPositionMarker: View {
    var body: some View {
        Rectangle()
            .stroke(TraceTheme.ink3, lineWidth: 1.5)
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(45))
            .frame(width: 16, height: 16)
            .accessibilityLabel("Your real position")
    }
}
