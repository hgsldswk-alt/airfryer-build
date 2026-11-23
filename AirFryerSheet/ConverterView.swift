import SwiftUI

@MainActor
struct ConverterView: View {
    @EnvironmentObject private var model: AppModel
    private enum Field: Hashable { case temperature, minutes }

    @FocusState private var focused: Field?
    @State private var temperature = ""
    @State private var minutes = ""
    let onBack: () -> Void

    private var unit: TemperatureUnit { model.state.unit }
    private var range: ClosedRange<Int> { OvenConversion.range(for: unit) }

    private var estimate: OvenConversion.Estimate? {
        guard let temperature = number(temperature), let minutes = number(minutes) else { return nil }
        return OvenConversion.suggest(oven: temperature, minutes: minutes, unit: unit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Action(L.t("nav.chart"), id: "convert.back", kind: .quiet, symbol: "chevron.left", run: onBack)
                PageHeader(title: L.t("convert.title"), detail: L.t("convert.help"))
                Panel {
                    VStack(alignment: .leading, spacing: 9) {
                        field(L.f("convert.temperature", unit.symbol), text: $temperature,
                              key: .temperature, id: "convert.temperature")
                        field(L.t("convert.minutes"), text: $minutes, key: .minutes, id: "convert.minutes")
                        Hint(L.f("convert.range", range.lowerBound, range.upperBound, unit.symbol))
                    }
                }
                if let estimate {
                    Panel(tinted: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(L.t("convert.suggestion"))
                            Text("\(estimate.temperature)\(unit.symbol)").font(.largeTitle.weight(.heavy))
                                .monospacedDigit().accessibilityIdentifier("convert.result.temperature")
                            Text(L.f("convert.checkIn", estimate.firstCheck)).font(.headline)
                                .accessibilityIdentifier("convert.result.minutes")
                        }
                    }
                } else if !temperature.isEmpty && !minutes.isEmpty {
                    Hint(L.t("convert.invalid")).accessibilityIdentifier("convert.invalid")
                }
                Hint(L.t("convert.caution"))
                if focused != nil {
                    Action(L.t("action.done"), id: "convert.keyboard.done", kind: .quiet) { focused = nil }
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)

    }

    private func field(_ label: String, text: Binding<String>, key: Field, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            TextField(label, text: text)
                .keyboardType(.numberPad)
                .focused($focused, equals: key)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(id)
        }
    }

    private func number(_ text: String) -> Int? {
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == text.count, digits.allSatisfy({ $0 < 10 }) else { return nil }
        return Int(digits.map { String($0) }.joined())
    }
}
