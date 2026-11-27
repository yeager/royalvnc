#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Dispatch

// TODO: All of this is very hacky and NOT fully fleshed out!
final class SocketNetworkConnection: NetworkConnection {
    let settings: NetworkConnectionSettings

    private var socket: Socket?

    // This will be replaced when calling start. Calling any other method before start (which would use this placeholder queue) is a programmer error.
    private var queue = DispatchQueue(label: "PLACEHOLDER")

    private(set) var statusUpdateHandler: NetworkConnectionStatusUpdateHandler?

    private(set) var status: NetworkConnectionStatus = .unknown("None") {
        didSet {
            statusUpdateHandler?(status)
        }
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
        self.statusUpdateHandler = statusUpdateHandler
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
        // TODO
        // fatalError("Not implemented")
    }

    func start(queue: DispatchQueue) {
        self.status = .preparing
        self.queue = queue

        queue.async { [weak self] in
            guard let self else { return }

            do {
                let addressInfo = try AddressInfo(host: settings.host,
                                                               port: settings.port)

                let socket = try Socket(addressInfo: addressInfo)

                try socket.connect()

                self.socket = socket
                self.status = .ready
            } catch {
                self.status = .failed(error)
            }
        }
    }
}

// MARK: - Reading
extension SocketNetworkConnection: NetworkConnectionReading {
	func read(minimumLength: Int,
              maximumLength: Int) async throws -> Data {
        let queue = self.queue

        guard let socket else {
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
                    continuation.resume(throwing: VNCError.connection(.failed(error)))
                    return
                }

                // Handle connection closure
                if bytesRead == 0 {
                    // TODO
                    continuation.resume(throwing: VNCError.connection(.closed))

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

        guard let socket else {
            throw VNCError.connection(.notReady)
        }

		return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let bytesToSend = [UInt8](data)
                do {
                    _ = try socket.send(buffer: bytesToSend)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: VNCError.connection(.failed(error)))
                }
            }
        }
	}
}
