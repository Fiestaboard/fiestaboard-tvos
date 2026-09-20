import Foundation

/// The one clock shared by all changing flaps in a frame.
/// A tile's face and vertical scale are deterministic at any timestamp.
struct BoardFlipTransition {
    struct Sample {
        let cell: BoardCell
        let scaleY: Double
    }

    static let duration = 0.18
    static let totalDuration = 0.36

    let from: [BoardCell]
    let to: [BoardCell]
    let columns: Int
    let startedAt: Date

    func sample(index: Int, at date: Date) -> Sample {
        guard to.indices.contains(index) else { return Sample(cell: .blank, scaleY: 1) }
        let next = to[index]
        guard from.indices.contains(index), from[index] != next else {
            return Sample(cell: next, scaleY: 1)
        }
        let colCount = max(columns, 1)
        let delay = Double((index / colCount + index % colCount) % 8) * 0.025
        let elapsed = date.timeIntervalSince(startedAt) - delay
        let phase = min(1, max(0, elapsed / Self.duration))
        let face = phase < 0.5 ? from[index] : next
        return Sample(cell: face, scaleY: max(0.06, abs(1 - 2 * phase)))
    }
}
