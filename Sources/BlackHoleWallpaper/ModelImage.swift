import CoreGraphics
import Foundation
import ImageIO

/// Pictures of model files: decoded with ImageIO into RGBA8, at most `ModelTexture.maxSide` on the longer side.
enum ModelImage {
    static func texture(data: Data, maxSide: Int = ModelTexture.maxSide) -> ModelTexture? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts), CGImageSourceGetCount(src) > 0 else { return nil }
        let w = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let pw = (w?[kCGImagePropertyPixelWidth] as? Int) ?? 0, ph = (w?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        // Large pictures are scaled while decoding; small ones are read as they are.
        let img: CGImage?
        if max(pw, ph) > maxSide {
            let t = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxSide,
                     kCGImageSourceCreateThumbnailWithTransform: false] as CFDictionary
            img = CGImageSourceCreateThumbnailAtIndex(src, 0, t)
        } else {
            img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        return img.flatMap { texture($0, maxSide: maxSide) }
    }

    static func texture(url: URL) -> ModelTexture? { (try? Data(contentsOf: url)).flatMap { texture(data: $0) } }

    /// Draws a picture into RGBA8 with straight alpha and no colour conversion: the bytes stay as stored,
    /// the renderer decides what is sRGB.
    static func texture(_ img: CGImage, maxSide: Int = ModelTexture.maxSide) -> ModelTexture? {
        var w = img.width, h = img.height
        guard w > 0, h > 0 else { return nil }
        let s = min(1, Double(maxSide) / Double(max(w, h)))
        w = max(Int((Double(w) * s).rounded()), 1); h = max(Int((Double(h) * s).rounded()), 1)
        var bytes = Data(count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: img.colorSpace?.model == .rgb ? img.colorSpace! : CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // CoreGraphics only draws premultiplied; undo it so masks and colours stay as in the file.
        bytes.withUnsafeMutableBytes { buf in
            let p = buf.bindMemory(to: UInt8.self)
            for i in Swift.stride(from: 0, to: w * h * 4, by: 4) {
                let a = Int(p[i + 3])
                if a > 0 && a < 255 {
                    for c in 0..<3 { p[i + c] = UInt8(min(255, (Int(p[i + c]) * 255 + a / 2) / a)) }
                }
            }
        }
        return ModelTexture(width: w, height: h, rgba: bytes)
    }
}
