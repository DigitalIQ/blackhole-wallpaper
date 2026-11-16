import Foundation
import Metal

enum SelfTestMemory {
    static func run() -> Int32 {
        var failures = 0
        for preset in Preset.factory {
            autoreleasepool {
                let r = Renderer(look: preset.look, layout: ScreenLayout(holeX: 0.5, holeY: 0.5, topBar: 24, bottomBar: 60))
                r.setTime(20)
                func pixels() -> Data? {
                    autoreleasepool {
                        guard let image = Snapshot.render(r, width: 1280, height: 720),
                              let data = image.dataProvider?.data else { return nil }
                        return data as Data
                    }
                }
                guard let before = pixels() else { failures += 1; return }
                let active = GPU.shared.device.currentAllocatedSize
                // Speicherdruck während des Betriebs darf aktive Ressourcen nicht beschädigen.
                GPU.shared.releaseCachedResources()
                BodyGPU.shared.releaseCachedResources()
                let pressure = pixels()
                r.releaseIdleResources()
                GPU.shared.releaseCachedResources()
                BodyGPU.shared.releaseCachedResources()
                let idle = GPU.shared.device.currentAllocatedSize
                let resumed = pixels()
                let same = before == pressure && before == resumed
                let freed = idle < active
                print("\(same && freed ? "ok" : "FEHLER") \(preset.id): GPU aktiv=\(active / 1024 / 1024) MiB, Pause=\(idle / 1024 / 1024) MiB, Bild identisch=\(same)")
                if !same || !freed { failures += 1 }
                // Wiederholte Freigabe muss ebenfalls sicher sein.
                r.releaseIdleResources(); r.releaseIdleResources()
                GPU.shared.releaseCachedResources(); BodyGPU.shared.releaseCachedResources()
            }
        }
        return failures == 0 ? 0 : 1
    }
}
