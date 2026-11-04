import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let cover: UIImage?
}

struct SnapshotProvider: TimelineProvider {
    private func entry() -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetStore.load(), cover: WidgetStore.coverData().flatMap(UIImage.init(data:)))
    }
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .init(book: .init(id: 0, title: "Book title", authors: "Author", progress: 40), streak: 7, longestStreak: 12, goalDone: 9, goalTotal: 24, goalYear: 2026), cover: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app refreshes the snapshot whenever it learns something new; the widget re-reads it hourly regardless.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }
}

private let appURL = URL(string: "bookorb://continue")!

struct ContinueReadingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let book = entry.snapshot?.book {
            HStack(spacing: 12) {
                cover.frame(width: family == .systemSmall ? 52 : 74)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue reading").font(.caption2.weight(.medium)).foregroundStyle(.tint)
                    Text(book.title).font(family == .systemSmall ? .footnote.weight(.semibold) : .headline).lineLimit(family == .systemSmall ? 3 : 2)
                    if family != .systemSmall { Text(book.authors).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    if let p = book.progress {
                        ProgressView(value: min(max(p / 100, 0), 1))
                        Text("\(Int(p))%").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .widgetURL(appURL)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "book").font(.title2)
                Text("Nothing in progress").font(.footnote).multilineTextAlignment(.center)
            }.foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var cover: some View {
        Group {
            if let image = entry.cover { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Color.secondary.opacity(0.2); Image(systemName: "book.closed").foregroundStyle(.secondary) } }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ReadingStatsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reading streak").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Text("\(s?.streak ?? 0) day\((s?.streak ?? 0) == 1 ? "" : "s")").font(.title3.weight(.semibold))
                if family != .systemSmall, let longest = s?.longestStreak, longest > 0 { Text("Longest: \(longest)").font(.caption2).foregroundStyle(.secondary) }
            }
            if family != .systemSmall || (s?.goalTotal ?? 0) > 0 { goal }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(appURL)
    }

    @ViewBuilder private var goal: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 4) {
            Text("\(s?.goalYear ?? 0) goal").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            if let total = s?.goalTotal, total > 0 {
                Text("\(s?.goalDone ?? 0) / \(total)").font(.title3.weight(.semibold))
                ProgressView(value: min(Double(s?.goalDone ?? 0) / Double(total), 1))
            } else {
                Text("\(s?.goalDone ?? 0) read").font(.title3.weight(.semibold))
            }
        }
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.kind.continueReading, provider: SnapshotProvider()) { entry in
            ContinueReadingView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Continue reading")
        .description("The book you're reading, with your progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ReadingStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.kind.stats, provider: SnapshotProvider()) { entry in
            ReadingStatsView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Reading stats")
        .description("Your reading streak and yearly goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CompanionWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ContinueReadingWidget()
        ReadingStatsWidget()
    }
}
