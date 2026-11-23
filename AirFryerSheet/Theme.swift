import SwiftUI

enum Theme {
    static let paper = Color(red: 251/255, green: 248/255, blue: 242/255)
    static let surface = Color(red: 255/255, green: 253/255, blue: 250/255)
    static let ink = Color(red: 42/255, green: 33/255, blue: 28/255)
    static let muted = Color(red: 103/255, green: 86/255, blue: 75/255)
    static let line = Color(red: 232/255, green: 220/255, blue: 208/255)
    static let accent = Color(red: 154/255, green: 59/255, blue: 18/255)
    static let tint = Color(red: 246/255, green: 232/255, blue: 220/255)
}

enum ButtonKind { case primary, secondary, quiet, chip }

struct Action: View {
    let title: String
    let id: String
    var kind: ButtonKind = .secondary
    var symbol: String? = nil
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title).multilineTextAlignment(.center)
            }
            .font(kind == .quiet || kind == .chip ? .subheadline.weight(.semibold) : .callout.weight(.semibold))
            .padding(.horizontal, kind == .quiet ? 5 : 11)
            .padding(.vertical, 6)
            .frame(minWidth: 44, maxWidth: kind == .quiet || kind == .chip ? nil : .infinity,
                   minHeight: kind == .primary ? 52 : 44)
            .foregroundStyle(kind == .primary ? .white : Theme.accent)
            .background(background, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                if kind == .secondary || kind == .chip {
                    RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: Theme.surface
        case .quiet: .clear
        case .chip: Theme.tint
        }
    }
}

struct Panel<Content: View>: View {
    var tinted = false
    var inset: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tinted ? Theme.tint : Theme.surface, in: RoundedRectangle(cornerRadius: 19))
            .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(Theme.line).allowsHitTesting(false) }
    }
}

struct PageHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.heavy)).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if let detail { Hint(detail) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Hint: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption2.weight(.heavy)).tracking(0.6).foregroundStyle(Theme.accent)
            .textCase(.uppercase)
    }
}

struct RecipeNumbers: View {
    let settings: Settings
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(unit.label(settings.celsius)).font(.callout.weight(.bold))
            Hint(L.f("format.minutes", settings.minutes))
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

struct Pair<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) { content }
            VStack(spacing: 8) { content }
        }
    }
}

extension View {
    func sheetPalette() -> some View {
        foregroundStyle(Theme.ink).tint(Theme.accent).preferredColorScheme(.light)
    }
}
