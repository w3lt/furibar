import SwiftUI
import FuribarCore

enum Theme {
    /// Furina's hydro blues, with a touch of gold.
    static let hydro = Color(red: 0.27, green: 0.47, blue: 0.96)
    static let hydroLight = Color(red: 0.36, green: 0.75, blue: 0.96)
    static let gold = Color(red: 0.87, green: 0.72, blue: 0.42)
    static let accent = LinearGradient(colors: [hydro, hydroLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardFill = Color.primary.opacity(0.05)
    static let cardStroke = Color.primary.opacity(0.08)
    static let controlFill = Color.primary.opacity(0.07)
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { CardTitle(text: title) }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 0.5))
    }
}

struct CardTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// A big square-ish button for the main modes.
struct ModeTile: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.controlFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.gold.opacity(0.7) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small capsule choice.
struct Chip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.controlFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An on/off tile for the quick settings row.
struct ToggleTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .background(Circle().fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.controlFill)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(isOn ? "On" : "Off").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.controlFill))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Row label with an icon, used by switches and steppers.
struct RowLabel: View {
    let title: String
    let symbol: String
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.hydro)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A row with a pure-SwiftUI switch (renders the same everywhere, including snapshots).
struct SwitchRow: View {
    let title: String
    let symbol: String
    var detail: String?
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button {
            set(!isOn)
        } label: {
            HStack {
                RowLabel(title: title, symbol: symbol, detail: detail)
                Spacer(minLength: 8)
                Capsule()
                    .fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: 30, height: 18)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                            .padding(2)
                            .offset(x: isOn ? 6 : -6)
                    )
                    .animation(.easeOut(duration: 0.15), value: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// − value + control for level settings whose range the protocol doesn't state.
/// The earbuds reject values they don't accept, and the session puts the old value back.
struct LevelRow: View {
    let title: String
    let symbol: String
    let value: UInt8
    var range: ClosedRange<UInt8> = 0...15
    let set: (UInt8) -> Void

    var body: some View {
        HStack {
            RowLabel(title: title, symbol: symbol)
            Spacer()
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound) { set(value - 1) }
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 26)
                stepButton("plus", enabled: value < range.upperBound) { set(value + 1) }
            }
            .background(Capsule().fill(Theme.controlFill))
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
        }
    }
}

/// Collapsible section; only one is open at a time so the panel stays a sensible height.
struct FoldSection<Content: View>: View {
    let id: String
    let title: String
    let symbol: String
    @Binding var expanded: String
    @ViewBuilder var content: Content

    private var isOpen: Bool { expanded == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded = isOpen ? "" : id }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.hydro)
                        .frame(width: 18)
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 0.5))
    }
}

struct BatteryPill: View {
    let label: String
    let level: BatteryLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(level.percent <= 15 && !level.charging ? Color.red : Color.primary)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text("\(level.percent)%").font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.controlFill))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if level.charging { return "battery.100percent.bolt" }
        switch level.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct Banner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}
