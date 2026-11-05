import SwiftUI

// MARK: Rarity styling

private func rarityColors(_ rarity: String) -> (Color, Color) {
    switch rarity {
    case "rare": return (Color(red: 0.45, green: 0.68, blue: 0.95), Color(red: 0.18, green: 0.35, blue: 0.65))
    case "epic": return (Color(red: 0.70, green: 0.55, blue: 0.95), Color(red: 0.38, green: 0.25, blue: 0.70))
    case "legendary": return (Color(red: 0.98, green: 0.84, blue: 0.40), Color(red: 0.72, green: 0.52, blue: 0.10))
    default: return (Color(white: 0.82), Color(white: 0.52))
    }
}

private func rarityLabel(_ r: String) -> String { r.capitalized }

/// Maps the server's icon names (Lucide-style) to SF Symbols; anything unknown becomes a rosette.
private func symbol(_ name: String) -> String {
    let map: [String: String] = [
        "flame": "flame.fill", "calendar": "calendar", "calendar-check": "calendar.badge.checkmark", "compass": "safari", "globe": "globe",
        "book-open": "book", "book": "book.closed", "book-marked": "book.closed", "clock": "clock", "timer": "timer", "gauge": "gauge.with.dots.needle.67percent",
        "moon": "moon.stars", "moon-star": "moon.stars", "sunrise": "sunrise", "sun": "sun.max", "fast-forward": "forward.fill", "rabbit": "hare",
        "heart": "heart.fill", "play": "play.fill", "library": "books.vertical", "pen": "pencil", "pencil": "pencil", "pen-line": "pencil.line",
        "file-text": "doc.text", "bookmark": "bookmark.fill", "hammer": "hammer", "star": "star.fill", "medal": "medal", "palette": "paintpalette",
        "trophy": "trophy.fill", "repeat": "repeat", "shield": "shield.fill", "activity": "waveform.path.ecg", "award": "rosette", "smartphone": "iphone",
        "atom": "atom", "arrow-left-right": "arrow.left.arrow.right", "sparkles": "sparkles", "hourglass": "hourglass", "coffee": "cup.and.saucer.fill",
        "list-ordered": "list.number", "arrow-up-down": "arrow.up.arrow.down", "minimize-2": "arrow.down.right.and.arrow.up.left", "layers": "square.stack.3d.up",
        "refresh-cw": "arrow.triangle.2.circlepath", "target": "scope", "zap": "bolt.fill", "ellipsis": "ellipsis",
    ]
    return map[name.lowercased()] ?? "rosette"
}

// MARK: Grouping

/// One badge on screen: a single achievement, or a set of tiers shown as its current tier.
private struct Badge: Identifiable {
    var id: String
    var name: String
    var icon: String
    var rarity: String
    var earned: Bool
    var secret: Bool
    var caption: String
    var fraction: Double          // progress toward the next tier, 0...1
    var next: AchievementItem?    // the next tier still to earn
    var earnedTier: Int?
    var hasTiers: Bool
}

private func dateText(_ iso: String?) -> String? {
    guard let d = parseDate(iso) else { return nil }
    let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
}

private func parseDate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = a.date(from: iso) { return d }
    return ISO8601DateFormatter().date(from: iso) ?? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(iso.prefix(10))) }()
}

private func num(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "" }

private func badges(_ items: [AchievementItem]) -> [Badge] {
    var order: [String] = []
    var groups: [String: [AchievementItem]] = [:]
    for it in items.sorted(by: { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }) {
        let k = it.groupKey ?? it.key
        if groups[k] == nil { order.append(k) }
        groups[k, default: []].append(it)
    }
    return order.map { k in
        let tiers = groups[k]!.sorted { ($0.tier ?? 0) < ($1.tier ?? 0) }
        let earned = tiers.filter(\.earned)
        let top = earned.last
        let next = tiers.first { !$0.earned }
        let shown = top ?? tiers[0]
        let hasTiers = tiers.count > 1
        let secret = top == nil && tiers.allSatisfy(\.hidden)
        var caption = "Not started"
        var fraction = 0.0
        if let n = next, let t = n.threshold, t > 0, let p = n.currentProgress { fraction = min(max(p / t, 0), 1) }
        if secret { caption = "Keep reading" }
        else if hasTiers {
            var parts: [String] = []
            if let t = top?.tier { parts.append("Tier \(t)") }
            if let n = next, let t = n.threshold, let p = n.currentProgress, p > 0 || top != nil { parts.append("\(num(p)) / \(num(t))") }
            if !parts.isEmpty { caption = parts.joined(separator: " · ") }
        } else if let t = tiers.first {
            if t.earned { caption = dateText(t.awardedAt) ?? "Earned" }
            else if let th = t.threshold, let p = t.currentProgress, p > 0 { caption = "\(num(p)) / \(num(th))" }
        }
        return Badge(id: k, name: secret ? "Secret achievement" : shown.name, icon: shown.iconName, rarity: shown.rarity, earned: top != nil, secret: secret,
                     caption: caption, fraction: fraction, next: next, earnedTier: top?.tier, hasTiers: hasTiers)
    }
}

// MARK: Medal

private struct Medal: View {
    let icon: String
    let rarity: String
    let earned: Bool
    var secret = false
    var fraction = 0.0
    var size: CGFloat = 72

    var body: some View {
        let (light, dark) = rarityColors(rarity)
        ZStack {
            if earned {
                Circle().fill(LinearGradient(colors: [light, dark], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().stroke(.white.opacity(0.45), lineWidth: 2).padding(size * 0.06)
                Circle().fill(.black.opacity(0.12)).padding(size * 0.2)
                Image(systemName: symbol(icon)).font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(.white)
            } else {
                Circle().fill(Color.secondary.opacity(0.18))
                Circle().stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 3])).padding(size * 0.05)
                Image(systemName: secret ? "questionmark" : symbol(icon)).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(.secondary.opacity(0.7))
                if fraction > 0 {
                    Circle().trim(from: 0, to: fraction).stroke(light, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).padding(1)
                }
            }
        }
        .frame(width: size, height: size).shadow(color: earned ? dark.opacity(0.4) : .clear, radius: 5, y: 3)
    }
}

// MARK: Screen

struct AchievementsView: View {
    @EnvironmentObject var api: ServerAPI
    @EnvironmentObject var session: Session
    @State private var catalogue: AchievementCatalogue?
    @State private var error: String?
    @State private var loading = false
    @State private var showAll = false

    var body: some View {
        ScrollView {
            if let c = catalogue {
                LazyVStack(spacing: 16) {
                    LatestUnlock(items: c.categories.flatMap(\.achievements))
                    Summary(c: c)
                    Closest(c: c, showAll: $showAll)
                    ForEach(c.categories, id: \.key) { CategoryCard(category: $0) }
                }.padding(.horizontal).padding(.bottom)
            }
        }
        .refreshable { await load() }
        .overlay {
            if loading && catalogue == nil { ProgressView() }
            else if catalogue == nil { Text(error ?? "No achievements yet").foregroundStyle(.secondary).padding() }
        }
        .task { await load() }
        .sheet(isPresented: $showAll) { if let c = catalogue { AllClosestSheet(c: c) } }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { catalogue = try await api.achievements() }
        catch is AuthError { session.clearTokens() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

private let cardBackground = Color.secondary.opacity(0.12)

private struct LatestUnlock: View {
    let items: [AchievementItem]
    var body: some View {
        let earned = items.filter { $0.earned && parseDate($0.awardedAt) != nil }.sorted { parseDate($0.awardedAt)! > parseDate($1.awardedAt)! }
        let recent = Array(earned.prefix(7))
        let cal = Calendar.current
        let thisMonth = earned.filter { cal.isDate(parseDate($0.awardedAt)!, equalTo: Date(), toGranularity: .month) }.count
        if !recent.isEmpty {
            VStack(spacing: 6) {
                HStack {
                    Text("LATEST UNLOCK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(thisMonth) in \(monthName)").font(.subheadline).foregroundStyle(.secondary)
                }
                TabView {
                    ForEach(recent) { a in
                        VStack(spacing: 8) {
                            Medal(icon: a.iconName, rarity: a.rarity, earned: true, size: 110)
                            Text(a.name).font(.title2.weight(.bold))
                            HStack(spacing: 8) {
                                Text(rarityLabel(a.rarity)).font(.footnote.weight(.semibold)).foregroundStyle(rarityColors(a.rarity).0)
                                    .padding(.horizontal, 10).padding(.vertical, 3).overlay(Capsule().stroke(rarityColors(a.rarity).0.opacity(0.6)))
                                Text("\(a.category.capitalized) · \(dateText(a.awardedAt) ?? "")").foregroundStyle(.secondary)
                            }
                            Text(a.description).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary).lineLimit(3)
                        }.padding(.horizontal, 6)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .always)).frame(height: 270)
            }
            .padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private var monthName: String { let f = DateFormatter(); f.dateFormat = "LLLL"; return f.string(from: Date()).capitalized }
}

private struct Summary: View {
    let c: AchievementCatalogue
    var body: some View {
        let all = c.categories.flatMap(\.achievements)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading) { Text("\(c.totalEarned)").font(.system(size: 40, weight: .bold)); Text("of \(c.totalAvailable) tiers").font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
            Spacer(minLength: 4)
            ForEach(["common", "rare", "epic", "legendary"], id: \.self) { r in
                let of = all.filter { $0.rarity == r }
                VStack(spacing: 4) {
                    Medal(icon: "", rarity: r, earned: true, size: 30)
                    Text("\(of.filter(\.earned).count)/\(of.count)").font(.subheadline.weight(.semibold))
                    Text(rarityLabel(r)).font(.caption).foregroundStyle(rarityColors(r).0).lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The next tiers still to earn, closest first.
private func closest(_ c: AchievementCatalogue) -> [(item: AchievementItem, fraction: Double)] {
    c.categories.flatMap { badges($0.achievements) }
        .compactMap { b -> (AchievementItem, Double)? in
            guard let n = b.next, !n.hidden, let t = n.threshold, t > 0, let p = n.currentProgress, p > 0 else { return nil }
            return (n, min(p / t, 1))
        }
        .sorted { $0.1 > $1.1 }
        .map { (item: $0.0, fraction: $0.1) }
}

private struct Closest: View {
    let c: AchievementCatalogue
    @Binding var showAll: Bool
    var body: some View {
        let list = closest(c)
        if !list.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text("Closest to unlocking").font(.title3.weight(.bold))
                    Spacer()
                    Button { showAll = true } label: { Text("All \(list.count) ›").foregroundStyle(.tint) }
                }
                ForEach(list.prefix(3), id: \.item.key) { entry in
                    let a = entry.item
                    HStack(alignment: .top, spacing: 14) {
                        Medal(icon: a.iconName, rarity: a.rarity, earned: false, fraction: entry.fraction, size: 66)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rarityLabel(a.rarity)).font(.caption.weight(.semibold)).foregroundStyle(rarityColors(a.rarity).0)
                                .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(rarityColors(a.rarity).0.opacity(0.6)))
                            Text(a.name).font(.headline)
                            Text(a.description).font(.subheadline).foregroundStyle(.secondary)
                            if let t = a.threshold, let p = a.currentProgress {
                                HStack(alignment: .firstTextBaseline, spacing: 4) { Text(num(max(t - p, 0))).font(.title2.weight(.bold)); Text("to go").foregroundStyle(.secondary) }
                                HStack {
                                    ProgressView(value: entry.fraction).tint(rarityColors(a.rarity).0)
                                    Text("\(num(p)) / \(num(t))").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

private struct AllClosestSheet: View {
    let c: AchievementCatalogue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(closest(c), id: \.item.key) { entry in
                let a = entry.item
                HStack(spacing: 12) {
                    Medal(icon: a.iconName, rarity: a.rarity, earned: false, fraction: entry.fraction, size: 40)
                    VStack(alignment: .leading) {
                        Text(a.name).font(.headline)
                        Text("\(num(a.currentProgress ?? 0)) / \(num(a.threshold ?? 0))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int((entry.fraction * 100).rounded()))%").font(.title3.weight(.semibold))
                }
            }
            .listStyle(.plain).navigationTitle("Closest to unlocking").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct CategoryCard: View {
    let category: AchievementCategory
    private let icons = ["reading": "book.fill", "library": "books.vertical.fill", "exploration": "safari.fill", "dedication": "flame.fill", "devices": "iphone"]
    var body: some View {
        let list = badges(category.achievements)
        let pct = category.totalCount > 0 ? Double(category.earnedCount) / Double(category.totalCount) : 0
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icons[category.key] ?? "rosette").foregroundStyle(.tint).frame(width: 36, height: 36).background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                Text(category.label).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(category.earnedCount) / \(category.totalCount)").font(.footnote.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(Color.secondary.opacity(0.15), in: Capsule())
                Spacer()
                Text("\(Int((pct * 100).rounded()))%").foregroundStyle(.secondary)
                ProgressView(value: pct).frame(width: 44)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), spacing: 22) {
                ForEach(list) { b in
                    VStack(spacing: 6) {
                        Medal(icon: b.icon, rarity: b.rarity, earned: b.earned, secret: b.secret, fraction: b.fraction, size: 72)
                        Text(b.name).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
                        Text(b.caption).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}
