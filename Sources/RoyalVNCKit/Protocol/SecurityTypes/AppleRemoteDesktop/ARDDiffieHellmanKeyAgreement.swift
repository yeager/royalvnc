#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension VNCProtocol.ARDAuthentication {
	struct DiffieHellmanKeyAgreement {
		let publicKey: Data
		let privateKey: Data
		let secretKey: Data

		init?(prime: Data,
			  generator: Data,
			  peerKey: Data,
			  keyLength: Int) {
			guard Self.hasValidParameters(prime: prime,
										  generator: generator,
										  peerKey: peerKey,
										  keyLength: keyLength) else {
				return nil
			}

			guard let keyPair = Self.generateKeyPair(generator: generator,
													 prime: prime,
													 keyLength: keyLength),
				  !keyPair.privateKey.isEmpty,
				  !keyPair.publicKey.isEmpty else {
				return nil
			}

			guard let secretKey = Self.computeSharedKey(prime: prime,
														peerKey: peerKey,
														privateKey: keyPair.privateKey,
														keyLength: keyLength),
				  !secretKey.isEmpty else {
				return nil
			}

			self.publicKey = keyPair.publicKey
			self.privateKey = keyPair.privateKey
			self.secretKey = secretKey
		}
	}
}

extension VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement {
	static func hasValidParameters(prime: Data,
								   generator: Data,
								   peerKey: Data,
								   keyLength: Int) -> Bool {
		guard keyLength > 0,
			  keyLength <= VNCProtocol.ARDAuthentication.maximumKeyLength,
			  prime.count == keyLength,
			  peerKey.count == keyLength,
			  !generator.isEmpty,
			  prime.last.map({ $0 & 1 == 1 }) == true,
			  let bigPrime = BigNum(data: prime),
			  !bigPrime.isLessThan(5),
			  let primeMinusOne = bigPrime.subtracting(1),
			  let bigGenerator = BigNum(data: generator),
			  !bigGenerator.isLessThan(2),
			  bigGenerator.isLessThan(primeMinusOne),
			  let bigPeerKey = BigNum(data: peerKey),
			  !bigPeerKey.isLessThan(2),
			  bigPeerKey.isLessThan(primeMinusOne) else {
			return false
		}

		return true
	}
}

private extension VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement {
	struct KeyPair {
		let publicKey: Data
		let privateKey: Data
	}

	static func generateKeyPair(generator: Data,
								prime: Data,
								keyLength: Int) -> KeyPair? {
		let bigPrivKey = BigNum()
		let bigPubKey = BigNum()

		guard let bigPrime = BigNum(data: prime),
			  let bigGenerator = BigNum(data: generator) else {
			return nil
		}

		// Generate DH private key
		repeat {
			let randSuccess = bigPrivKey.rand(range: bigPrime)

			guard randSuccess else {
				return nil
			}
		} while bigPrivKey.isZero

		let modSuccess = BigNum.modExp(y: bigPubKey,
									   g: bigGenerator,
									   x: bigPrivKey,
									   p: bigPrime)

		guard modSuccess else {
			return nil
		}

		guard let privKey = bigPrivKey.fixedWidthBigEndianData(length: keyLength),
			  let pubKey = bigPubKey.fixedWidthBigEndianData(length: keyLength) else {
			return nil
		}

		let keyPair = KeyPair(publicKey: pubKey,
							  privateKey: privKey)

		return keyPair
	}

	static func computeSharedKey(prime: Data,
								 peerKey: Data,
							 privateKey: Data,
							 keyLength: Int) -> Data? {
		guard let bigPrime = BigNum(data: prime),
			  let bigPrivKey = BigNum(data: privateKey),
			  let bigPeerKey = BigNum(data: peerKey) else {
			return nil
		}

		let bigSharedKey = BigNum()

		let modSuccess = BigNum.modExp(y: bigSharedKey,
									   g: bigPeerKey,
									   x: bigPrivKey,
									   p: bigPrime)

		guard modSuccess else {
			return nil
		}

		guard let sharedKey = bigSharedKey.fixedWidthBigEndianData(length: keyLength) else {
			return nil
		}

		return sharedKey
	}
}
