import CoreGraphics
import Foundation
@testable import FiestaBoardTV

/// Turns the DEBUG `FigmaGeometryRegistry` into the probe JSON that
/// `scripts/parity/native-parity.mjs` reads (`build/parity/<ref>.probes.json`).
///
/// Frames are in points relative to the Screen slot's root — the view tagged
/// with the slot's Figma id — which is how `get_metadata` reports a slot's
/// children. Text comes from the label passed to `figmaNode(_:label:)`.
enum ParityProbe {
    struct Node: Equatable {
        let figma: String
        let label: String?
        let rect: CGRect
    }

    /// Every registered node, relative to `root`. Nil when the root itself
    /// was never laid out.
    static func nodes(relativeTo root: String,
                      in registry: FigmaGeometryRegistry = .shared) -> [Node]? {
        let all = registry.snapshot()
        guard let origin = all[root]?.frame.origin else { return nil }
        return all.values
            .map { Node(figma: $0.id, label: $0.label,
                        rect: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y)) }
            .sorted { $0.figma < $1.figma }
    }

    static func json(ref: String, root: String, scale: CGFloat,
                     in registry: FigmaGeometryRegistry = .shared) -> [String: Any] {
        let nodes = self.nodes(relativeTo: root, in: registry) ?? []
        return [
            "schema": 1,
            "ref": ref,
            "root": root,
            "scale": scale,
            "source": "FigmaGeometryRegistry (onGeometryChange, global space)",
            "nodes": nodes.map { node -> [String: Any] in
                var out: [String: Any] = [
                    "figma": node.figma,
                    "rect": ["x": round2(node.rect.minX), "y": round2(node.rect.minY),
                             "width": round2(node.rect.width), "height": round2(node.rect.height)],
                ]
                if let label = node.label { out["text"] = label }
                return out
            },
        ]
    }

    private static func round2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
}
