import CoreLocation
import SwiftUI
import UIKit

/// Trace colours on top of Apple's semantic system colours, so greys, cells and
/// separators match the Settings app. Accent stays white; red is for errors only.
enum TraceTheme {
    static let accent = Color.white
    static let ink = Color.primary
    static let ink2 = Color.secondary
    static let ink3 = Color(uiColor: .tertiaryLabel)
    static let glassHalf = Color.white.opacity(0.56)
    static let separator = Color(uiColor: .separator)
    /// Fills for fields and controls (Settings uses these too).
    static let fill = Color(uiColor: .tertiarySystemFill)
    /// Grouped backgrounds, exactly as in Settings.
    static let background = Color(uiColor: .systemGroupedBackground)
    static let cell = Color(uiColor: .secondarySystemGroupedBackground)
    static let signal = Color(uiColor: .systemRed)
    /// Native toggles switch to system grey, not green: the brand has no hue.
    static let toggleOn = Color(uiColor: .systemGray)

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

/// Liquid Glass for the navigation layer that floats over the map.
struct TraceGlassModifier<S: Shape>: ViewModifier {
    var style: TraceGlassStyle
    var interactive: Bool
    var shape: S

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: shape)
            // Glass draws outside the layout bounds; expand hit-testing to match.
            .contentShape(shape)
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

    /// Native toggle, system grey when on.
    func traceToggle() -> some View {
        tint(TraceTheme.toggleOn)
    }
}

// MARK: - Buttons (native styles)

/// The single white action on a screen: a native prominent capsule, white with a black label.
struct PrimaryButton: View {
    let title: String
    var size: ControlSize = .large
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, size: ControlSize = .large, action: @escaping () -> Void) {
        self.title = title
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isEnabled ? Color.black : TraceTheme.ink3)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(size)
        .tint(.white)
    }
}

/// Secondary actions (Stop, Cancel, Route here): a native bordered capsule.
/// Stopping isn't destructive, so it isn't red.
struct SecondaryButton<Label: View>: View {
    var size: ControlSize = .large
    var expand = true
    let action: () -> Void
    let label: Label

    init(size: ControlSize = .large, expand: Bool = true, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.size = size
        self.expand = expand
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: expand ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(size)
        .tint(.white)
    }
}

extension SecondaryButton where Label == Text {
    init(_ title: String, size: ControlSize = .large, expand: Bool = true, action: @escaping () -> Void) {
        self.init(size: size, expand: expand, action: action) { Text(title) }
    }
}

/// Round icon buttons in the tray. Selected means inversion: white fill, black glyph.
struct CircleButton: View {
    let systemImage: String
    let label: String
    var selected = false
    var size: ControlSize = .large
    let action: () -> Void

    var body: some View {
        if selected {
            Button(action: action) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.black)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(size)
            .tint(.white)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(size)
            .tint(.white)
            .accessibilityLabel(label)
        }
    }
}

// MARK: - Shared pieces

/// Numbered steps in a grouped cell, for pairing instructions.
struct StepsCard: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Divider().padding(.leading, 30)
                }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(TraceTheme.cell, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
                        .font(.largeTitle.bold())
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

            VStack(spacing: TraceTheme.rowGap) {
                actions
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TraceTheme.background.ignoresSafeArea())
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
