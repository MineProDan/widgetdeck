import CoreKit
import StudentFeatureWidgetKit
import SwiftUI
import WidgetKit

/// Student section widgets (S-03). Views, snapshot types and the timeline provider live in the
/// `StudentFeatureWidgetKit` package product; timelines come only from App Group snapshots.
struct StudentWidgets: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        TodayScheduleWidget()
        AssignmentsWidget()
        FocusLiveActivity()
    }
}

/// Open assignments and calendar deadlines, soonest first (S-05).
struct AssignmentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.assignments.kindIdentifier, provider: AssignmentsProvider()) { entry in
            AssignmentsWidgetView(entry: entry)
        }
        .configurationDisplayName("Assignments Due")
        .description("What's due next, from your assignments and calendar.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

/// Focus timer Live Activity: Lock Screen chip + Dynamic Island (LockScreen.png, S-08).
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreenView(context: context)
        } dynamicIsland: { context in
            FocusIsland.make(context: context)
        }
    }
}

/// Next class with a self-updating countdown. Entries at every class start/end.
struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextClass.kindIdentifier,
                            provider: StudentScheduleProvider<NextClassSnapshot>()) { entry in
            NextClassWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Class")
        .description("Your next class and how long until it starts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

/// The rest of today's classes. Rolls over at midnight.
struct TodayScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.todaySchedule.kindIdentifier,
                            provider: StudentScheduleProvider<TodayScheduleSnapshot>()) { entry in
            TodayScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Schedule")
        .description("Today's classes, in order.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
