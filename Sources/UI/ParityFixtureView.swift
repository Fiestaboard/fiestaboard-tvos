#if DEBUG
import SwiftUI

/// A DEBUG-only screen for the A0 parity proofs (PHASE-4-TV-PLAN §2.1).
///
/// `-fiestaboard.parityFixture glass` launches straight into it, with no
/// model, network or persisted state. It holds a known pattern — 40 pt
/// alternating pure red and pure blue stripes — under a glass panel, so a
/// screenshot can show whether the material is translucent, plus two
/// focusable buttons so a screenshot can show the focus lift. Every piece is
/// a `figmaNode` with an accessibility identifier, for the registry vs
/// `XCUIElement.frame` cross-check.
struct ParityFixtureView: View {
    enum Kind: String {
        case glass

        static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> Kind? {
            defaults.string(forKey: "fiestaboard.parityFixture").flatMap(Kind.init(rawValue:))
        }
    }

    static let glassNode = "parity:glass"
    static let stripeWidth: CGFloat = 40
    static let panel = CGRect(x: 480, y: 300, width: 960, height: 320)

    let kind: Kind

    var body: some View {
        ZStack(alignment: .topLeading) {
            stripes
            // Tagged at its intrinsic size. XCUITest reports a Text's glyph
            // bounds, so a `.frame` inside the tagged element makes the two
            // disagree (registry 600×80 vs XCUI 216×46), and a `.background`
            // inside it made XCUI report a box anchored at the screen origin.
            Text("Parity fixture")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .figmaNode("parity:title", label: "Parity fixture", identify: true)
                .placed(x: 80, y: 60)
            glass
                .placed(x: Self.panel.minX, y: Self.panel.minY)
            HStack(spacing: 60) {
                Button("First") {}
                    .figmaNode("parity:first", label: "First", identify: true)
                Button("Second") {}
                    .figmaNode("parity:second", label: "Second", identify: true)
            }
            .placed(x: 780, y: 820)
        }
        .frame(width: 1920, height: 1080)
        .ignoresSafeArea() // full-bleed: DEBUG parity fixture laid out in absolute screen points
        .preferredColorScheme(.dark)
    }

    private var stripes: some View {
        HStack(spacing: 0) {
            ForEach(0..<Int(1920 / Self.stripeWidth), id: \.self) { index in
                (index.isMultiple(of: 2) ? Color(red: 1, green: 0, blue: 0) : Color(red: 0, green: 0, blue: 1))
                    .frame(width: Self.stripeWidth)
            }
        }
        .frame(width: 1920, height: 1080)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        if #available(tvOS 26.0, *) {
            Color.clear
                .frame(width: Self.panel.width, height: Self.panel.height)
                .glassEffect(.regular, in: shape)
                .accessibilityElement()
                .accessibilityLabel("Glass panel")
                .figmaNode(Self.glassNode, label: "glassEffect(.regular)", identify: true)
        } else {
            Color.clear
                .frame(width: Self.panel.width, height: Self.panel.height)
                .background(.regularMaterial, in: shape)
                .accessibilityElement()
                .accessibilityLabel("Material panel")
                .figmaNode(Self.glassNode, label: "regularMaterial", identify: true)
        }
    }
}
private extension View {
    /// Top-leading placement by sibling spacers, so no modifier wraps the
    /// accessibility element itself (see `ParityFixtureView`).
    func placed(x: CGFloat, y: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 1, height: y)
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: x, height: 1)
                self
            }
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
