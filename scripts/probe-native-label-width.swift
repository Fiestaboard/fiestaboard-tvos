import AppKit
import Foundation

/// Verify a retained native control can contain its full label at the TV
/// typography floor. Arguments: fullLabel measuredControlWidth.
@main
struct ProbeNativeLabelWidth {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3, let width = Double(args[2]) else {
            throw NSError(domain: "NativeLabelWidth", code: 2)
        }
        let minimum = (args[1] as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 23)]).width
        print("label=\(args[1]) nativeWidth=\(width) minimumFullLabelWidthAt23pt=\(minimum)")
        exit(width >= minimum ? 0 : 1)
    }
}
