// Rebuilds the tvOS layered app icon and the static Top Shelf art from
// `TacoMark`, the same vector the app draws its Top Shelf posters with.
//
// Run it through scripts/generate-brand-assets.sh, which compiles this file
// together with Sources/Render/TacoMark.swift.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent(
    "Sources/UI/Assets.xcassets/App Icon & Top Shelf Image.brandassets")

let assetInfo: [String: Any] = ["author": "xcode", "version": 1]

func writeJSON(_ value: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: value,
                                          options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

/// Which slice of the artwork a file carries.
///
/// tvOS composites the layers with parallax, so the brand field and the
/// taco have to ship separately even though they are one picture.
enum Layer {
    case brandField
    case taco
    case complete
}

func render(width: Int, height: Int, layer: Layer, to url: URL) throws {
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }

    // TacoMark is authored y-down; a CGContext is y-up.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)

    let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

    if layer == .brandField || layer == .complete {
        context.setFillColor(TacoMark.Ink.brand)
        context.fill(canvas)
    }

    if layer == .taco || layer == .complete {
        // Leave a generous margin: tvOS crops the icon to a rounded rect and
        // magnifies it under the parallax, so art near an edge gets clipped.
        let markHeight = min(canvas.height * 0.70, canvas.width * 0.52 / TacoMark.aspect)
        let box = CGRect(x: canvas.midX - markHeight * TacoMark.aspect / 2,
                         y: canvas.midY - markHeight / 2,
                         width: markHeight * TacoMark.aspect, height: markHeight)
        for shape in TacoMark.shapes(in: box) {
            context.setFillColor(shape.fill)
            context.addPath(shape.path)
            context.fillPath()
        }
    }

    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func imageSet(_ folder: URL, sizes: [(Int, Int, String)]) throws {
    var images: [[String: String]] = []
    for (width, height, scale) in sizes {
        let filename = "art_\(scale).png"
        try render(width: width, height: height, layer: .complete,
                   to: folder.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "tv", "scale": scale])
    }
    try writeJSON(["images": images, "info": assetInfo],
                  to: folder.appendingPathComponent("Contents.json"))
}

/// The icon is one taco over a solid brand field. `Middle` stays empty: a
/// third plane of art would only add parallax jitter to a flat mark.
func iconStack(_ name: String, sizes: [(Int, Int, String)]) throws {
    let stack = catalog.appendingPathComponent("\(name).imagestack")
    let layers = ["Front", "Middle", "Back"]
    try writeJSON(["layers": layers.map { ["filename": "\($0).imagestacklayer"] },
                   "info": assetInfo],
                  to: stack.appendingPathComponent("Contents.json"))

    for layerName in layers {
        let folder = stack.appendingPathComponent("\(layerName).imagestacklayer")
        try writeJSON(["info": assetInfo], to: folder.appendingPathComponent("Contents.json"))

        let content = folder.appendingPathComponent("Content.imageset")
        let layer: Layer
        switch layerName {
        case "Back": layer = .brandField
        case "Front": layer = .taco
        default: layer = .complete  // Middle: nothing to draw.
        }

        var images: [[String: String]] = []
        for (width, height, scale) in sizes {
            let filename = "art_\(scale).png"
            if layerName == "Middle" {
                try renderEmpty(width: width, height: height,
                                to: content.appendingPathComponent(filename))
            } else {
                try render(width: width, height: height, layer: layer,
                           to: content.appendingPathComponent(filename))
            }
            images.append(["filename": filename, "idiom": "tv", "scale": scale])
        }
        try writeJSON(["images": images, "info": assetInfo],
                      to: content.appendingPathComponent("Contents.json"))
    }
}

func renderEmpty(width: Int, height: Int, to url: URL) throws {
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

try iconStack("App Icon", sizes: [(400, 240, "1x"), (800, 480, "2x")])
try iconStack("App Icon - App Store", sizes: [(1280, 768, "1x")])
try imageSet(catalog.appendingPathComponent("Top Shelf Image.imageset"),
             sizes: [(1920, 720, "1x"), (3840, 1440, "2x")])
try imageSet(catalog.appendingPathComponent("Top Shelf Image Wide.imageset"),
             sizes: [(2320, 720, "1x"), (4640, 1440, "2x")])
try writeJSON(["assets": [
    ["filename": "App Icon.imagestack", "idiom": "tv",
     "role": "primary-app-icon", "size": "400x240"],
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv",
     "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv",
     "role": "top-shelf-image", "size": "1920x720"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
     "role": "top-shelf-image-wide", "size": "2320x720"],
], "info": assetInfo], to: catalog.appendingPathComponent("Contents.json"))

print("Brand assets rebuilt.")
