import Foundation
import XCTest

@testable import RoyalVNCKit

final class VeNCryptTests: XCTestCase {
	func testReadsVersionAndTLSSubtypeList() async throws {
		let connection = VeNCryptReadingConnection(data: Data([
			0, 2, // VeNCrypt 0.2
			2, // two subtypes
			0, 0, 1, 2, // TLSVnc
			0, 0, 1, 9 // Ident
		]))

		let version = try await VNCProtocol.VeNCrypt.receiveVersion(connection: connection)
		let subtypes = try await VNCProtocol.VeNCrypt.receiveSubtypes(connection: connection)

		XCTAssertEqual(version, VNCProtocol.VeNCrypt.Version.version0_2)
		XCTAssertEqual(subtypes, [VNCProtocol.VeNCrypt.Subtype.tlsVNC, .ident])
		XCTAssertTrue(subtypes[0].requiresTLS)
		XCTAssertFalse(subtypes[1].requiresTLS)
	}

	func testRejectsUnexpectedAcknowledgements() async throws {
		let versionConnection = VeNCryptReadingConnection(data: Data([1]))
		let subtypeConnection = VeNCryptReadingConnection(data: Data([0]))

		await XCTAssertThrowsErrorAsync {
			try await VNCProtocol.VeNCrypt.receiveVersionAcknowledgement(connection: versionConnection)
		}
		await XCTAssertThrowsErrorAsync {
			try await VNCProtocol.VeNCrypt.receiveTLSSubtypeAcknowledgement(connection: subtypeConnection)
		}
	}
}

private final class VeNCryptReadingConnection: NetworkConnectionReading {
	private var remaining: Data

	init(data: Data) {
		remaining = data
	}

	func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
		guard remaining.count >= minimumLength else {
			throw VNCError.protocol(.invalidData)
		}

		let count = min(remaining.count, maximumLength)
		let result = remaining.prefix(count)
		remaining.removeFirst(count)
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
			XCTFail("Expected an error", file: file, line: line)
		} catch {
			// Expected.
		}
	}
}
