import Foundation
import Network

/// What the browser extension sends to http://127.0.0.1:9614/add
struct AddRequest: Decodable {
    let url: String
    let filename: String?
    let referrer: String?
    let cookies: String?
    let userAgent: String?
}

/// What the extension sends to http://127.0.0.1:9614/video (a page for yt-dlp)
struct VideoRequest: Decodable {
    let url: String
    let quality: String?
    let cookies: [BrowserCookie]?   // the site's cookies, so signed-in checks pass
}

/// Tiny HTTP server on 127.0.0.1 so the browser extension can hand downloads to the app.
/// Only accepts requests from this Mac, and from browser extensions (never from web pages).
final class LocalServer {
    static let port: UInt16 = 9614

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "odm.server")
    private let onAdd: (AddRequest) -> Void
    private let onVideo: (VideoRequest) -> Void
    private let onPrefetch: (VideoRequest) -> Void
    private var usedFallback = false

    init(onAdd: @escaping (AddRequest) -> Void, onVideo: @escaping (VideoRequest) -> Void,
         onPrefetch: @escaping (VideoRequest) -> Void) {
        self.onAdd = onAdd
        self.onVideo = onVideo
        self.onPrefetch = onPrefetch
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if !usedFallback {
            // Bind to loopback only, so nothing outside this Mac can connect.
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        }
        do {
            let l: NWListener
            if usedFallback {
                l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            } else {
                l = try NWListener(using: params)
            }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                if case .failed(let error) = state {
                    NSLog("ODM: browser bridge failed: \(error)")
                    l.cancel()
                    if !self.usedFallback {
                        self.usedFallback = true
                        self.queue.asyncAfter(deadline: .now() + 1) { self.start() }
                    }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            NSLog("ODM: could not start browser bridge: \(error)")
            if !usedFallback {
                usedFallback = true
                start()
            }
        }
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        if case let .hostPort(host, _) = conn.endpoint {
            let h = "\(host)"
            let isLocal = h.hasPrefix("127.") || h == "::1" || h.hasPrefix("::1%")
                || h.hasPrefix("::ffff:127.") || h == "localhost"
            if !isLocal { conn.cancel(); return }
        }
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }
            if buf.count > 1_000_000 { conn.cancel(); return }
            if let request = HTTPRequest.parse(buf) {
                self.respond(to: request, on: conn)
                return
            }
            if isComplete || error != nil { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    private func respond(to req: HTTPRequest, on conn: NWConnection) {
        let origin = req.headers["origin"] ?? ""
        let fromExtension = origin.hasPrefix("chrome-extension://") || origin.hasPrefix("moz-extension://")
            || origin.hasPrefix("safari-web-extension://")
        // Web pages send their own Origin; refuse them so random sites can't start downloads.
        if !origin.isEmpty && !fromExtension {
            send(conn, status: "403 Forbidden", body: #"{"ok":false,"error":"forbidden"}"#, origin: nil)
            return
        }
        let path = req.path.split(separator: "?").first.map(String.init) ?? req.path

        switch (req.method, path) {
        case ("OPTIONS", _):
            send(conn, status: "204 No Content", body: "", origin: origin)
        case ("GET", "/ping"):
            send(conn, status: "200 OK", body: #"{"ok":true,"app":"ODM"}"#, origin: origin)
        case ("POST", "/add"):
            guard let add = try? JSONDecoder().decode(AddRequest.self, from: req.body) else {
                send(conn, status: "400 Bad Request", body: #"{"ok":false,"error":"bad json"}"#, origin: origin)
                return
            }
            let handler = onAdd
            DispatchQueue.main.async { handler(add) }
            send(conn, status: "200 OK", body: #"{"ok":true}"#, origin: origin)
        case ("POST", "/video"):
            guard let video = try? JSONDecoder().decode(VideoRequest.self, from: req.body) else {
                send(conn, status: "400 Bad Request", body: #"{"ok":false,"error":"bad json"}"#, origin: origin)
                return
            }
            let handler = onVideo
            DispatchQueue.main.async { handler(video) }
            send(conn, status: "200 OK", body: #"{"ok":true}"#, origin: origin)
        case ("POST", "/prefetch"):
            guard let video = try? JSONDecoder().decode(VideoRequest.self, from: req.body) else {
                send(conn, status: "400 Bad Request", body: #"{"ok":false,"error":"bad json"}"#, origin: origin)
                return
            }
            let handler = onPrefetch
            DispatchQueue.main.async { handler(video) }
            send(conn, status: "200 OK", body: #"{"ok":true}"#, origin: origin)
        default:
            send(conn, status: "404 Not Found", body: #"{"ok":false}"#, origin: origin)
        }
    }

    private func send(_ conn: NWConnection, status: String, body: String, origin: String?) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.utf8.count)\r\n"
        head += "Connection: close\r\n"
        if let o = origin, !o.isEmpty {
            head += "Access-Control-Allow-Origin: \(o)\r\n"
            head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        head += "\r\n"
        conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}

/// Minimal HTTP/1.1 request parser (enough for our three endpoints).
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Returns nil until the full request (headers + body) has arrived.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data.subdata(in: data.startIndex..<sep.lowerBound), encoding: .utf8) else {
            return HTTPRequest(method: "BAD", path: "/", headers: [:], body: Data())
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else {
            return HTTPRequest(method: "BAD", path: "/", headers: [:], body: Data())
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard data.endIndex - bodyStart >= length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return HTTPRequest(method: String(requestLine[0]).uppercased(), path: String(requestLine[1]),
                           headers: headers, body: body)
    }
}
