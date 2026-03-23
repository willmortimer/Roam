import Testing
import Foundation
@testable import iDev

@Suite("EncryptedBlobService")
struct EncryptedBlobServiceTests {
    let service = EncryptedBlobService()

    @Test("Encrypt and decrypt round-trip")
    func roundTrip() throws {
        let original = "Hello, iDev!".data(using: .utf8)!
        let encrypted = try service.encrypt(data: original, password: "test-password")
        let decrypted = try service.decrypt(blob: encrypted, password: "test-password")
        #expect(decrypted == original)
    }

    @Test("Round-trip with large data")
    func largeRoundTrip() throws {
        let original = Data(repeating: 0xAB, count: 1_000_000)
        let encrypted = try service.encrypt(data: original, password: "p@ssw0rd!")
        let decrypted = try service.decrypt(blob: encrypted, password: "p@ssw0rd!")
        #expect(decrypted == original)
    }

    @Test("Round-trip with empty data")
    func emptyData() throws {
        let original = Data()
        let encrypted = try service.encrypt(data: original, password: "pw")
        let decrypted = try service.decrypt(blob: encrypted, password: "pw")
        #expect(decrypted == original)
    }

    @Test("Wrong password fails decryption")
    func wrongPassword() throws {
        let original = "secret".data(using: .utf8)!
        let encrypted = try service.encrypt(data: original, password: "correct")
        #expect(throws: (any Error).self) {
            _ = try service.decrypt(blob: encrypted, password: "wrong")
        }
    }

    @Test("Empty password throws")
    func emptyPassword() {
        #expect(throws: BlobError.self) {
            _ = try service.encrypt(data: Data([1, 2, 3]), password: "")
        }
    }

    @Test("Invalid magic bytes throw")
    func invalidMagic() {
        let badBlob = Data([0x00, 0x00, 0x00, 0x00]) + Data(repeating: 0, count: 60)
        #expect(throws: BlobError.self) {
            _ = try service.decrypt(blob: badBlob, password: "pw")
        }
    }

    @Test("Truncated blob throws")
    func truncatedBlob() {
        let shortBlob = Data([0x69, 0x44, 0x45, 0x56, 0x01]) // magic + version only
        #expect(throws: BlobError.self) {
            _ = try service.decrypt(blob: shortBlob, password: "pw")
        }
    }

    @Test("Unsupported version throws")
    func unsupportedVersion() {
        // Valid magic, bad version (99), then enough padding
        var blob = Data([0x69, 0x44, 0x45, 0x56, 99])
        blob.append(Data(repeating: 0, count: 60))
        #expect(throws: BlobError.self) {
            _ = try service.decrypt(blob: blob, password: "pw")
        }
    }

    @Test("Different encryptions of same data produce different blobs")
    func uniqueEncryptions() throws {
        let data = "same data".data(using: .utf8)!
        let enc1 = try service.encrypt(data: data, password: "pw")
        let enc2 = try service.encrypt(data: data, password: "pw")
        #expect(enc1 != enc2) // different salt + nonce each time
    }

    @Test("Blob starts with iDEV magic bytes")
    func magicHeader() throws {
        let encrypted = try service.encrypt(data: Data([1]), password: "pw")
        #expect(encrypted[0] == 0x69) // 'i'
        #expect(encrypted[1] == 0x44) // 'D'
        #expect(encrypted[2] == 0x45) // 'E'
        #expect(encrypted[3] == 0x56) // 'V'
        #expect(encrypted[4] == 1)    // version
    }
}
