import Foundation

/// Intercepts URLSession traffic so client tests never touch the network.
///
/// Responses are queued per path prefix. `requests` records what was sent,
/// including bodies, so tests can assert on the request as well as the reply.
final class StubURLProtocol: URLProtocol {

    struct Stub {
        let status: Int
        let body: Data
        let headers: [String: String]

        init(status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }

        static func json(_ string: String, status: Int = 200) -> Stub {
            Stub(status: status, body: Data(string.utf8),
                 headers: ["Content-Type": "application/json"])
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [Stub]] = [:]
    nonisolated(unsafe) private static var recorded: [(url: URL, method: String, body: Data?)] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queues = [:]
        recorded = []
    }

    /// Queue a response for the next request whose path contains `pathFragment`.
    static func enqueue(_ stub: Stub, for pathFragment: String) {
        lock.lock(); defer { lock.unlock() }
        queues[pathFragment, default: []].append(stub)
    }

    static var requests: [(url: URL, method: String, body: Data?)] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // Longest matching fragment wins, so "/api/panels" and "/api/panel/" can coexist.
    private static func dequeue(for url: URL) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        let path = url.path
        let key = queues.keys
            .filter { path.contains($0) && !(queues[$0]?.isEmpty ?? true) }
            .max(by: { $0.count < $1.count })
        guard let key, var queue = queues[key], !queue.isEmpty else { return nil }
        let stub = queue.removeFirst()
        queues[key] = queue
        return stub
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        // httpBody is nil for stream-backed bodies; read the stream instead.
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
            body = data
        }

        StubURLProtocol.lock.lock()
        StubURLProtocol.recorded.append((url, request.httpMethod ?? "GET", body))
        StubURLProtocol.lock.unlock()

        guard let stub = StubURLProtocol.dequeue(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
