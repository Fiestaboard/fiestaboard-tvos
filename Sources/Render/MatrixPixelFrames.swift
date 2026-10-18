import CoreGraphics
import Foundation

/// Animation textures stay at the device's native LED resolution, never the
/// TV's resolution. A marquee retains just two small color textures.
enum MatrixPixelFrames {
    static func colors(_ raster: MatrixRaster) -> CGImage? {
        image(words: raster.pixels.map(rgba), width: raster.width, height: raster.height)
    }

    static func shifted(_ old: [UInt32], _ new: [UInt32], width: Int, height: Int, step: Int) -> [UInt32] {
        let step = min(width, max(0, step))
        var output = old
        for row in 0..<height {
            let start = row * width
            output.replaceSubrange(start..<(start + width - step),
                                   with: old[(start + step)..<(start + width)])
            output.replaceSubrange((start + width - step)..<(start + width),
                                   with: new[start..<(start + step)])
        }
        return output
    }

    static func dissolve(width: Int, height: Int) -> [CGImage] {
        let count = width * height
        guard count > 0 else { return [] }
        var order = Array(0..<count)
        var random: UInt32 = 0x9e3779b9
        // Stable shuffle makes interrupted playback and recorded previews
        // reproducible without storing a separate random schedule.
        if count > 1 {
            for index in stride(from: count - 1, through: 1, by: -1) {
                random ^= random << 13
                random ^= random >> 17
                random ^= random << 5
                order.swapAt(index, Int(random) % (index + 1))
            }
        }
        let steps = min(32, count)
        var pixels = [UInt32](repeating: 0, count: count)
        var revealed = 0
        return (0...steps).compactMap { step in
            let end = step * count / steps
            for index in revealed..<end { pixels[order[index]] = 0xffffffff }
            revealed = end
            return image(words: pixels, width: width, height: height)
        }
    }

    private static func rgba(_ rgb: UInt32) -> UInt32 {
        // An unlit LED is transparent: the fixed physical surface supplies
        // its configured off color and receives no emitted-light halo.
        guard rgb != 0 else { return 0 }
        return 0xff000000 | ((rgb & 0xff) << 16) | (rgb & 0xff00) | ((rgb >> 16) & 0xff)
    }

    private static func image(words: [UInt32], width: Int, height: Int) -> CGImage? {
        let data = words.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                            .union(.byteOrder32Big),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
