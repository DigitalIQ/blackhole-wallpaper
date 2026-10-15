import Foundation
import IOKit.ps

extension Notification.Name {
    static let powerSourceChanged = Notification.Name("BlackHolePowerSourceChanged")
}

enum Power {
    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    /// Posts .powerSourceChanged when the Mac switches between adapter and battery.
    static func startWatching() {
        let src = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .powerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue()
        if let src { CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode) }
    }
}
