import Foundation
import XCTest
@testable import FiestaBoardTV

enum SpecFixture {
    /// The bundled board-spec.json, loaded once.
    static let spec: BoardSpec = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "board-spec", withExtension: "json", subdirectory: "Spec")
            ?? Bundle.main.url(forResource: "board-spec", withExtension: "json", subdirectory: "Spec") else {
            fatalError("board-spec.json is not in the test bundle — check the Spec folder reference in project.yml")
        }
        return try! BoardSpec.load(from: url)
    }()
}

private final class BundleToken {}
