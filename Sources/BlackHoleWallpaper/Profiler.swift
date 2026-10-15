import Foundation
import Metal

/// GPU time per pass from Metal's stage-boundary timestamps, for --bench-passes. Off (nil) otherwise,
/// then the encoder helpers below cost nothing.
final class PassProfiler {
    static var shared: PassProfiler?

    private let buffer: MTLCounterSampleBuffer
    private let capacity = 1024
    private var entries: [(name: String, first: Int, count: Int)] = []
    private var next = 0
    /// Nanoseconds per counter tick.
    private let nsPerTick: Double

    init?(device: MTLDevice) {
        guard device.supportsCounterSampling(.atStageBoundary),
              let set = device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) else { return nil }
        let d = MTLCounterSampleBufferDescriptor()
        d.counterSet = set
        d.sampleCount = capacity
        d.storageMode = .shared
        guard let b = try? device.makeCounterSampleBuffer(descriptor: d) else { return nil }
        buffer = b
        // The counters count nanoseconds on Apple GPUs (checked against the command buffer's own GPU time).
        nsPerTick = 1
    }

    func begin() { entries = []; next = 0 }

    func tag(_ rp: MTLRenderPassDescriptor, _ name: String) {
        guard next + 4 <= capacity else { return }
        let a = rp.sampleBufferAttachments[0]!
        a.sampleBuffer = buffer
        a.startOfVertexSampleIndex = next
        a.endOfVertexSampleIndex = next + 1
        a.startOfFragmentSampleIndex = next + 2
        a.endOfFragmentSampleIndex = next + 3
        entries.append((name, next, 4))
        next += 4
    }

    func compute(_ name: String) -> MTLComputePassDescriptor {
        let d = MTLComputePassDescriptor()
        guard next + 2 <= capacity else { return d }
        let a = d.sampleBufferAttachments[0]!
        a.sampleBuffer = buffer
        a.startOfEncoderSampleIndex = next
        a.endOfEncoderSampleIndex = next + 1
        entries.append((name, next, 2))
        next += 2
        return d
    }

    func blit(_ name: String) -> MTLBlitPassDescriptor {
        let d = MTLBlitPassDescriptor()
        guard next + 2 <= capacity else { return d }
        let a = d.sampleBufferAttachments[0]!
        a.sampleBuffer = buffer
        a.startOfEncoderSampleIndex = next
        a.endOfEncoderSampleIndex = next + 1
        entries.append((name, next, 2))
        next += 2
        return d
    }

    /// After the command buffer completed: milliseconds per pass name (summed when a name repeats).
    func collect() -> [String: Double] {
        guard next > 0, let data = try? buffer.resolveCounterRange(0..<next) else { return [:] }
        var out: [String: Double] = [:]
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let ts = raw.bindMemory(to: MTLCounterResultTimestamp.self)
            for e in entries {
                let v = (0..<e.count).map { ts[e.first + $0].timestamp }
                    .filter { $0 != 0 && $0 != UInt64(MTLCounterErrorValue) }
                guard let lo = v.min(), let hi = v.max() else { continue }
                out[e.name, default: 0] += Double(hi - lo) * nsPerTick / 1e6
            }
        }
        return out
    }
}

extension MTLCommandBuffer {
    func renderEncoder(_ rp: MTLRenderPassDescriptor, _ name: String) -> MTLRenderCommandEncoder? {
        PassProfiler.shared?.tag(rp, name)
        return makeRenderCommandEncoder(descriptor: rp)
    }

    func computeEncoder(_ name: String) -> MTLComputeCommandEncoder? {
        if let p = PassProfiler.shared { return makeComputeCommandEncoder(descriptor: p.compute(name)) }
        return makeComputeCommandEncoder()
    }

    func blitEncoder(_ name: String) -> MTLBlitCommandEncoder? {
        if let p = PassProfiler.shared { return makeBlitCommandEncoder(descriptor: p.blit(name)) }
        return makeBlitCommandEncoder()
    }
}
