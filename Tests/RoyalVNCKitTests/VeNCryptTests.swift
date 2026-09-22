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

	func testOnlyCertificateAuthenticatedVNCIsSelectedByDefault() {
		XCTAssertEqual(
			VNCProtocol.VeNCrypt.preferredAuthenticatedTLSSubtype(
				from: [.tlsNone, .tlsVNC, .x509VNC]
			),
			.x509VNC
		)
		XCTAssertNil(VNCProtocol.VeNCrypt.preferredAuthenticatedTLSSubtype(from: [.tlsNone, .tlsVNC]))
	}

	func testWritesVersionAndSubtypeInNetworkOrder() async throws {
		let connection = VeNCryptWritingConnection()

		try await VNCProtocol.VeNCrypt.sendVersion(.version0_2, connection: connection)
		try await VNCProtocol.VeNCrypt.sendSubtype(.x509VNC, connection: connection)

		XCTAssertEqual(connection.data, Data([0, 2, 0, 0, 1, 5]))
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

private final class VeNCryptWritingConnection: NetworkConnectionWriting {
	private(set) var data = Data()

	func write(data: Data) async throws {
		self.data.append(data)
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
