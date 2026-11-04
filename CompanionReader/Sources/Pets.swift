import SwiftUI
import UIKit

/// The reading companions from the BookOrbit KOReader plugin. Sprite art is 64x64 pixel art with six
/// poses per character, shipped as Pets/<name>.json.
enum Pets {
    static let names = ["cat", "dog", "rabbit", "owl", "penguin", "robot", "vampire", "dragon",
                        "ghost", "mimic", "mummy", "witch", "skeleton", "candle", "alien", "claude", "dino"]
    private static var cache: [String: [String: UIImage]] = [:]

    static func sprites(_ pet: String) -> [String: UIImage] {
        if let c = cache[pet] { return c }
        guard let url = Bundle.main.url(forResource: pet, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let palette = root["palette"] as? [String: String],
              let poses = root["poses"] as? [String: [String]] else { return [:] }
        var colors: [Character: UInt32] = [:]
        for (k, v) in palette { if let c = k.first, let n = UInt32(v, radix: 16) { colors[c] = 0xFF00_0000 | n } }
        var out: [String: UIImage] = [:]
        for (pose, rows) in poses {
            var pixels = [UInt32](repeating: 0, count: 64 * 64)
            for (y, row) in rows.prefix(64).enumerated() {
                for (x, ch) in row.prefix(64).enumerated() {
                    if let argb = colors[ch] {
                        // CGImage wants premultiplied RGBA bytes; opaque pixels need only a channel swap.
                        let r = (argb >> 16) & 255, g = (argb >> 8) & 255, b = argb & 255
                        pixels[y * 64 + x] = 0xFF00_0000 | (b << 16) | (g << 8) | r
                    }
                }
            }
            let provider = CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 4) as CFData)!
            if let cg = CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
                out[pose] = UIImage(cgImage: cg)
            }
        }
        cache[pet] = out
        return out
    }

    private static let milestones: Set<Int> = [7, 30, 50, 100, 200, 365]

    /// Same rules as the plugin: one pose for the current situation.
    static func pose(hasBook: Bool, streak: Int, longest: Int, todayMin: Int, finishedToday: Bool, hour: Int) -> String {
        if !hasBook && streak == 0 { return "wait" }
        if todayMin <= 0 { return "sleep" }
        if finishedToday { return "ribbon" }
        if milestones.contains(streak) || (streak > 1 && streak >= longest) { return "party" }
        if hour >= 22 || hour < 5 { return "yawn" }
        return "read"
    }

    static func lines(_ pose: String, streak: Int, longest: Int, todayMin: Int) -> (String, String) {
        switch pose {
        case "read": return ("Reading with you", "\(duration(todayMin)) today")
        case "sleep": return ("Fast asleep", "Wakes up when you read")
        case "party": return ("\(streak) \(streak == 1 ? "day" : "days") in a row!", streak >= longest ? "A new best" : "Your best is \(longest)")
        case "ribbon": return ("Book finished!", "")
        case "yawn": return ("Past bedtime", "\(duration(todayMin)) read today")
        default: return ("Ready when you are", "Open a book to start")
        }
    }

    private static func duration(_ min: Int) -> String { min >= 60 ? "\(min / 60) h \(min % 60) min" : "\(min) min" }
}

struct PetCard: View {
    let data: [String: [String: Any]]
    let hasBook: Bool
    let size: String
    @AppStorage("pet") private var pet = "cat"
    @State private var picking = false

    var body: some View {
        let streak = (data["reading-streak"]?["currentStreak"] as? NSNumber)?.intValue ?? 0
        let longest = (data["reading-streak"]?["longestStreak"] as? NSNumber)?.intValue ?? 0
        let todayMin = Self.todayMinutes(data)
        let pose = Pets.pose(hasBook: hasBook, streak: streak, longest: longest, todayMin: todayMin,
                             finishedToday: Self.finishedToday(data), hour: Calendar.current.component(.hour, from: Date()))
        let (line1, line2) = Pets.lines(pose, streak: streak, longest: longest, todayMin: todayMin)
        let dim: CGFloat = size == "s" ? 72 : size == "l" ? 152 : 104

        Button { picking = true } label: {
            Group {
                if size == "s" {
                    VStack { sprite(pose, dim); Text(line1).font(.subheadline.weight(.medium)).multilineTextAlignment(.center) }
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 16) {
                        sprite(pose, dim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line1).font(.headline)
                            if !line2.isEmpty { Text(line2).font(.subheadline).foregroundStyle(.secondary) }
                            Text("Tap to change companion").font(.caption2).foregroundStyle(.tint)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                        ForEach(Pets.names, id: \.self) { name in
                            Button { pet = name; picking = false; WidgetSync.updatePet(name: name) } label: {
                                VStack {
                                    if let img = Pets.sprites(name)["read"] { Image(uiImage: img).interpolation(.none).resizable().frame(width: 72, height: 72) }
                                    Text(name.capitalized).font(.caption)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                }
                .navigationTitle("Choose a companion").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { picking = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private func sprite(_ pose: String, _ dim: CGFloat) -> some View {
        if let img = Pets.sprites(pet)[pose] { Image(uiImage: img).interpolation(.none).resizable().frame(width: dim, height: dim) }
    }

    static func todayMinutes(_ data: [String: [String: Any]]) -> Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let today = f.string(from: Date())
        let days = data["reading-rhythm"]?["days"] as? [[String: Any]] ?? []
        guard let d = days.last(where: { ($0["date"] as? String)?.hasPrefix(today) == true }),
              let s = (d["readingSeconds"] as? NSNumber)?.doubleValue else { return 0 }
        return Int(s / 60)
    }

    /// A book counts as finished today when the year's completed count has grown since the day began.
    static func finishedToday(_ data: [String: [String: Any]]) -> Bool {
        guard let completed = (data["reading-goal"]?["completedBooks"] as? NSNumber)?.intValue else { return false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let today = f.string(from: Date())
        let d = UserDefaults.standard
        if d.string(forKey: "base_date") != today { d.set(today, forKey: "base_date"); d.set(completed, forKey: "base_completed") }
        return completed > d.integer(forKey: "base_completed")
    }
}
