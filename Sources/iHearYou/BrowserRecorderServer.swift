// iHearYou | Signature: i729
import Foundation
import Network

/// Serves the recorder only on loopback; audio stays in the browser, never in HTTP requests.
final class BrowserRecorderServer {
    private let queue = DispatchQueue(label: "com.i729.iHearYou.browser")
    private var listener: NWListener?
    private var readyURL: URL?
    private let route = "/" + UUID().uuidString + "/"
    private var pending: [(Result<URL, Error>) -> Void] = []
    func open(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            if let readyURL { DispatchQueue.main.async { completion(.success(readyURL)) }; return }
            pending.append(completion)
            guard listener == nil else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port,
                              let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(self.route)") else { return }
                        self.readyURL = url; self.finish(.success(url))
                    case .failed(let error): self.readyURL = nil; self.listener = nil; self.finish(.failure(error))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    connection.start(queue: self.queue)
                    self.receive(connection, accumulated: Data())
                    self.queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
                }
                listener.start(queue: queue)
            } catch { listener = nil; finish(.failure(error)) }
        }
    }
    private func finish(_ result: Result<URL, Error>) {
        let callbacks = pending; pending = []
        DispatchQueue.main.async { callbacks.forEach { $0(result) } }
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var request = accumulated; if let data { request.append(data) }
            guard request.count <= 8192 else { connection.cancel(); return }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, accumulated: request) }
                return
            }
            let valid = text.hasPrefix("GET \(self.route) HTTP/1.")
            let file = Bundle.main.url(forResource: "BrowserRecorder", withExtension: "html")
            let body = valid ? (file.flatMap { try? Data(contentsOf: $0) } ?? Data("Recorder tidak ditemukan.".utf8)) : Data("Not found".utf8)
            let header = "HTTP/1.1 \(valid ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self' blob:; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'; connect-src 'none'\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
    func stop() { queue.async { [self] in listener?.cancel(); listener = nil; readyURL = nil } }
}
