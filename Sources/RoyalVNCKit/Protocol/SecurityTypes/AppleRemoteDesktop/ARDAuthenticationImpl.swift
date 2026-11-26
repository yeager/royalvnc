#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Security)
import Security
#endif

extension VNCProtocol.ARDAuthentication {
    struct Authentication {
        let cipherText: Data
        let publicKey: Data

        private init(cipherText: Data,
                     publicKey: Data) {
            self.cipherText = cipherText
            self.publicKey = publicKey
        }

        init?(agreement: DiffieHellmanKeyAgreement,
              username: String,
              password: String) {
            // Get MD5 hash of shared secret
			let secretHash = agreement.secretKey.md5Hash()

            // ciphertext: AES128(shared, username[64]:password[64])
            let credArraySize = 128
            var creds = Data(count: credArraySize)

            let randomCredsDataSuccess = creds.withUnsafeMutableBytes {
                guard let credsBytes = $0.baseAddress else { return false }

#if canImport(Security)
				let randomStatus = SecRandomCopyBytes(kSecRandomDefault, credArraySize, credsBytes)

                guard randomStatus == errSecSuccess else { return false }
#else
				// TODO: Probably not secure
				for i in 0..<credArraySize {
					$0[i] = UInt8.random(in: 0...255)
				}
#endif

                return true
            }

            guard randomCredsDataSuccess else { return nil }

			let usernameBytes = Data(username.utf8)
			let passwordBytes = Data(password.utf8)
			let fieldLength = credArraySize / 2
			let maximumValueLength = fieldLength - 1

			guard usernameBytes.count <= maximumValueLength,
				  passwordBytes.count <= maximumValueLength,
				  !usernameBytes.contains(0),
				  !passwordBytes.contains(0) else {
				return nil
			}

			creds.replaceSubrange(0..<usernameBytes.count, with: usernameBytes)
			creds.replaceSubrange(fieldLength..<(fieldLength + passwordBytes.count),
							  with: passwordBytes)

			// Add null bytes to indicate the end of each C string.
			creds[usernameBytes.count] = 0
			creds[fieldLength + passwordBytes.count] = 0

			guard let cipherText = creds.aes128ECBEncrypted(withKey: secretHash) else {
				return nil
			}

            self.init(cipherText: cipherText,
                      publicKey: agreement.publicKey)
        }
    }
}
