import Foundation
import Darwin

public enum SystemBootTime {
    public static func timestamp() -> TimeInterval {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride

        if sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 {
            return TimeInterval(bootTime.tv_sec) + (TimeInterval(bootTime.tv_usec) / 1_000_000)
        }

        return fallbackTimestamp()
    }

    static func fallbackTimestamp(
        now: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> TimeInterval {
        now.timeIntervalSince1970 - systemUptime
    }
}
