import Foundation

import Dispatch

// TODO: All of this is very hacky and NOT fully fleshed out!
final class SocketNetworkConnection: NetworkConnection {
    let settings: NetworkConnectionSettings

    private let stateLock = NSLock()
    private var storedSocket: Socket?
    private var didStart = false
    private var isCancelled = false
    private var storedStatus: NetworkConnectionStatus = .setup
    private var storedStatusUpdateHandler: NetworkConnectionStatusUpdateHandler?
    private var statusRevision = 0
    private let statusCallbackQueue = DispatchQueue(label: "com.royalapps.royalvnc.socket.status")
    private let statusCallbackLock = NSRecursiveLock()

    // This will be replaced when calling start. Calling any other method before start (which would use this placeholder queue) is a programmer error.
    private var queue = DispatchQueue(label: "PLACEHOLDER")

    var status: NetworkConnectionStatus {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedStatus
    }

    init(settings: NetworkConnectionSettings) {
#if os(Windows)
        do {
            try Winsock.intializeWinsock()
        } catch {
            fatalError("Initializing Winsock failed: \(error.humanReadableDescription)")
        }
#endif

        self.settings = settings
    }

    func setStatusUpdateHandler(_ statusUpdateHandler: NetworkConnectionStatusUpdateHandler?) {
        statusCallbackLock.lock()
        stateLock.lock()
        storedStatusUpdateHandler = statusUpdateHandler
        statusRevision += 1
        stateLock.unlock()
        statusCallbackLock.unlock()
    }

    var isReady: Bool {
        switch status {
            case .ready:
                true
            default:
                false
        }
    }

    func cancel() {
        statusCallbackLock.lock()
        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            statusCallbackLock.unlock()
            return
        }
        isCancelled = true
        storedStatus = .cancelled
        let socket = storedSocket
        scheduleStatusUpdateLocked(.cancelled)
        stateLock.unlock()

        socket?.shutdown()
        statusCallbackLock.unlock()
    }

    func start(queue: DispatchQueue) {
        stateLock.lock()
        guard !didStart, !isCancelled else {
            stateLock.unlock()
            return
        }
        didStart = true
        self.queue = queue
        storedStatus = .preparing
        scheduleStatusUpdateLocked(.preparing)
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }

            do {
                let addressInfo = try AddressInfo(host: settings.host,
                                                               port: settings.port)

                let socket = try Socket(addressInfo: addressInfo)

                stateLock.lock()
                guard !isCancelled else {
                    stateLock.unlock()
                    return
                }
                storedSocket = socket
                stateLock.unlock()

                try socket.connect()

                updateStatus(.ready)
            } catch {
                updateStatus(.failed(error))
            }
        }
    }

    private func updateStatus(_ newStatus: NetworkConnectionStatus) {
        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            return
        }
        storedStatus = newStatus
        scheduleStatusUpdateLocked(newStatus)
        stateLock.unlock()
    }

    /// Must be called while `stateLock` is held to preserve transition order.
    private func scheduleStatusUpdateLocked(_ newStatus: NetworkConnectionStatus) {
        statusRevision += 1
        let revision = statusRevision
        statusCallbackQueue.async { [weak self] in
            guard let self else { return }
            self.statusCallbackLock.lock()
            self.stateLock.lock()
            guard revision == self.statusRevision else {
                self.stateLock.unlock()
                self.statusCallbackLock.unlock()
                return
            }
            let handler = self.storedStatusUpdateHandler
            self.stateLock.unlock()
            handler?(newStatus)
            self.statusCallbackLock.unlock()
        }
    }

    private func currentSocket() -> Socket? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedSocket
    }

    private var cancellationRequested: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }
}

// MARK: - Reading
extension SocketNetworkConnection: NetworkConnectionReading {
	func read(minimumLength: Int,
              maximumLength: Int) async throws -> Data {
        let queue = self.queue

        guard let socket = currentSocket() else {
            throw VNCError.connection(.notReady)
        }

        let bufferSize = maximumLength

		return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                let bytesRead: Int
                do {
                    bytesRead = try socket.receive(buffer: &buffer)
                } catch {
                    let connectionError: VNCError = self.cancellationRequested
                        ? .connection(.cancelled)
                        : .connection(.failed(error))
                    continuation.resume(throwing: connectionError)
                    return
                }

                // Handle connection closure
                if bytesRead == 0 {
                    let connectionError: VNCError = self.cancellationRequested
                        ? .connection(.cancelled)
                        : .connection(.closed)
                    continuation.resume(throwing: connectionError)

                    return
                }

                // Slice the buffer to get only the received data
                let receivedData = Array(buffer.prefix(.init(bytesRead)))
                let receivedLength = receivedData.count

                // Validate received data length
                guard receivedLength >= minimumLength,
                      receivedLength <= maximumLength else {
                    continuation.resume(throwing: VNCError.protocol(.invalidData))

                    return
                }

                continuation.resume(returning: Data(receivedData))
            }
        }
	}
}

// MARK: - Writing
extension SocketNetworkConnection: NetworkConnectionWriting {
	func write(data: Data) async throws {
        let queue = self.queue

        guard let socket = currentSocket() else {
            throw VNCError.connection(.notReady)
        }

		return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let bytesToSend = [UInt8](data)
                do {
                    _ = try socket.send(buffer: bytesToSend)
                    continuation.resume()
                } catch {
                    let connectionError: VNCError = self.cancellationRequested
                        ? .connection(.cancelled)
                        : .connection(.failed(error))
                    continuation.resume(throwing: connectionError)
                }
            }
        }
	}
}
