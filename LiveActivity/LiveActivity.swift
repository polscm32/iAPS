import ActivityKit
import Charts
import SwiftUI
import WidgetKit

struct LiveActivity: Widget {
    let dateFormatter: DateFormatter = {
        var f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if !context.isStale && !context.state.change.isEmpty {
            Text(context.state.change)
        } else {
            Text("--")
        }
    }

    func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        Text("Updated: \(dateFormatter.string(from: context.state.date))")
    }

    func bgLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if context.isStale {
            Text("--")
        } else {
            Text(context.state.bg)
        }
    }

    @ViewBuilder func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            Text(context.state.bg)
            if let trendSystemImage = context.state.trendSystemImage {
                Image(systemName: trendSystemImage)
            }
        }
    }

    @ViewBuilder func chart(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            Chart {
                ForEach(context.state.sixHourReadingsGlucose.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Time", context.state.sixHourReadingsDate[index] ?? Date()),
                        y: .value("Value", context.state.sixHourReadingsGlucose[index] ?? 0)
                    ).foregroundStyle(Color(red: 0.435, green: 0.812, blue: 0.592))
                }
            }
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here

            HStack(spacing: 3) {
                bgAndTrend(context: context).font(.title)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    changeLabel(context: context).font(.title3)
                    updatedLabel(context: context).font(.caption).foregroundStyle(.black.opacity(0.7))
                }
            }
            .privacySensitive()
            .imageScale(.small)
            .padding(.all, 15)
            .background(Color.white.opacity(0.2))
            .foregroundColor(Color.black)
            .activityBackgroundTint(Color.cyan.opacity(0.2))
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 3) {
                        bgAndTrend(context: context)
                    }.imageScale(.small).font(.title).padding(.leading, 5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    changeLabel(context: context).font(.title).padding(.trailing, 5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack {
                        updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                            .padding(.bottom, 5)
                        Spacer()
                        chart(context: context)
                    }
                }
            } compactLeading: {
                HStack(spacing: 1) {
                    bgAndTrend(context: context)
                }.bold().imageScale(.small).padding(.leading, 5)
            } compactTrailing: {
                changeLabel(context: context).padding(.trailing, 5)
            } minimal: {
                bgLabel(context: context).bold()
            }
            .widgetURL(URL(string: "freeaps-x://"))
            .keylineTint(Color.cyan.opacity(0.5))
        }
    }
}

private extension LiveActivityAttributes {
    static var preview: LiveActivityAttributes {
        LiveActivityAttributes(startDate: Date())
    }
}

private extension LiveActivityAttributes.ContentState {
    static var test: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "100",
            trendSystemImage: "arrow.right",
            change: "+2",
            date: Date(),
            sixHourReadingsGlucose: [90, 95, 100],
            sixHourReadingsDate: [
                Calendar.current.date(byAdding: .minute, value: -15, to: Date()),
                Calendar.current.date(byAdding: .minute, value: -10, to: Date()),
                Calendar.current.date(byAdding: .minute, value: -5, to: Date())
            ]
        )
    }
}

#Preview("Notification", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.test
}
