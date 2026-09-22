#if canImport(CFNetwork)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import CFNetwork
import CoreFoundation
import Dispatch

/// Apple socket streams can enable TLS on an open stream, preserving the TCP
/// connection required by VeNCrypt. This transport is intentionally separate
/// from `NWConnection`, whose parameters cannot be changed after it starts.
final class CFStreamNetworkConnection: TLSUpgradableNetworkConnection {
	let settings: NetworkConnectionSettings

	private var readStream: CFReadStream?
	private var writeStream: CFWriteStream?
	private var queue = DispatchQueue(label: "com.royalapps.royalvnc.cfstream.placeholder")
	private var didUpgradeToTLS = false

	private(set) var statusUpdateHandler: NetworkConnectionStatusUpdateHandler?
	private(set) var status: NetworkConnectionStatus = .setup {
		didSet { statusUpdateHandler?(status) }
	}

	init(settings: NetworkConnectionSettings) {
		self.settings = settings
	}

	var isReady: Bool {
		if case .ready = status { return true }
		return false
	}

	func setStatusUpdateHandler(_ statusUpdateHandler: NetworkConnectionStatusUpdateHandler?) {
		self.statusUpdateHandler = statusUpdateHandler
	}

	func start(queue: DispatchQueue) {
		self.queue = queue
		status = .preparing

		queue.async { [weak self] in
			guard let self else { return }

			var readStream: Unmanaged<CFReadStream>?
			var writeStream: Unmanaged<CFWriteStream>?
			CFStreamCreatePairWithSocketToHost(
				kCFAllocatorDefault,
				settings.host as CFString,
				UInt32(settings.port),
				&readStream,
				&writeStream
			)

			guard let read = readStream?.takeRetainedValue(),
				  let write = writeStream?.takeRetainedValue(),
				  CFReadStreamOpen(read),
				  CFWriteStreamOpen(write) else {
				self.status = .failed(VNCError.connection(.failed(nil)))
				return
			}

			self.readStream = read
			self.writeStream = write
			self.status = .ready
		}
	}

	func cancel() {
		queue.async { [weak self] in
			guard let self else { return }
			if let readStream { CFReadStreamClose(readStream) }
			if let writeStream { CFWriteStreamClose(writeStream) }
			readStream = nil
			writeStream = nil
			status = .cancelled
		}
	}

	func upgradeToTLS(serverName: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			queue.async { [weak self] in
				guard let self, let readStream, !didUpgradeToTLS else {
					continuation.resume(throwing: VNCError.protocol(.invalidData))
					return
				}

				let settings: [CFString: Any] = [
					kCFStreamSSLPeerName: serverName,
					kCFStreamSSLValidatesCertificateChain: true,
					kCFStreamSSLLevel: kCFStreamSocketSecurityLevelTLSv1_2
				]

				guard CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, settings as CFDictionary) else {
					continuation.resume(throwing: VNCError.connection(.failed(nil)))
					return
				}

				didUpgradeToTLS = true
				continuation.resume()
			}
		}
	}

	func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
		try await withCheckedThrowingContinuation { continuation in
			queue.async { [weak self] in
				guard let self, let readStream else {
					continuation.resume(throwing: VNCError.connection(.closed))
					return
				}

				var buffer = [UInt8](repeating: 0, count: maximumLength)
				let count = buffer.withUnsafeMutableBufferPointer {
					CFReadStreamRead(readStream, $0.baseAddress, maximumLength)
				}
				guard count >= minimumLength else {
					continuation.resume(throwing: VNCError.protocol(.noData))
					return
				}

				continuation.resume(returning: Data(buffer.prefix(count)))
			}
		}
	}

	func write(data: Data) async throws {
		try await withCheckedThrowingContinuation { continuation in
			queue.async { [weak self] in
				guard let self, let writeStream else {
					continuation.resume(throwing: VNCError.connection(.closed))
					return
				}

				let bytes = [UInt8](data)
				var offset = 0
				while offset < bytes.count {
					let count = bytes.withUnsafeBufferPointer {
						CFWriteStreamWrite(writeStream, $0.baseAddress?.advanced(by: offset), bytes.count - offset)
					}
					guard count > 0 else {
						continuation.resume(throwing: VNCError.connection(.failed(nil)))
						return
					}
					offset += count
				}

				continuation.resume()
			}
		}
	}
}
#endif
