import Foundation
import Observation

@MainActor
@Observable
final class ConnectModel {

    var boards: [DiscoveredBoard] = []
    var isScanning = false
    var manualAddress = ""
    var errorMessage: String?
    var isConnecting = false

    private let app: AppModel
    private var discovery: BoardDiscovering?

    init(app: AppModel) { self.app = app }

    func startScan(using discovery: BoardDiscovering = BonjourDiscovery()) async {
        self.discovery = discovery
        isScanning = true
        for await found in discovery.boards() {
            boards = found
        }
        isScanning = false
    }

    func stopScan() {
        discovery?.stop()
        discovery = nil
        isScanning = false
    }

    func connect(to host: URL, name: String) async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            let previousHost = app.connection.saved?.host
            let result = try await app.connection.connect(to: host, displayName: name)
            if previousHost != host { app.clearTopShelf() }
            stopScan()
            app.finishConnect(result)
        } catch {
            errorMessage = "Couldn't reach \(host.host() ?? host.absoluteString). Check it's on and on this network."
        }
    }

    func connectManually() async {
        guard let url = ManualAddress.parse(manualAddress) else {
            errorMessage = "Enter an address like 192.168.1.50"
            return
        }
        await connect(to: url, name: url.host() ?? "FiestaBoard")
    }
}
