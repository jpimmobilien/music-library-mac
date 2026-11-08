import Foundation
import ImageIO
import MLStudio

/// Netzwerkzugriffe des Audio Studios: eigener User-Agent, keine Cookies, kein Zwischenspeicher, Zeitlimits.
/// Es werden keine Daten des Nutzers gesendet – nur die angefragte Adresse.
public enum StudioHTTP {
    public static let userAgent = "MusicLibrary-AudioStudio"

    static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = max(timeout, 600)
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }

    /// Kleine Antwort laden (JSON, Prüfsummen, Bilder) mit Größenbegrenzung. Lokale Dateien (file://) für Tests.
    public static func data(from url: URL, maxBytes: Int, timeout: TimeInterval = 20, accept: String? = nil) async throws -> Data {
        if url.isFileURL {
            let data = try Data(contentsOf: url)
            guard data.count <= maxBytes else { throw StudioError.other("Die Antwort ist zu groß.") }
            return data
        }
        guard url.scheme?.lowercased() == "https" else { throw StudioError.unsupportedURL }
        var request = URLRequest(url: url)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        let session = URLSession(configuration: configuration(timeout: timeout))
        defer { session.finishTasksAndInvalidate() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            try check(response)
            if response.expectedContentLength > Int64(maxBytes) { throw StudioError.other("Die Antwort ist zu groß.") }
            var data = Data()
            data.reserveCapacity(min(max(Int(response.expectedContentLength), 0), maxBytes))
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw StudioError.other("Die Antwort ist zu groß.") }
            }
            return data
        } catch {
            throw map(error)
        }
    }

    /// Datei laden (Werkzeuge) mit Fortschritt (geladene Bytes, Gesamtgröße falls bekannt).
    public static func download(from url: URL, to destination: URL, maxBytes: Int64 = 400 * 1024 * 1024, timeout: TimeInterval = 60,
                                progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        if url.isFileURL {
            try fm.copyItem(at: url, to: destination)
            let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            progress(size, size)
            return
        }
        guard url.scheme?.lowercased() == "https" else { throw StudioError.unsupportedURL }
        let delegate = DownloadDelegate(destination: destination, maxBytes: maxBytes, progress: progress)
        let session = URLSession(configuration: configuration(timeout: timeout), delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: URLRequest(url: url))
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    delegate.setContinuation(c)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw map(error)
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 404, 410: throw StudioError.unavailable("Die Adresse wurde nicht gefunden (HTTP \(http.statusCode)).")
        case 401, 403: throw StudioError.network("Zugriff verweigert (HTTP \(http.statusCode)).")
        case 429: throw StudioError.network("Zu viele Anfragen – bitte später erneut versuchen (HTTP 429).")
        default: throw StudioError.network("HTTP \(http.statusCode)")
        }
    }

    static func map(_ error: Error) -> Error {
        if error is StudioError { return error }
        if error is CancellationError { return StudioError.cancelled }
        if let u = error as? URLError {
            switch u.code {
            case .cancelled: return StudioError.cancelled
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
                 .secureConnectionFailed, .serverCertificateUntrusted, .internationalRoamingOff, .dataNotAllowed:
                return StudioError.network(u.localizedDescription)
            default:
                return StudioError.network(u.localizedDescription)
            }
        }
        return StudioError.other(error.localizedDescription)
    }

    // MARK: Vorschaubilder

    /// Vorschaubild laden: nur https, höchstens 5 MB, Zeitlimit; WebP u. a. werden nach JPEG gewandelt.
    public static func thumbnail(from url: URL, maxBytes: Int = 5 * 1024 * 1024, timeout: TimeInterval = 15) async -> Data? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard let data = try? await data(from: url, maxBytes: maxBytes, timeout: timeout, accept: "image/jpeg,image/png,image/webp,image/*") else { return nil }
        return normalizedImage(data)
    }

    /// JPEG und PNG unverändert; andere Bildformate (WebP, HEIC, GIF …) → JPEG. nil, wenn es kein Bild ist.
    public static func normalizedImage(_ data: Data) -> Data? {
        if isJPEG(data) || isPNG(data) { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static func isJPEG(_ d: Data) -> Bool { d.count > 3 && d[d.startIndex] == 0xFF && d[d.startIndex + 1] == 0xD8 && d[d.startIndex + 2] == 0xFF }
    static func isPNG(_ d: Data) -> Bool { d.count > 8 && d.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }
}

/// Download mit Fortschritt (Delegate-Variante, damit auch große Dateien nicht im Speicher landen).
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let maxBytes: Int64
    private let progress: @Sendable (Int64, Int64?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var finished = false
    private var lastReport: TimeInterval = 0

    init(destination: URL, maxBytes: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.destination = destination
        self.maxBytes = maxBytes
        self.progress = progress
    }

    func setContinuation(_ c: CheckedContinuation<Void, Error>) {
        lock.lock()
        if finished {
            let f = failure
            lock.unlock()
            if let f { c.resume(throwing: f) } else { c.resume() }
            return
        }
        continuation = c
        lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes {
            lock.lock(); failure = StudioError.other("Die Datei ist unerwartet groß."); lock.unlock()
            downloadTask.cancel()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let report = now - lastReport >= 0.2
        if report { lastReport = now }
        lock.unlock()
        if report { progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let response = downloadTask.response { try StudioHTTP.check(response) }
            let fm = FileManager.default
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            progress(size, size)
        } catch {
            lock.lock(); failure = error; lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if failure == nil, let error { failure = error }
        finished = true
        let c = continuation
        continuation = nil
        let f = failure
        lock.unlock()
        guard let c else { return }
        if let f { c.resume(throwing: f) } else { c.resume() }
    }
}
