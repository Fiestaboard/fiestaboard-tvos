import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Locally encoded QR with a four-module white quiet zone and integer pixels.
enum QRCode {
    static func image(for value: String, scale: Int = 8) -> CGImage? {
        guard scale > 0 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let quiet = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor.white).cropped(to: quiet)
        let composed = code.composited(over: white).transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return CIContext().createCGImage(composed, from: composed.extent)
    }
}
struct QRCodeView: View {
    let url: URL
    var body: some View {
        if let image = QRCode.image(for: url.absoluteString) {
            Image(decorative: image, scale: 1).interpolation(.none)
                .frame(width: CGFloat(image.width), height: CGFloat(image.height)).accessibilityHidden(true)
        }
    }
}
