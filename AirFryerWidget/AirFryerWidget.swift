import ActivityKit
import SwiftUI
import WidgetKit

struct PinnedEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetData.Snapshot?
    var preview = false
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedEntry {
        PinnedEntry(date: .now, preview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
        completion(PinnedEntry(date: .now, snapshot: WidgetData.read(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
        let snapshot = WidgetData.read()
        let now = Date()
        var entries = [PinnedEntry(date: now, snapshot: snapshot)]
        if let expiration = snapshot?.validUntil, expiration > now {
            entries.append(PinnedEntry(date: expiration, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct PinnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetData.kind, provider: PinnedProvider()) { entry in
            PinnedWidgetView(entry: entry)
        }
        .configurationDisplayName(L.t("widgets.pinned"))
        .description(L.t("widgets.homeHelp"))
        .supportedFamilies([.systemSmall])
    }
}

private struct PinnedWidgetView: View {
    let entry: PinnedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L.t("widgets.pinned"), systemImage: "star.fill").font(.caption2.weight(.semibold))
            if let snapshot = entry.snapshot, snapshot.hasPro(at: entry.date) {
                Text(snapshot.customName ?? L.t("food." + snapshot.foodID)).font(.headline).lineLimit(2)
                Text(snapshot.fryerName ?? L.t("fryer.default")).font(.caption).lineLimit(1)
                Text(L.f("format.join", snapshot.unit.label(snapshot.celsius),
                         L.f("format.minutes", snapshot.duration))).font(.caption.weight(.semibold)).monospacedDigit()
            } else if entry.preview {
                Text(L.t("food.fries")).font(.headline)
                Text(L.f("format.join", TemperatureUnit.regional.label(190), L.f("format.minutes", 14))).font(.caption)
            } else {
                Text(L.t(entry.snapshot == nil ? "widgets.noFood" : "widgets.included")).font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Color(red: 42/255, green: 33/255, blue: 28/255))
        .containerBackground(for: .widget) { Color(red: 246/255, green: 232/255, blue: 220/255) }
        .widgetURL(entry.snapshot.flatMap { $0.hasPro(at: entry.date) ? $0.url : nil })
    }
}

struct FryerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookActivity.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.food).font(.headline)
                    Text(context.attributes.fryer).font(.caption)
                    Text(context.state.temperature).font(.caption).monospacedDigit()
                }
                Spacer()
                if context.isStale && context.state.pausedSeconds == nil {
                    Text(L.t("done.check")).font(.headline)
                } else {
                    ActivityCountdown(state: context.state).font(.title2.weight(.bold)).multilineTextAlignment(.trailing)
                }
            }
            .padding(15)
            .activityBackgroundTint(Color(red: 251/255, green: 248/255, blue: 242/255))
            .activitySystemActionForegroundColor(Color(red: 42/255, green: 33/255, blue: 28/255))
            .foregroundStyle(Color(red: 42/255, green: 33/255, blue: 28/255))
            .widgetURL(URL(string: "airfryersheet://timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.food).font(.headline).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityCountdown(state: context.state).font(.headline).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? L.t("done.check") : context.attributes.fryer).font(.caption)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                ActivityCountdown(state: context.state).frame(width: 49)
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(URL(string: "airfryersheet://timer"))
        }
    }
}

private struct ActivityCountdown: View {
    var state: CookActivity.ContentState

    var body: some View {
        Group {
            if let seconds = state.pausedSeconds {
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            } else {
                Text(timerInterval: state.started...state.deadline, countsDown: true, showsHours: false)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

@main
struct AirFryerWidgets: WidgetBundle {
    var body: some Widget {
        PinnedWidget()
        FryerActivityWidget()
    }
}
