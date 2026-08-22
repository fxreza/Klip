import SwiftUI

/// Live "3 minutes ago" label. Ticks once a second while visible.
struct RelativeTimestampView: View {
    let timestamp: Date
    /// Font role, so the row subtitle and the preview footer can size it
    /// differently while both track the user's font-scale setting.
    var role: KlipFontRole = .rowSubtitle
    /// Foreground colour — selected rows pass `Theme.onAccentSecondary`.
    var color: Color = .secondary

    @State private var currentDate = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(timeAgo(from: timestamp, relativeTo: currentDate))
            .font(.klip(role))
            .foregroundStyle(color)
            .lineLimit(1)
            .onReceive(timer) { input in
                currentDate = input
            }
    }

    private func timeAgo(from date: Date, relativeTo now: Date) -> String {
        let diff = now.timeIntervalSince(date)
        if diff < 1 {
            return "just now"
        } else if diff < 60 {
            let seconds = Int(diff)
            return "\(seconds) second\(seconds == 1 ? "" : "s") ago"
        } else if diff < 3600 {
            let minutes = Int(diff / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if diff < 86400 {
            let hours = diff / 3600
            let roundedHours = (hours * 2).rounded() / 2
            if roundedHours == 1.0 {
                return "1 hour ago"
            } else if roundedHours.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(roundedHours)) hours ago"
            } else {
                return "\(roundedHours) hours ago"
            }
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if diff < 2592000 {
            let weeks = Int(diff / 604800)
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if diff < 31536000 {
            let months = Int(diff / 2592000)
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else {
            let years = Int(diff / 31536000)
            return "\(years) year\(years == 1 ? "" : "s") ago"
        }
    }
}
