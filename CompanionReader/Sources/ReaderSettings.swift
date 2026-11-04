import Foundation
import ReadiumNavigator

let defaultWordsPerMinute = 230.0

final class ReaderSettings: ObservableObject {
    private let d = UserDefaults.standard
    /// Multiplier of the publisher's size, 1.0 = 100%.
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    /// Multiplier of the default page margins.
    @Published var margins: Double { didSet { d.set(margins, forKey: "margins") } }
    @Published var justify: Bool { didSet { d.set(justify, forKey: "justify") } }
    @Published var dark: Bool { didSet { d.set(dark, forKey: "dark") } }

    /// Words per minute learned from the user's own reading; 0 until there is enough to go on.
    @Published var learnedPace: Double { didSet { d.set(learnedPace, forKey: "learnedPace") } }

    init() {
        learnedPace = d.double(forKey: "learnedPace")
        fontSize = d.object(forKey: "fontSize") as? Double ?? 1.0
        margins = d.object(forKey: "margins") as? Double ?? 1.0
        justify = d.bool(forKey: "justify")
        dark = d.bool(forKey: "dark")
    }

    func reset() { fontSize = 1; margins = 1; justify = false; learnedPace = 0 }

    var preferences: EPUBPreferences {
        EPUBPreferences(
            fontSize: fontSize,
            hyphens: justify ? true : nil,
            pageMargins: margins,
            publisherStyles: justify ? false : nil,
            textAlign: justify ? .justify : nil,
            theme: dark ? .dark : .light
        )
    }
}
