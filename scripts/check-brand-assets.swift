#!/usr/bin/env swift
// Guards the tvOS brand assets. Run by CI and by generate-brand-assets.sh.
//
// The icon is one taco over a solid brand field: a flat amber Back layer, an
// empty Middle layer, and a Front layer carrying only the mark. The last
// check is the one that matters most — it fails if the art ever goes back to
// being a resampled photograph rather than flat colour.
import AppKit
import Foundation

let catalog = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/UI/Assets.xcassets/App Icon & Top Shelf Image.brandassets")

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

func layer(_ stack: String, _ name: String, scale: String = "1x") -> NSBitmapImageRep {
    let path = catalog
        .appendingPathComponent("\(stack).imagestack/\(name).imagestacklayer/Content.imageset/art_\(scale).png")
    guard let data = try? Data(contentsOf: path), let image = NSBitmapImageRep(data: data) else {
        fputs("Missing brand asset: \(path.path)\n", stderr)
        exit(1)
    }
    return image
}

func rgb(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let c = image.colorAt(x: x, y: y)!
    return (Int(c.redComponent * 255), Int(c.greenComponent * 255),
            Int(c.blueComponent * 255), Int(c.alphaComponent * 255))
}

for stack in ["App Icon", "App Icon - App Store"] {
    let back = layer(stack, "Back")
    let middle = layer(stack, "Middle")
    let front = layer(stack, "Front")
    let w = front.pixelsWide, h = front.pixelsHigh

    // Back: flat brand amber, corner to corner.
    for (x, y) in [(1, 1), (w - 2, 1), (w / 2, h / 2), (1, h - 2), (w - 2, h - 2)] {
        let c = rgb(back, x, y)
        check((c.r, c.g, c.b, c.a) == (0xf5, 0xa6, 0x23, 255),
              "\(stack) Back is not flat #f5a623 at (\(x), \(y)) — got \(c)")
    }

    // Middle: nothing. A third plane of art would only add parallax jitter.
    check(rgb(middle, w / 2, h / 2).a == 0, "\(stack) Middle layer is not empty")

    // Front: the mark, centred, clear of the edges tvOS crops and magnifies.
    check(rgb(front, w / 16, h / 2).a == 0, "\(stack) Front has art at the left edge")
    check(rgb(front, w - w / 16, h / 2).a == 0, "\(stack) Front has art at the right edge")
    check(rgb(front, w / 2, h / 2).a > 128, "\(stack) Front has no mark at its centre")

    // The mark is flat colour, so a scanline through it can only hit palette
    // entries. A resampled raster would smear across hundreds of shades.
    var shades: Set<Int> = []
    for x in 0..<w {
        let c = rgb(front, x, h / 2)
        if c.a > 128 { shades.insert(c.r << 16 | c.g << 8 | c.b) }
    }
    check(shades.count <= 8,
          "\(stack) Front is not flat colour: \(shades.count) shades across its middle row")
}

guard failures.isEmpty else {
    for failure in failures { fputs("BRAND ASSET CHECK FAILED: \(failure)\n", stderr) }
    exit(1)
}
print("Brand assets OK: flat amber field, empty middle layer, flat-colour mark.")
