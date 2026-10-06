import CoreLocation
import SwiftUI
import UIKit

/// Trace colours on top of Apple's semantic system colours, so greys, cells and
/// separators match the Settings app. Trace Blue marks actions; the Bearing and
/// the live light stay white; red is for errors only.
enum TraceTheme {
    /// Trace Blue, #0070FF: fully saturated. White labels on it 4.4:1, on black 4.8:1.
    static let accent = Color(red: 0, green: 112 / 255, blue: 1)
    /// The light: the Bearing's light half and the live marker. Never blue.
    static let light = Color.white
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
    /// Native toggles switch to Trace Blue.
    static let toggleOn = accent

    static let gutter: CGFloat = 16
    static let trayRadius: CGFloat = 28
    static let trayPadding: CGFloat = 12
    static let rowGap: CGFloat = 10
    /// The iOS 26 tab bar's height. The tray matches it so the two read as a pair.
    static let barHeight: CGFloat = 62

    /// Precise, not bouncy.
    static let motion = Animation.spring(duration: 0.35, bounce: 0)
    static let camera = Animation.easeInOut(duration: 0.6)
}

// MARK: - Haptics

/// Haptics for taps the system doesn't already cover: a light tap for buttons, a
/// firmer press for the blue action, a selection tick for choices.
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func press() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
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

    /// Native toggle, Trace Blue when on.
    func traceToggle() -> some View {
        tint(TraceTheme.toggleOn)
    }
}

// MARK: - Buttons (native styles)

/// The single blue action on a screen: a native prominent capsule in Trace Blue with a white label.
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
        Button {
            Haptics.press()
            action()
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(isEnabled ? Color.white : TraceTheme.ink3)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(size)
        .tint(TraceTheme.accent)
    }
}

/// Secondary actions (Stop, Cancel, Route here): a neutral native bordered capsule,
/// so the blue action stays the only one. Stopping isn't destructive, so it isn't red.
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
        Button {
            Haptics.tap()
            action()
        } label: {
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

// MARK: - Shared pieces

/// List row label: white icon and white text, as in the Settings app.
/// Blue is for toggles and actions, never for row icons.
struct RowLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(isEnabled ? TraceTheme.ink : TraceTheme.ink3)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(isEnabled ? TraceTheme.ink : TraceTheme.ink3)
        }
    }
}

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

    /// Reads typed coordinates: `47.14561, 27.60692`, `47.14561 27.60692`, `-33.89 151.27`,
    /// `47.1456° N 27.6069° E` or `47.1456N, 27.6069E`. Without N/S/E/W the first
    /// number is latitude. Returns nil for anything else.
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        let input = text.uppercased().replacingOccurrences(of: "°", with: " ")
        guard let regex = try? NSRegularExpression(pattern: #"([-+]?\d{1,3}(?:\.\d+)?)\s*([NSEW])?"#) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        guard matches.count == 2 else { return nil }

        // Only separators may sit around the two numbers.
        var leftover = input
        for match in matches.reversed() {
            if let r = Range(match.range, in: leftover) { leftover.removeSubrange(r) }
        }
        guard leftover.allSatisfy({ $0 == " " || $0 == "," || $0 == ";" || $0 == "\t" }) else { return nil }

        var values: [(value: Double, hemisphere: Character?)] = []
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: input),
                  let value = Double(input[numberRange]) else { return nil }
            let hemisphere = Range(match.range(at: 2), in: input).flatMap { input[$0].first }
            values.append((value, hemisphere))
        }

        var latitude = values[0].value
        var longitude = values[1].value
        let first = values[0].hemisphere, second = values[1].hemisphere
        if first == "E" || first == "W" || second == "N" || second == "S" {
            swap(&latitude, &longitude)
        }
        for (hemisphere, isLatitude) in [(first, first == "N" || first == "S"), (second, second == "N" || second == "S")] {
            guard let hemisphere, hemisphere == "S" || hemisphere == "W" else { continue }
            if isLatitude { latitude = -abs(latitude) } else { longitude = -abs(longitude) }
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
