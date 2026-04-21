import Foundation
import Dispatch

enum PerfClock {
    struct Instant {
        fileprivate let uptimeNanoseconds: UInt64
        fileprivate let continuousInstant: Any?
    }

    static func now() -> Instant {
        let uptime = DispatchTime.now().uptimeNanoseconds
        if #available(macOS 13.0, *) {
            let clock = ContinuousClock()
            return Instant(uptimeNanoseconds: uptime, continuousInstant: clock.now)
        }
        return Instant(uptimeNanoseconds: uptime, continuousInstant: nil)
    }

    static func elapsedMs(since start: Instant) -> Int {
        if #available(macOS 13.0, *),
           let continuousStart = start.continuousInstant as? ContinuousClock.Instant {
            let clock = ContinuousClock()
            let components = continuousStart.duration(to: clock.now).components
            let secondsMs = components.seconds * 1000
            let attosecondsMs = components.attoseconds / 1_000_000_000_000_000
            let totalMs = secondsMs + attosecondsMs
            if totalMs > Int64(Int.max) { return Int.max }
            if totalMs < Int64(Int.min) { return Int.min }
            return Int(totalMs)
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let delta = now >= start.uptimeNanoseconds ? now - start.uptimeNanoseconds : 0
        return Int(delta / 1_000_000)
    }
}
