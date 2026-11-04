import Foundation
import UIKit
import WidgetKit

/// Keeps the Home Screen widgets up to date with what the app last learned from the server.
enum WidgetSync {
    static func publish(api: ServerAPI, current: BookCard?, widgets: WidgetData) async {
        var snap = WidgetSnapshot()
        if let b = current {
            snap.book = .init(id: b.id, title: b.title ?? "Untitled", authors: b.authors.joined(separator: ", "), progress: b.readingProgress)
        }
        snap.streak = (widgets["reading-streak"]?["currentStreak"] as? NSNumber)?.intValue ?? 0
        snap.longestStreak = (widgets["reading-streak"]?["longestStreak"] as? NSNumber)?.intValue ?? 0
        snap.goalDone = (widgets["reading-goal"]?["completedBooks"] as? NSNumber)?.intValue ?? 0
        snap.goalTotal = (widgets["reading-goal"]?["goalBooks"] as? NSNumber)?.intValue ?? 0
        snap.goalYear = (widgets["reading-goal"]?["year"] as? NSNumber)?.intValue ?? Calendar.current.component(.year, from: Date())

        var cover: Data?
        if let b = current, b.hasCover, let image = await api.cover(bookId: b.id) { cover = scaled(image, maxHeight: 360).jpegData(compressionQuality: 0.8) }
        WidgetStore.save(snap, cover: cover)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Updates just the reading progress, e.g. when the reader is closed.
    static func updateProgress(bookId: Int, percent: Double) {
        guard var snap = WidgetStore.load(), snap.book?.id == bookId else { return }
        snap.book?.progress = percent
        snap.updatedAt = Date()
        WidgetStore.save(snap, cover: WidgetStore.coverData())
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func scaled(_ image: UIImage, maxHeight: CGFloat) -> UIImage {
        guard image.size.height > maxHeight else { return image }
        let size = CGSize(width: image.size.width * maxHeight / image.size.height, height: maxHeight)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
