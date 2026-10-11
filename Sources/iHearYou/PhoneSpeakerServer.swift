// iHearYou | Signature: i729
import Foundation
import Network
import Darwin

struct PhoneSpeakerState {
    let urls: [URL]
    let connected: Bool
    let error: String?
}

/// An explicitly enabled LAN receiver. A per-start capability URL authorizes one
/// listener; no microphone input, recordings, or file-system endpoints are served.
final class PhoneSpeakerServer {
    var onState: ((PhoneSpeakerState) -> Void)?
    private let queue = DispatchQueue(label: "com.i729.iHearYou.phone-speaker")
    private let mailboxLock = NSLock()
    private var accepting = false
    private var pending: [Float] = []
    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var stream: NWConnection?
    private var requests: [UUID: NWConnection] = [:]
    private var route = ""
    private var urls: [URL] = []
    private var sending = false
    private var sentAt = Date()
    private var generation = UUID()

    func start() throws {
        guard let file = Bundle.main.url(forResource: "PhoneSpeaker", withExtension: "html"),
              FileManager.default.isReadableFile(atPath: file.path) else {
            throw AudioFailure.message("Halaman speaker iPhone tidak ditemukan di aplikasi.")
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "0.0.0.0", port: .any)
        let nextListener = try NWListener(using: parameters)
        queue.async { [self, nextListener] in
            stopOnQueue()
            let current = UUID()
            generation = current
            route = "/" + UUID().uuidString + "/"
            listener = nextListener
            nextListener.stateUpdateHandler = { [weak self, weak nextListener] state in
                guard let self, self.generation == current else { return }
                switch state {
                case .ready:
                    guard let port = nextListener?.port else { return }
                    let addresses = Self.localAddresses()
                    self.urls = addresses.compactMap { URL(string: "http://\($0):\(port.rawValue)\(self.route)") }
                    self.emit(error: addresses.isEmpty ? "Mac belum memiliki alamat jaringan lokal. Sambungkan Mac dan iPhone ke Wi-Fi yang sama, lalu aktifkan ulang speaker iPhone." : nil)
                case .failed(let error):
                    self.stopOnQueue()
                    self.emit(error: "Penerima iPhone tidak bisa dimulai: \(error.localizedDescription)")
                default: break
                }
            }
            nextListener.newConnectionHandler = { [weak self] connection in
                guard let self, self.generation == current,
                      self.requests.count < 8,
                      Self.isLocalPeer(connection.endpoint) else { connection.cancel(); return }
                let requestID = UUID()
                self.requests[requestID] = connection
                connection.stateUpdateHandler = { [weak self, weak connection] state in
                    guard let self, let connection else { return }
                    if case .failed = state { self.close(connection, requestID: requestID) }
                    if case .cancelled = state { self.close(connection, requestID: requestID) }
                }
                connection.start(queue: self.queue)
                self.receive(connection, requestID: requestID, accumulated: Data())
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
                    guard let self, let connection, self.requests[requestID] === connection else { return }
                    self.close(connection, requestID: requestID)
                }
            }
            let nextTimer = DispatchSource.makeTimerSource(queue: queue)
            timer = nextTimer
            nextTimer.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(3))
            nextTimer.setEventHandler { [weak self] in self?.flush() }
            nextTimer.resume()
            nextListener.start(queue: queue)
        }
    }

    /// Called on the inference queue, never on the audio render callback. The
    /// mailbox bounds both memory and latency even when a receiver stops reading.
    func publish(_ samples: [Float]) {
        mailboxLock.lock()
        defer { mailboxLock.unlock() }
        guard accepting else { return }
        let incoming = samples.suffix(9600)
        let excess = pending.count + incoming.count - 9600
        if excess > 0 { pending.removeFirst(min(excess, pending.count)) }
        pending.append(contentsOf: incoming)
    }

    func stop() { queue.async { [self] in stopOnQueue(); emit() } }

    private func setAccepting(_ enabled: Bool) {
        mailboxLock.lock(); accepting = enabled; pending.removeAll(keepingCapacity: true); mailboxLock.unlock()
    }
    private func stopOnQueue() {
        generation = UUID()
        listener?.cancel(); listener = nil
        timer?.cancel(); timer = nil
        let oldStream = stream; stream = nil; oldStream?.cancel()
        let oldRequests = requests; requests.removeAll()
        oldRequests.values.forEach { $0.cancel() }
        urls = []; sending = false
        setAccepting(false)
    }
    private func emit(error: String? = nil) {
        let state = PhoneSpeakerState(urls: urls, connected: stream != nil, error: error)
        DispatchQueue.main.async { [weak self] in self?.onState?(state) }
    }
    private func close(_ connection: NWConnection, requestID: UUID) {
        requests.removeValue(forKey: requestID)
        if stream === connection {
            stream = nil; sending = false; setAccepting(false); emit()
        }
        connection.cancel()
    }

    private func receive(_ connection: NWConnection, requestID: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, connection] data, _, complete, error in
            guard let self, self.requests[requestID] === connection, error == nil else { connection.cancel(); return }
            var request = accumulated
            if let data { request.append(data) }
            guard request.count <= 8192 else { self.close(connection, requestID: requestID); return }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { self.close(connection, requestID: requestID) }
                else { self.receive(connection, requestID: requestID, accumulated: request) }
                return
            }
            let parts = text.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
            guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/1.") else {
                self.respond(connection, requestID: requestID, code: "405 Method Not Allowed", body: Data("GET only".utf8)); return
            }
            if parts[1] == Substring(self.route) {
                let body = Bundle.main.url(forResource: "PhoneSpeaker", withExtension: "html")
                    .flatMap { try? Data(contentsOf: $0) } ?? Data()
                self.respond(connection, requestID: requestID, code: "200 OK", body: body)
            } else if parts[1] == Substring(self.route + "stream") {
                guard self.stream == nil else {
                    self.respond(connection, requestID: requestID, code: "409 Conflict", body: Data("Speaker sedang digunakan oleh tab lain. Putuskan tab itu dahulu.".utf8)); return
                }
                self.requests.removeValue(forKey: requestID)
                self.stream = connection; self.sending = true; self.sentAt = Date()
                self.setAccepting(true)
                let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, let connection, self.stream === connection else { return }
                    if error != nil { self.close(connection, requestID: requestID) }
                    else { self.sending = false; self.emit() }
                })
                // Detect a tab closing even while audio capture is stopped.
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak connection] _, _, _, _ in
                    guard let self, let connection else { return }
                    self.close(connection, requestID: requestID)
                }
            } else {
                self.respond(connection, requestID: requestID, code: "404 Not Found", body: Data("Not found".utf8))
            }
        }
    }
    private func respond(_ connection: NWConnection, requestID: UUID, code: String, body: Data) {
        let header = "HTTP/1.1 \(code)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in self?.close(connection, requestID: requestID) })
    }
    private func flush() {
        guard let stream else { return }
        if sending {
            if Date().timeIntervalSince(sentAt) > 1 { close(stream, requestID: UUID()) }
            return
        }
        mailboxLock.lock()
        let samples = pending.isEmpty ? [Float](repeating: 0, count: 1920) : pending
        pending.removeAll(keepingCapacity: true)
        mailboxLock.unlock()
        let bytes = samples.withUnsafeBytes { Data($0) }
        let chunk = Data("\(String(bytes.count, radix: 16))\r\n".utf8) + bytes + Data("\r\n".utf8)
        sending = true; sentAt = Date()
        stream.send(content: chunk, completion: .contentProcessed { [weak self, weak stream] error in
            guard let self, let stream, self.stream === stream else { return }
            if error != nil { self.close(stream, requestID: UUID()) }
            else { self.sending = false }
        })
    }
    private static func isPrivateAddress(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 169 && octets[1] == 254)
    }
    private static func isLocalPeer(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        return isPrivateAddress(String(describing: host))
    }
    private static func localAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var result: [(String, String)] = []
        var current = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host), name = String(cString: entry.pointee.ifa_name)
            guard isPrivateAddress(ip), !name.hasPrefix("utun") else { continue }
            result.append((name, ip))
        }
        // Prefer Wi-Fi/Ethernet over bridge adapters when presenting the link.
        result.sort { ($0.0.hasPrefix("en") ? 0 : 1, $0.0) < ($1.0.hasPrefix("en") ? 0 : 1, $1.0) }
        return result.reduce(into: []) { if !$0.contains($1.1) { $0.append($1.1) } }
    }
}
