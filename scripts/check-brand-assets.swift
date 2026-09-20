#!/usr/bin/env swift
import AppKit
import Foundation

let stack = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/UI/Assets.xcassets/App Icon & Top Shelf Image.brandassets/App Icon.imagestack")

func pixel(_ layer: String, x: Int, y: Int) -> NSColor {
    let path = stack.appendingPathComponent("\(layer).imagestacklayer/Content.imageset/art_1x.png")
    let image = NSBitmapImageRep(data: try! Data(contentsOf: path))!
    return image.colorAt(x: x, y: y)!
}

let back = pixel("Back", x: 200, y: 120)
precondition(abs(back.redComponent - 245.0 / 255) < 0.01)
precondition(abs(back.greenComponent - 166.0 / 255) < 0.01)
precondition(abs(back.blueComponent - 35.0 / 255) < 0.01)

// The app icon is one taco over a solid brand field. The middle layer and
// the space at either side of the taco must be completely transparent.
precondition(pixel("Middle", x: 200, y: 120).alphaComponent < 0.01)
precondition(pixel("Front", x: 25, y: 120).alphaComponent < 0.01)
precondition(pixel("Front", x: 375, y: 120).alphaComponent < 0.01)
precondition(pixel("Front", x: 200, y: 120).alphaComponent > 0.5)
print("Brand icon layers OK")
