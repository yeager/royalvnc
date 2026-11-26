import Foundation
import XCTest

@testable import RoyalVNCKit

final class ARDAuthenticationTests: XCTestCase {
	func testRejectsOversizedKeyBeforeReadingParameterArrays() async throws {
		let connection = ARDReadingConnection(data: Data([1, 1, 2, 1]))

		await XCTAssertThrowsErrorAsync {
			_ = try await VNCProtocol.ARDAuthentication.receive(connection: connection)
		}

		XCTAssertEqual(connection.bytesRead, 4)
	}

	func testRejectsInvalidDiffieHellmanParameters() {
		let validPrime = Data([23])
		let validGenerator = Data([5])
		let validPeerKey = Data([8])

		XCTAssertTrue(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement.hasValidParameters(
			prime: validPrime,
			generator: validGenerator,
			peerKey: validPeerKey,
			keyLength: 1
		))
		XCTAssertFalse(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement.hasValidParameters(
			prime: Data([22]),
			generator: validGenerator,
			peerKey: validPeerKey,
			keyLength: 1
		))
		XCTAssertFalse(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement.hasValidParameters(
			prime: validPrime,
			generator: Data([1]),
			peerKey: validPeerKey,
			keyLength: 1
		))
		XCTAssertFalse(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement.hasValidParameters(
			prime: validPrime,
			generator: Data([5]),
			peerKey: Data([1]),
			keyLength: 1
		))
		XCTAssertFalse(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement.hasValidParameters(
			prime: validPrime,
			generator: validGenerator,
			peerKey: validPeerKey,
			keyLength: VNCProtocol.ARDAuthentication.maximumKeyLength + 1
		))
	}
}

private final class ARDReadingConnection: NetworkConnectionReading {
	private var remaining: Data
	private(set) var bytesRead = 0

	init(data: Data) {
		remaining = data
	}

	func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
		guard remaining.count >= minimumLength else {
			throw VNCError.protocol(.invalidData)
		}

		let count = min(remaining.count, maximumLength)
		let result = Data(remaining.prefix(count))
		remaining.removeFirst(count)
		bytesRead += count
		return result
	}
}

private extension XCTestCase {
	func XCTAssertThrowsErrorAsync(
		_ expression: @escaping () async throws -> Void,
		file: StaticString = #filePath,
		line: UInt = #line
	) async {
		do {
			try await expression()
			XCTFail("Expected expression to throw", file: file, line: line)
		} catch {
			// Expected.
		}
	}
}
