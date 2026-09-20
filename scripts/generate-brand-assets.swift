#!/usr/bin/env swift
// Rebuild the tvOS layered icon and static Top Shelf fallback from FiestaBoard's taco.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let artwork = root.appendingPathComponent("scripts/artwork/fiesta-icon.png")
let catalog = root.appendingPathComponent("Sources/UI/Assets.xcassets/App Icon & Top Shelf Image.brandassets")
guard let icon = NSImage(contentsOf: artwork) else { fatalError("Missing FiestaBoard source icon") }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func writeJSON(_ value: Any, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let info: [String: Any] = ["info": ["author": "xcode", "version": 1]]

enum Layer { case back, middle, front, complete }

func render(width: Int, height: Int, layer: Layer, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                        bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot draw asset") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let w = CGFloat(width), h = CGFloat(height)
    if layer == .back || layer == .complete {
        color(0xf5a623).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
    }
    if layer == .front || layer == .complete {
        let artSide = min(h * 0.88, w * 0.58)
        icon.draw(in: NSRect(x: (w - artSide) / 2, y: (h - artSide) / 2,
                             width: artSide, height: artSide),
                  from: .zero, operation: .sourceOver, fraction: 1)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url)
}

func imageSet(_ folder: URL, sizes: [(Int, Int, String)]) throws {
    var images: [[String: String]] = []
    for (width, height, scale) in sizes {
        let filename = "art_\(scale).png"
        try render(width: width, height: height, layer: .complete, to: folder.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "tv", "scale": scale])
    }
    try writeJSON(["images": images, "info": info["info"]!], to: folder.appendingPathComponent("Contents.json"))
}

func iconStack(_ name: String, sizes: [(Int, Int, String)]) throws {
    let stack = catalog.appendingPathComponent("\(name).imagestack")
    let layers = ["Front", "Middle", "Back"]
    try writeJSON(["layers": layers.map { ["filename": "\($0).imagestacklayer"] },
                   "info": info["info"]!], to: stack.appendingPathComponent("Contents.json"))
    for name in layers {
        let folder = stack.appendingPathComponent("\(name).imagestacklayer")
        try writeJSON(info, to: folder.appendingPathComponent("Contents.json"))
        let imageFolder = folder.appendingPathComponent("Content.imageset")
        let layer: Layer = name == "Back" ? .back : (name == "Middle" ? .middle : .front)
        var images: [[String: String]] = []
        for (width, height, scale) in sizes {
            let filename = "art_\(scale).png"
            try render(width: width, height: height, layer: layer,
                       to: imageFolder.appendingPathComponent(filename))
            images.append(["filename": filename, "idiom": "tv", "scale": scale])
        }
        try writeJSON(["images": images, "info": info["info"]!],
                      to: imageFolder.appendingPathComponent("Contents.json"))
    }
}

try iconStack("App Icon", sizes: [(400, 240, "1x"), (800, 480, "2x")])
try iconStack("App Icon - App Store", sizes: [(1280, 768, "1x")])
try imageSet(catalog.appendingPathComponent("Top Shelf Image.imageset"),
             sizes: [(1920, 720, "1x"), (3840, 1440, "2x")])
try imageSet(catalog.appendingPathComponent("Top Shelf Image Wide.imageset"),
             sizes: [(2320, 720, "1x"), (4640, 1440, "2x")])
try writeJSON(["assets": [
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"]
], "info": info["info"]!], to: catalog.appendingPathComponent("Contents.json"))
