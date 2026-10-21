import Foundation

/// Sleep timer with an equal-power fade-out over its final stretch.
struct SleepTimer: Sendable, Equatable {
    static let presets: [TimeInterval] = [15, 30, 45, 60, 120, 240, 480].map { $0 * 60 }
    /// Fade covers the last quarter of the timer, capped at five minutes.
    static func defaultFade(for duration: TimeInterval) -> TimeInterval { min(300, duration * 0.25) }

    let start: Date
    let duration: TimeInterval
    let fade: TimeInterval

    init(duration: TimeInterval, start: Date = Date(), fade: TimeInterval? = nil) {
        self.start = start
        self.duration = max(0, duration)
        self.fade = min(max(0, fade ?? Self.defaultFade(for: duration)), self.duration)
    }

    var end: Date { start.addingTimeInterval(duration) }
    var fadeStart: Date { end.addingTimeInterval(-fade) }

    func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
    func isFinished(at now: Date) -> Bool { now >= end }

    /// 1 until the fade begins, then a cosine (equal-power) ramp to 0 at the end.
    func gain(at now: Date) -> Float {
        if now >= end { return 0 }
        if now <= fadeStart || fade <= 0 { return 1 }
        let progress = now.timeIntervalSince(fadeStart) / fade
        return Float(cos(progress * .pi / 2))
    }

    static func label(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        return h == 1 ? "1 hour" : "\(h) hours"
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// Pro: brings the sound back in slowly at a chosen wake time.
struct WakeFade: Sendable, Equatable {
    static let defaultDuration: TimeInterval = 10 * 60

    let at: Date
    let duration: TimeInterval

    init(at: Date, duration: TimeInterval = Self.defaultDuration) {
        self.at = at
        self.duration = max(1, duration)
    }

    /// The next time `hour:minute` occurs strictly after `now`.
    static func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.hour = hour; c.minute = minute; c.second = 0
        return calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }

    /// 0 before the wake time, then a sine ramp up to 1 over `duration`.
    func gain(at now: Date) -> Float {
        if now <= at { return 0 }
        let progress = min(1, now.timeIntervalSince(at) / duration)
        return Float(sin(progress * .pi / 2))
    }

    func isComplete(at now: Date) -> Bool { now >= at.addingTimeInterval(duration) }
}
