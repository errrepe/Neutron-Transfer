// Nucleon Transfer — F5 offline download suite (Swift Testing).
// No network, no secrets: encrypt via FileUpload, then verify + decrypt +
// reassemble through the FileDownload path (proves byte-identity, hash
// enforcement, ordering, and destination planning).
import CryptoKit
import Foundation
import Testing

@testable import NeutronTransfer

struct FileDownloadTests {
    @Test func roundtripSingleBlockByteIdentical() throws {
        let data = Data("hello neutron f5 fixture".utf8)
        let back = try FileDownload.roundtrip(data: data, blockSize: 4 * 1024 * 1024)
        #expect(back == data)
    }

    @Test func roundtripMultiBlockOutOfOrder() throws {
        // 10 bytes at 4B blocks → 4+4+2, reassembled from reversed order.
        let data = Data("0123456789".utf8)
        let back = try FileDownload.roundtrip(data: data, blockSize: 4)
        #expect(back == data)
        let chunks = FileUpload.splitBlocks(data, blockSize: 4)
        #expect(chunks.count == 3)
        #expect(chunks.map(\.count) == [4, 4, 2])
    }

    @Test func roundtripEmptyIsEmpty() throws {
        #expect(try FileDownload.roundtrip(data: Data()) == Data())
        #expect(try FileDownload.reassemble(blocks: [], contentKey: Data(repeating: 0, count: 32)) == Data())
    }

    @Test func hashMismatchFailsClosed() throws {
        let key = Data((0..<32).map { UInt8($0) })
        let enc = try FileUpload.encryptBlock(Data("abc".utf8), contentKey: key)
        let goodHash = try FileUpload.blockHash(enc).base64EncodedString()
        // Good verifies.
        try FileDownload.verifyBlock(FileDownload.FetchedBlock(
            index: 1, encrypted: enc, expectedHashB64: goodHash
        ))
        // Tampered bytes fail.
        var tampered = enc
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        do {
            _ = try FileDownload.reassemble(
                blocks: [FileDownload.FetchedBlock(
                    index: 1, encrypted: tampered, expectedHashB64: goodHash
                )],
                contentKey: key
            )
            Issue.record("tampered block accepted")
        } catch let e as FileDownloadError {
            #expect(e == .hashMismatch(index: 1))
        }
        // Bad base64 fails loudly.
        do {
            try FileDownload.verifyBlock(FileDownload.FetchedBlock(
                index: 1, encrypted: enc, expectedHashB64: "!!!"
            ))
            Issue.record("bad hash accepted")
        } catch let e as FileDownloadError {
            #expect(e == .badBlockHash("!!!"))
        }
    }

    @Test func blockIndexGapFails() throws {
        let key = Data((0..<32).map { UInt8($0) })
        let enc = try FileUpload.encryptBlock(Data("x".utf8), contentKey: key)
        let h = try FileUpload.blockHash(enc).base64EncodedString()
        let blocks = [
            FileDownload.FetchedBlock(index: 1, encrypted: enc, expectedHashB64: h),
            FileDownload.FetchedBlock(index: 3, encrypted: enc, expectedHashB64: h),
        ]
        do {
            _ = try FileDownload.reassemble(blocks: blocks, contentKey: key)
            Issue.record("gapped index accepted")
        } catch let e as FileDownloadError {
            #expect(e == .blockIndexGap)
        }
    }

    @Test func wrongContentKeyFails() throws {
        let key = Data((0..<32).map { UInt8($0) })
        let other = Data((0..<32).map { UInt8(0xFF - $0) })
        let enc = try FileUpload.encryptBlock(Data("secret".utf8), contentKey: key)
        let h = try FileUpload.blockHash(enc).base64EncodedString()
        do {
            _ = try FileDownload.reassemble(
                blocks: [FileDownload.FetchedBlock(
                    index: 1, encrypted: enc, expectedHashB64: h
                )],
                contentKey: other
            )
            Issue.record("wrong key accepted")
        } catch { /* expected: MDC mismatch from SEDDecrypt */ }
    }

    @Test func uniqueDestinationSuffixes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntf5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FileDownload.uniqueDestination(in: dir, name: "a.txt").lastPathComponent == "a.txt")
        try Data("1".utf8).write(to: dir.appendingPathComponent("a.txt"))
        #expect(FileDownload.uniqueDestination(in: dir, name: "a.txt").lastPathComponent == "a (1).txt")
        try Data("2".utf8).write(to: dir.appendingPathComponent("a (1).txt"))
        #expect(FileDownload.uniqueDestination(in: dir, name: "a.txt").lastPathComponent == "a (2).txt")
        // Extensionless names suffix cleanly.
        try Data("x".utf8).write(to: dir.appendingPathComponent("README"))
        #expect(FileDownload.uniqueDestination(in: dir, name: "README").lastPathComponent == "README (1)")
    }

    @Test func atomicWriteRoundtrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntf5w-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("sub/dir/out.bin")
        let data = Data((0..<1024).map { UInt8($0 & 0xFF) })
        try FileDownload.atomicWrite(data, to: dest)
        #expect(try Data(contentsOf: dest) == data)
        #expect(!FileManager.default.fileExists(
            atPath: dest.appendingPathExtension("nucleon-part").path
        ))
    }

    @Test func fixtureScale77ByteRule() throws {
        // The live 26B fixture encrypts to exactly 77B (plaintext + 51):
        // download Size == encrypted length, Hash == sha256(ciphertext).
        let key = Data((0..<32).map { UInt8($0) })
        let plain = Data("12345678901234567890123456".utf8)
        #expect(plain.count == 26)
        let enc = try FileUpload.encryptBlock(plain, contentKey: key)
        #expect(enc.count == 77)
        let hash = try FileUpload.blockHash(enc)
        #expect(hash == Data(SHA256.hash(data: enc)))
        let back = try FileDownload.reassemble(
            blocks: [FileDownload.FetchedBlock(
                index: 1, encrypted: enc,
                expectedHashB64: hash.base64EncodedString()
            )],
            contentKey: key
        )
        #expect(back == plain)
    }
}
