import Foundation
import IOKit
import ABCore

/// Abbruchmarke, threadsicher.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Führt alle MTP-Vorgänge eines Geräts nacheinander auf einer eigenen Warteschlange aus
/// (MTP erlaubt nur eine Transaktion zur selben Zeit). Vorgänge mit höherer Priorität – Ordner öffnen –
/// werden vor wartenden Übertragungsabschnitten und Vorschaubildern ausgeführt.
final class MTPWorker: @unchecked Sendable {
    private let queue: OperationQueue
    private var session: MTPSession?
    private var transport: IOUSBHostTransport?
    /// Nach `close` laufen keine neuen Vorgänge mehr an (sie enden sofort mit „getrennt“).
    private let closing = CancelFlag()

    init(name: String) {
        queue = OperationQueue()
        queue.name = "AndroidBridge.MTP.\(name)"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
    }

    /// Öffnet Schnittstelle und MTP-Sitzung. Gibt `interfaceService` in jedem Fall frei.
    func open(interfaceService: io_service_t, timeout: TimeInterval) async throws -> MTPDeviceInfo {
        try await run(priority: .veryHigh, requiresSession: false) { [self] _, _ in
            defer { IOObjectRelease(interfaceService) }
            let transport = try IOUSBHostTransport(interfaceService: interfaceService)
            let session = MTPSession(transport: transport)
            session.commandTimeout = min(timeout, 10)
            session.responseTimeout = max(timeout, 20)
            do {
                let info = try session.getDeviceInfo()
                try session.openSession()
                self.transport = transport
                self.session = session
                Diagnostics.shared.log(.mtp, "Sitzung geöffnet (Paketgröße \(transport.maxPacketSize), \(info.operationsSupported.count) Operationen, Teilstücke: \(session.supportsPartialDownload ? "ja" : "nein"))")
                return info
            } catch {
                transport.close()
                throw error
            }
        }
    }

    /// Schließt Sitzung und Schnittstelle; wartende Vorgänge werden abgebrochen.
    func close(graceful: Bool) {
        closing.cancel()
        let op = BlockOperation { [self] in
            if graceful { session?.closeSession() }
            transport?.close()
            session = nil
            transport = nil
        }
        op.queuePriority = .veryHigh
        queue.addOperation(op)
    }

    /// Führt `body` mit der Sitzung auf der Gerätewarteschlange aus.
    func run<T>(priority: Operation.QueuePriority = .normal, requiresSession: Bool = true,
                _ body: @escaping (MTPSession?, CancelFlag) throws -> T) async throws -> T {
        let flag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let op = BlockOperation { [weak self] in
                    if flag.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let self else {
                        continuation.resume(throwing: MTPError.disconnected)
                        return
                    }
                    if self.closing.isCancelled || (requiresSession && self.session == nil) {
                        continuation.resume(throwing: MTPError.disconnected)
                        return
                    }
                    do {
                        continuation.resume(returning: try body(self.session, flag))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                op.queuePriority = priority
                queue.addOperation(op)
            }
        } onCancel: {
            flag.cancel()
        }
    }

    /// Bequemer Zugriff, wenn eine offene Sitzung vorausgesetzt wird.
    func withSession<T>(priority: Operation.QueuePriority = .normal,
                        _ body: @escaping (MTPSession, CancelFlag) throws -> T) async throws -> T {
        try await run(priority: priority) { session, flag in
            guard let session else { throw MTPError.disconnected }
            return try body(session, flag)
        }
    }
}
