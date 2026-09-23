#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public extension VNCConnection {
    /// True only when the Tight handshake advertised file list, download and
    /// upload messages in the directions required by this client.
    var canTransferFiles: Bool { supportsTightFileTransfer }

    func requestFileList(directory: String) throws {
        try enqueueFileTransfer(try TightFileTransfer.fileListRequest(directory: directory))
    }

    func requestFileDownload(path: String, offset: UInt32 = 0) throws {
        try enqueueFileTransfer(try TightFileTransfer.downloadRequest(path: path, offset: offset))
    }

    func requestFileUpload(path: String, offset: UInt32 = 0) throws {
        try enqueueFileTransfer(try TightFileTransfer.uploadRequest(path: path, offset: offset))
    }

    func sendFileUploadData(_ data: Data) throws {
        try enqueueFileTransfer(try TightFileTransfer.uploadData(data))
    }

    func finishFileUpload(modificationTime: UInt32) throws {
        try enqueueFileTransfer(try TightFileTransfer.uploadData(Data(), endModificationTime: modificationTime))
    }

    private func enqueueFileTransfer(_ data: Data) throws {
        guard canTransferFiles else {
            throw VNCError.protocol(.notImplemented(feature: "TightVNC file transfer"))
        }
        guard connectionState.status == .connected else {
            throw VNCError.connection(.notReady)
        }
        enqueueClientToServerMessage(VNCProtocol.TightFileTransferMessage(data: data))
    }
}
