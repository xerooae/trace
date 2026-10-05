import CoreLocation
import SwiftUI

/// Trace tokens (BRAND_GUIDELINES.md §5). No hue: black, white, and white at fixed opacities.
enum TraceTheme {
    static let accent = Color.white
    static let ink = Color.white.opacity(0.92)
    static let ink2 = Color.white.opacity(0.60)
    static let glassHalf = Color.white.opacity(0.56)
    static let ink3 = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.16)
    static let hairlineHigh = Color.white.opacity(0.30)
    static let rule = Color.white.opacity(0.09)
    /// Controls that sit inside glass (tray buttons, fields).
    static let fill = Color.white.opacity(0.08)
    static let graphite = Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255)
    static let signal = Color(red: 1, green: 69 / 255, blue: 58 / 255)

    static let gutter: CGFloat = 16
    static let trayRadius: CGFloat = 28
    static let trayPadding: CGFloat = 12
    static let rowGap: CGFloat = 10

    /// Precise, not bouncy.
    static let motion = Animation.spring(duration: 0.35, bounce: 0)
    static let camera = Animation.easeInOut(duration: 0.6)
}

// MARK: - Glass

enum TraceGlassStyle {
    case regular
    case clear
}

/// Liquid Glass for the navigation layer. Reduce Transparency gets graphite and a hairline.
struct TraceGlassModifier<S: Shape>: ViewModifier {
    var style: TraceGlassStyle
    var interactive: Bool
    var shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(TraceTheme.graphite, in: shape)
                .overlay {
                    shape.stroke(contrast == .increased ? TraceTheme.hairlineHigh : TraceTheme.hairline, lineWidth: 1)
                }
                .contentShape(shape)
        } else {
            content
                .glassEffect(glass, in: shape)
                // Glass draws outside the layout bounds; expand hit-testing to match.
                .contentShape(shape)
        }
    }

    private var glass: Glass {
        let base: Glass = style == .clear ? .clear : .regular
        return interactive ? base.interactive() : base
    }
}

extension View {
    /// Never tinted: glass in Trace has no hue.
    func traceGlass<S: Shape>(_ style: TraceGlassStyle = .regular, interactive: Bool = false, in shape: S) -> some View {
        modifier(TraceGlassModifier(style: style, interactive: interactive, shape: shape))
    }

    /// Lists sit on black with graphite rows and sentence-case headers.
    func traceList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.black)
            .textCase(nil)
    }
}

// MARK: - Buttons

/// The single white action on a screen. 50 pt in the tray and sheets, 56 standalone.
/// Disabled, it turns to glass with an ink3 label: white always means "you can do this".
struct TracePrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    var expand = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? Color.black : TraceTheme.ink3)
            .padding(.horizontal, 18)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: height)
            .background(isEnabled ? Color.white : Color.white.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}

/// Secondary actions: Stop, Cancel, Route here. Stopping isn't destructive, so it isn't red.
struct TraceGlassButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    var expand = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? TraceTheme.ink : TraceTheme.ink3)
            .padding(.horizontal, 16)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: height)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Round icon buttons. Selected means inversion: white fill, black glyph.
struct TraceIconButtonStyle: ButtonStyle {
    var size: CGFloat = 50
    var selected = false
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selected ? Color.black : TraceTheme.ink)
            .frame(width: size, height: size)
            .background(fillColor(pressed: configuration.isPressed), in: Circle())
            .contentShape(Circle())
    }

    private func fillColor(pressed: Bool) -> Color {
        if selected { return .white }
        if !filled { return pressed ? TraceTheme.fill : .clear }
        return Color.white.opacity(pressed ? 0.16 : 0.08)
    }
}

/// Quiet text buttons: Use email instead, Restore purchases.
struct TraceTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(configuration.isPressed ? TraceTheme.ink : TraceTheme.ink2)
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
    }
}

// MARK: - Selection

/// Selection is inversion: a white track with a black knob.
struct TraceToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(duration: 0.2, bounce: 0)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .foregroundStyle(TraceTheme.ink)
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.white : TraceTheme.hairline)
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(configuration.isOn ? Color.black : TraceTheme.ink)
                        .frame(width: 27, height: 27)
                        .padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .sensoryFeedback(.impact(weight: .light), trigger: configuration.isOn)
    }
}

/// Segmented choice by inversion: travel mode, the Places switch.
struct TraceSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(.spring(duration: 0.2, bounce: 0)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? Color.black : TraceTheme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if isOn { Capsule().fill(Color.white) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.07), in: Capsule())
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
    }
}

// MARK: - Shared pieces

/// Numbered steps on graphite, for pairing instructions.
struct StepsCard: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Rectangle().fill(TraceTheme.rule).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(TraceTheme.ink3)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(TraceTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(TraceTheme.graphite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TraceTheme.rule, lineWidth: 1))
    }
}

/// Full-screen step: reading at the top, actions at the bottom edge.
struct StepLayout<Content: View, Actions: View>: View {
    let title: String
    let message: String
    let content: Content
    let actions: Actions

    init(_ title: String, message: String, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(TraceTheme.ink)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(TraceTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                actions
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Formatting

enum Coord {
    /// `35.6595° N 139.7005° E`. 4 decimals (about 11 m) in compact UI, 5 (about 1 m) in detail views.
    static func format(_ c: CLLocationCoordinate2D, decimals: Int = 4) -> String {
        let (lat, lon) = parts(c, decimals: decimals)
        return "\(lat) \(lon)"
    }

    static func parts(_ c: CLLocationCoordinate2D, decimals: Int = 4) -> (String, String) {
        let lat = String(format: "%.\(decimals)f° %@", abs(c.latitude), c.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.\(decimals)f° %@", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
        return (lat, lon)
    }

    static func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.latitude - b.latitude) < 0.000001 && abs(a.longitude - b.longitude) < 0.000001
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func distanceText(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}
