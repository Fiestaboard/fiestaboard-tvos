import Foundation
import Network

/// A loopback FiestaBoard fixture shared by the UI test and the app process.
final class FixtureHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FiestaBoardUITests.fixtureServer")
    private let onFrame: () -> Void
    private let lock = NSLock()
    private var sawFrame = false

    var port: UInt16 { listener.port!.rawValue }

    init(onFrame: @escaping () -> Void) throws {
        self.onFrame = onFrame
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, listener.port != nil else {
            throw NSError(domain: "FixtureHTTPServer", code: 1)
        }
    }

    deinit { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let body: String
            switch path {
            case "/api/panel/1": body = Fixtures.panelJSON
            case "/api/panel/1/frame":
                body = Fixtures.emptyFrameJSON
                self.lock.lock()
                let firstFrame = !self.sawFrame
                self.sawFrame = true
                self.lock.unlock()
                if firstFrame { self.onFrame() }
            case "/api/panels": body = Fixtures.panelsList
            default: body = #"{"detail":"Not found"}"#
            }
            let payload = Data(body.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + payload,
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
