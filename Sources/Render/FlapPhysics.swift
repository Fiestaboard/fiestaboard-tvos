import Foundation

/// One leaf of a split-flap, from the moment the drum lets it go to the
/// moment it comes to rest against the stop below.
///
/// Everything here is a pure function of a step's progress, so the renderer
/// stays deterministic and the tests can sample it. Angles are radians about
/// the tile's horizontal axle: 0 is the leaf standing upright showing the
/// previous glyph, π/2 is edge-on to the viewer, π is fallen flat against
/// the lower stop showing the next glyph. The leaf falls *toward* the
/// viewer, so its free edge comes off the board plane on the way down.
enum FlapPhysics {

    /// Fraction of the step spent falling. The rest is the rebound off the stop.
    static let impact = 0.64

    /// How far the leaf kicks back off the stop, in radians (~17°). The
    /// rebound profile below peaks at a little over half of this.
    static let reboundAmplitude = 0.30

    /// Where the eye is, in leaf half-heights from the board. Sets how much
    /// the free edge widens as it swings out toward the viewer: 1.11× at 45°,
    /// 1.17× edge-on. Widening stays inside the gutter so leaves never
    /// overlap a neighbour.
    static let eyeDistance = 7.0

    /// Room light: from the front, a little above the eye, so the falling
    /// face darkens as it tips up and away and the landing face arrives
    /// from the dark. The gloss is a sheen the face has only when it is
    /// square to the viewer, so it dips visibly as the leaf bounces off the
    /// stop and comes back. Nothing is ever brighter than at rest: a flash
    /// on an OLED-black face reads as a grey slab, not a highlight.
    private static let lightElevation = 12.0 * .pi / 180
    private static let ambient = 0.2
    private static let gloss = 0.35
    private static let glossExponent = 20.0

    /// Hinge angle at `progress` (0…1 through one drum step).
    static func angle(at progress: Double) -> Double {
        let p = min(1, max(0, progress))
        if p < impact {
            // Gravity: a small push off the catch, then constant angular
            // acceleration. It arrives at the stop ~12× faster than it left.
            let s = p / impact
            return .pi * (0.15 * s + 0.85 * s * s)
        }
        // Impact, then one damped kick back off the stop that dies out
        // exactly at the end of the step so the next step starts clean.
        let s = (p - impact) / (1 - impact)
        return .pi - reboundAmplitude * sin(.pi * s) * (1 - s)
    }

    /// Whether the leaf has passed edge-on, so the viewer sees its back face
    /// (the next glyph) rather than its front (the previous one).
    static func showsNext(at progress: Double) -> Bool {
        angle(at: progress) >= .pi / 2
    }

    struct Projection: Equatable {
        /// On-screen height of the leaf as a fraction of its true half-tile.
        let height: Double
        /// How much wider the free edge draws than the hinge edge.
        let widthFactor: Double
    }

    /// Perspective projection of the leaf from `eyeDistance`. The free edge
    /// at height h swings to depth h·sinθ toward the eye, so it is magnified
    /// by d/(d − h·sinθ) — which is also why the projected height is not a
    /// plain cosine.
    static func projection(angle: Double) -> Projection {
        let magnification = eyeDistance / (eyeDistance - sin(angle))
        return Projection(height: abs(cos(angle)) * magnification,
                          widthFactor: magnification)
    }

    /// Brightness of the visible face, 0…1, relative to at rest. Exactly 1
    /// at both ends of the step so the flap does not pop when the static
    /// tile takes over, and never above it.
    static func brightness(angle: Double) -> Double {
        // Elevation of the visible face's normal: the front face tilts up as
        // it falls; the back face comes into view pointing at the floor.
        let elevation = angle <= .pi / 2 ? angle : angle - .pi
        let atRest = cos(lightElevation)
        let diffuse = max(0, cos(elevation - lightElevation)) / atRest
        let sheen = pow(max(0, cos(elevation)), glossExponent)
        return min(1, max(0, ambient + (1 - ambient) * diffuse - gloss * (1 - sheen)))
    }

    struct CastShadow: Equatable {
        /// How far down the lower half the shadow reaches, 0…1.
        let depth: Double
        let opacity: Double
    }

    /// The shadow the leaf throws onto the lower half of the tile. The
    /// overhead component of the room light puts it there once the leaf has
    /// tipped past ~45°, and the leaf itself then covers it as it comes down.
    static func castShadow(angle: Double) -> CastShadow {
        let reach = min(1, max(0, (sin(angle) - cos(angle)) * 1.25))
        return CastShadow(depth: reach, opacity: 0.45 * reach)
    }
}
