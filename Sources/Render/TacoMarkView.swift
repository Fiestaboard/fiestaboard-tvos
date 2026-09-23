import SwiftUI

/// The taco mark, drawn live from `TacoMark`'s grid.
///
/// The asset catalog ships the same geometry as PNGs because tvOS wants
/// files for an icon; anything the app draws itself goes through this view,
/// so both come from the one definition.
public struct TacoMarkView: View {

    public init() {}

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            for shape in TacoMark.shapes(in: CGRect(origin: .zero, size: size)) {
                context.fill(Path(shape.path), with: .color(Color(cgColor: shape.fill)))
            }
        }
        .aspectRatio(TacoMark.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
