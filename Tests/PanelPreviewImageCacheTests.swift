import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelPreviewImageCacheTests: XCTestCase {
    private func request(id: String = "one") throws -> PanelPreviewImageCache.Request {
        let json = Fixtures.panelJSON.replacingOccurrences(of: "abc123def456", with: id)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
        return .init(panel: panel, preview: .init(rows: 1, cols: 1, cells: [[.character("A")]], message: "A"),
                     size: CGSize(width: 100, height: 60))
    }

    private func bitmap() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
            bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    func testRepeatedCardEvaluationReusesTheRenderedPicture() throws {
        let cache = PanelPreviewImageCache()
        let key = try request()
        let image = try bitmap()
        var renders = 0
        for _ in 0..<60 {
            XCTAssertTrue(cache.image(for: key) { renders += 1; return image } === image)
        }
        XCTAssertEqual(renders, 1, "Focus/scroll updates must not repaint an unchanged board")
    }

    func testContentSizeScaleAndAccessibilityChangesInvalidateThePicture() throws {
        let original = try request()
        var changes: [PanelPreviewImageCache.Request] = []
        var changed = original; changed.size.width += 1; changes.append(changed)
        changed = original; changed.scale = 2; changes.append(changed)
        changed = original; changed.reduceTransparency = true; changes.append(changed)
        changed = original; changed.increasedContrast = true; changes.append(changed)
        changed = original; changed.colorScheme = .light; changes.append(changed)
        let other = PanelPreviewImageCache.Request(panel: original.panel,
            preview: .init(rows: 1, cols: 1, cells: [[.color(.red)]], message: nil), size: original.size)
        changes.append(other)
        let alteredPanel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON
            .replacingOccurrences(of: "abc123def456", with: "one")
            .replacingOccurrences(of: "\"board_color\":\"black\"", with: "\"board_color\":\"white\"").utf8))
        changes.append(.init(panel: alteredPanel, preview: original.preview, size: original.size))
        let image = try bitmap()
        for key in changes {
            XCTAssertNotEqual(key, original)
            let cache = PanelPreviewImageCache()
            var renders = 0
            _ = cache.image(for: original) { renders += 1; return image }
            _ = cache.image(for: key) { renders += 1; return image }
            _ = cache.image(for: key) { renders += 1; return image }
            XCTAssertEqual(renders, 2, "Each individual change must invalidate the original picture")
        }
    }

    func testMemoryBudgetEvictsLeastRecentlyUsedPanelAndClearReleasesAll() throws {
        let image = try bitmap()
        let cache = PanelPreviewImageCache(byteLimit: image.bytesPerRow * image.height * 2, countLimit: 12)
        let a = try request(id: "a"), b = try request(id: "b"), c = try request(id: "c")
        var renders = 0
        func read(_ key: PanelPreviewImageCache.Request) {
            _ = cache.image(for: key) { renders += 1; return image }
        }
        read(a); read(b); read(a); read(c); read(a)
        XCTAssertEqual(renders, 3)
        read(b)
        XCTAssertEqual(renders, 4, "The least recently used image should be evicted")
        cache.removeAll(); read(a)
        XCTAssertEqual(renders, 5)
    }

    func testFailedRenderIsRetryableAndCountBudgetIsEnforced() throws {
        let cache = PanelPreviewImageCache(countLimit: 1)
        let a = try request(id: "a"), b = try request(id: "b")
        let image = try bitmap()
        XCTAssertNil(cache.image(for: a) { nil })
        var renders = 0
        for key in [a, a, b, a] {
            _ = cache.image(for: key) { renders += 1; return image }
        }
        XCTAssertEqual(renders, 3)
    }

    func testOversizedImageIsReturnedWithoutBeingRetained() throws {
        let image = try bitmap()
        let cache = PanelPreviewImageCache(byteLimit: image.bytesPerRow * image.height - 1)
        let key = try request()
        var renders = 0
        for _ in 0..<2 {
            XCTAssertTrue(cache.image(for: key) { renders += 1; return image } === image)
        }
        XCTAssertEqual(renders, 2, "An oversized image must not remain in the working set")
    }
}
