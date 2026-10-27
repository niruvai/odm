import Foundation
import UniformTypeIdentifiers

struct ProbeResult {
    let finalURL: URL
    let totalBytes: Int64      // -1 if unknown
    let resumable: Bool        // server honours byte ranges
    let suggestedName: String?
}

/// Asks the server for the first byte only, to learn the size, the real file name,
/// the final URL after redirects, and whether byte ranges (multi-connection / resume) work.
final class Prober: NSObject, URLSessionDataDelegate {
    private var completion: ((Result<ProbeResult, Error>) -> Void)?

    static func probe(url: URL, headers: [String: String],
                      completion: @escaping (Result<ProbeResult, Error>) -> Void) {
        let prober = Prober()
        prober.completion = { result in DispatchQueue.main.async { completion(result) } }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: prober, delegateQueue: nil)

        var req = URLRequest(url: url)
        Networking.apply(headers: headers, to: &req)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        session.dataTask(with: req).resume()
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<ProbeResult, Error>) {
        guard let c = completion else { return }
        completion = nil
        c(result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Networking.redirected(request, from: task))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // We only need the headers; stop the body right away.
        completionHandler(.cancel)

        guard let http = response as? HTTPURLResponse else {
            finish(.failure(DMError.message("The link did not return an HTTP response.")))
            return
        }
        if http.statusCode >= 400 {
            finish(.failure(DMError.http(http.statusCode)))
            return
        }

        var total: Int64 = -1
        var resumable = false
        if http.statusCode == 206,
           let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let slash = contentRange.lastIndex(of: "/") {
            let t = contentRange[contentRange.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            if let v = Int64(t), v > 0 {
                total = v
                resumable = true
            }
        } else if http.expectedContentLength > 0 {
            total = http.expectedContentLength
        }

        let finalURL = http.url ?? dataTask.currentRequest?.url ?? dataTask.originalRequest?.url
        guard let resolved = finalURL else {
            finish(.failure(DMError.message("Could not resolve the download URL.")))
            return
        }
        finish(.success(ProbeResult(finalURL: resolved, totalBytes: total,
                                    resumable: resumable, suggestedName: Prober.fileName(from: http))))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(error ?? DMError.message("No response from the server.")))
    }

    // MARK: File name detection

    static func fileName(from http: HTTPURLResponse) -> String? {
        var name: String?

        if let cd = http.value(forHTTPHeaderField: "Content-Disposition") {
            // RFC 5987: filename*=UTF-8''na%20me.zip
            if let r = cd.range(of: "filename*=", options: .caseInsensitive) {
                var v = String(cd[r.upperBound...])
                if let semi = v.firstIndex(of: ";") { v = String(v[..<semi]) }
                v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                if let q = v.range(of: "''") { v = String(v[q.upperBound...]) }
                if let decoded = v.removingPercentEncoding, !decoded.isEmpty { name = decoded }
            }
            if name == nil, let r = cd.range(of: "filename=", options: .caseInsensitive) {
                var v = String(cd[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") {
                    v.removeFirst()
                    if let end = v.firstIndex(of: "\"") { v = String(v[..<end]) }
                } else if let semi = v.firstIndex(of: ";") {
                    v = String(v[..<semi])
                }
                v = v.trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { name = v.removingPercentEncoding ?? v }
            }
        }

        if name == nil, let last = http.url?.lastPathComponent, !last.isEmpty, last != "/" {
            name = last
        }

        // Add an extension from the MIME type when the name has none.
        if let n = name, (n as NSString).pathExtension.isEmpty,
           let mime = http.mimeType, mime != "application/octet-stream",
           let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
            name = n + "." + ext
        }
        return name
    }
}
