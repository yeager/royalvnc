#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#endif

final class Socket: Sendable {
    let addressInfo: AddressInfo

#if canImport(Glibc) || canImport(Darwin) || canImport(Android)
    private typealias NativeSocket = Int32
#elseif canImport(WinSDK)
    private typealias NativeSocket = SOCKET
#endif

    private let nativeSocket: NativeSocket

    init(addressInfo: AddressInfo) throws(Errors) {
        let nativeSocket = socket(
            addressInfo.family,
            addressInfo.socktype,
            addressInfo.protocol
        )

#if canImport(Glibc) || canImport(Darwin) || canImport(Android)
        guard nativeSocket >= 0 else {
            throw .socketCreationFailed(underlyingErrorCode: errno)
        }
#elseif canImport(WinSDK)
        guard nativeSocket != INVALID_SOCKET else {
            let lastError = WSAGetLastError()

            throw .socketCreationFailed(underlyingErrorCode: lastError)
        }
#endif

        self.addressInfo = addressInfo
        self.nativeSocket = nativeSocket
    }

    func connect() throws(Errors) {
#if canImport(Glibc)
        try enableTCPKeepAlive()
#endif

        let connectResult: Int32

#if canImport(Glibc)
        connectResult = Glibc.connect(
            nativeSocket,
            addressInfo.addr,
            addressInfo.addrlen
        )
#elseif canImport(Android)
        guard let address = addressInfo.addr else {
            throw .connectFailed(underlyingErrorCode: EINVAL)
        }
        connectResult = Android.connect(nativeSocket, address, addressInfo.addrlen)
#elseif canImport(Darwin)
        connectResult = Darwin.connect(
            nativeSocket,
            addressInfo.addr,
            addressInfo.addrlen
        )
#elseif canImport(WinSDK)
        connectResult = WinSDK.connect(
            nativeSocket,
            addressInfo.addr,
            .init(addressInfo.addrlen)
        )
#endif

        guard connectResult >= 0 else {
#if canImport(WinSDK)
            throw .connectFailed(underlyingErrorCode: WSAGetLastError())
#else
            throw .connectFailed(underlyingErrorCode: errno)
#endif
        }
    }

#if canImport(Glibc)
    /// Detects an idle peer that has disappeared without sending a TCP FIN/RST.
    private func enableTCPKeepAlive() throws(Errors) {
        var enabled: Int32 = 1
        guard Glibc.setsockopt(
            nativeSocket,
            SOL_SOCKET,
            SO_KEEPALIVE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw .socketOptionFailed(underlyingErrorCode: errno)
        }

        // Probe after 60 seconds idle, then every 10 seconds, failing after
        // three unanswered probes. Linux reports the dead connection to recv.
        let options: [(Int32, Int32)] = [
            (Int32(TCP_KEEPIDLE), 60),
            (Int32(TCP_KEEPINTVL), 10),
            (Int32(TCP_KEEPCNT), 3),
        ]

        for (option, value) in options {
            var value = value
            guard Glibc.setsockopt(
                nativeSocket,
                Int32(IPPROTO_TCP),
                option,
                &value,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0 else {
                throw .socketOptionFailed(underlyingErrorCode: errno)
            }
        }
    }
#endif

    /// Interrupts a blocking connect, receive, or send without closing the
    /// descriptor while another thread may still be using it.
    func shutdown() {
#if canImport(WinSDK)
        _ = WinSDK.shutdown(nativeSocket, SD_BOTH)
#elseif canImport(Glibc)
        _ = Glibc.shutdown(nativeSocket, Int32(SHUT_RDWR))
#elseif canImport(Darwin)
        _ = Darwin.shutdown(nativeSocket, SHUT_RDWR)
#elseif canImport(Android)
        _ = Android.shutdown(nativeSocket, Int32(SHUT_RDWR))
#endif
    }

    func receive(buffer: inout [UInt8]) throws(Errors) -> Int {
        let bufferSize = buffer.count

        let (bytesRead, errorCode): (Int, Int32?) = buffer.withUnsafeMutableBytes { bufferPtr in
            guard let bufferPtrAddr = bufferPtr.baseAddress else {
                return (0, nil)
            }

            let ret = recv(
                nativeSocket,
                bufferPtrAddr,
                .init(bufferSize),
                0
            )

            guard ret < 0 else { return (.init(ret), nil) }
#if canImport(WinSDK)
            return (-1, WSAGetLastError())
#else
            return (-1, errno)
#endif
        }

        if bytesRead < 0 {
            throw .receiveFailed(underlyingErrorCode: errorCode ?? 0)
        }
        return bytesRead
    }

    func send(buffer: [UInt8]) throws(Errors) -> Int {
        let bufferCount = buffer.count
        guard bufferCount > 0 else { return 0 }

        let (bytesSent, errorCode): (Int, Int32?) = buffer.withUnsafeBytes { bufferPtr in
            guard let bufferPtrAddr = bufferPtr.baseAddress else {
                return (-1, nil)
            }

#if canImport(Glibc)
            let ret = Glibc.send(
                nativeSocket,
                bufferPtrAddr,
                .init(bufferCount),
                0
            )
#elseif canImport(Android)
            let ret = Android.send(
                nativeSocket,
                bufferPtrAddr,
                .init(bufferCount),
                0
            )
#elseif canImport(Darwin)
            let ret = Darwin.send(
                nativeSocket,
                bufferPtrAddr,
                .init(bufferCount),
                0
            )
#elseif canImport(WinSDK)
            let ret = WinSDK.send(
                nativeSocket,
                bufferPtrAddr,
                .init(bufferCount),
                0
            )
#endif

            guard ret < 0 else { return (.init(ret), nil) }
#if canImport(WinSDK)
            return (-1, WSAGetLastError())
#else
            return (-1, errno)
#endif
        }

        if bytesSent <= 0 {
            throw .sendFailed(underlyingErrorCode: errorCode ?? 0)
        }
        return bytesSent
    }

    deinit {
#if canImport(Glibc) || canImport(Darwin) || canImport(Android)
        close(nativeSocket)
#elseif canImport(WinSDK)
        closesocket(nativeSocket)
#endif
    }
}

// MARK: - Errors
extension Socket {
    enum Errors: LocalizedError {
        case socketCreationFailed(underlyingErrorCode: Int32?)
        case socketOptionFailed(underlyingErrorCode: Int32)
        case connectFailed(underlyingErrorCode: Int32)
        case receiveFailed(underlyingErrorCode: Int32)
        case sendFailed(underlyingErrorCode: Int32)

        var errorDescription: String? {
            switch self {
                case .socketCreationFailed(let underlyingErrorCode):
                    let underlyingErrorCodeStr: String

                    if let underlyingErrorCode {
                        underlyingErrorCodeStr = "\(underlyingErrorCode)"
                    } else {
                        underlyingErrorCodeStr = "N/A"
                    }

                    return "Socket creation failed (\(underlyingErrorCodeStr))"
                case .connectFailed(let underlyingErrorCode):
                    return "Connect failed (\(underlyingErrorCode))"
                case .socketOptionFailed(let underlyingErrorCode):
                    return "Socket option setup failed (\(underlyingErrorCode))"
                case .receiveFailed(let underlyingErrorCode):
                    return "Receive failed (\(underlyingErrorCode))"
                case .sendFailed(let underlyingErrorCode):
                    return "Send failed (\(underlyingErrorCode))"
            }
        }
    }
}
