import Foundation

/// FiestaUI's 72-position flap drum, driven by one clock for the whole board.
/// Every changed tile advances one position every 80 ms with no tile stagger.
struct BoardFlipTransition {
    struct Sample {
        let previous: BoardCell
        let next: BoardCell
        let progress: Double
        let isAnimating: Bool

        /// The face on screen. The leaf shows its back (the next glyph) once
        /// it has passed edge-on, which `FlapPhysics` puts before half way
        /// because the fall is gravity-driven.
        var cell: BoardCell { FlapPhysics.showsNext(at: progress) ? next : previous }
    }

    static let stepDuration: TimeInterval = 0.08
    private static let drumSize = 72

    let from: [BoardCell]
    let to: [BoardCell]
    let code62: Code62Glyph
    let startedAt: Date
    let duration: TimeInterval
    private let startCodes: [Int]
    private let distances: [Int]

    init(from: [BoardCell], to: [BoardCell], code62: Code62Glyph, startedAt: Date) {
        self.from = from
        self.to = to
        self.code62 = code62
        self.startedAt = startedAt
        // `codes` stays a local: the closure below cannot capture a stored
        // property while the initialiser is still running.
        let codes = from.map(BoardTables.code(for:))
        startCodes = codes
        distances = to.enumerated().map { index, cell in
            guard codes.indices.contains(index) else { return 0 }
            let target = BoardTables.code(for: cell)
            return (target - codes[index] + Self.drumSize) % Self.drumSize
        }
        duration = Double(distances.max() ?? 0) * Self.stepDuration
    }

    func sample(index: Int, at date: Date) -> Sample {
        guard to.indices.contains(index) else {
            return Sample(previous: .blank, next: .blank, progress: 1, isAnimating: false)
        }
        let target = to[index]
        guard distances.indices.contains(index), distances[index] > 0 else {
            return Sample(previous: target, next: target, progress: 1, isAnimating: false)
        }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let cellDuration = Double(distances[index]) * Self.stepDuration
        guard elapsed + 1e-9 < cellDuration else {
            return Sample(previous: target, next: target, progress: 1, isAnimating: false)
        }
        let step = min(distances[index] - 1, Int(elapsed / Self.stepDuration))
        let previousCode = (startCodes[index] + step) % Self.drumSize
        let nextCode = (previousCode + 1) % Self.drumSize
        let progress = (elapsed - Double(step) * Self.stepDuration) / Self.stepDuration
        return Sample(previous: BoardTables.cell(forCode: previousCode, code62: code62),
                      next: BoardTables.cell(forCode: nextCode, code62: code62),
                      progress: min(1, max(0, progress)), isAnimating: true)
    }

    func retargeted(to newTarget: [BoardCell], at date: Date) -> BoardFlipTransition {
        let visible = newTarget.indices.map { sample(index: $0, at: date).cell }
        return BoardFlipTransition(from: visible, to: newTarget,
                                   code62: code62, startedAt: date)
    }
}
