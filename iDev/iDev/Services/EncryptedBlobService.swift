import Foundation
import CryptoKit

/// Encrypts and decrypts data blobs for export/import and BYO sync.
///
/// Blob format (version 1):
///   4-byte magic "iDEV"
///   1-byte version
///   16-byte PBKDF2 salt
///   12-byte AES-GCM nonce
///   N-byte ciphertext
///   16-byte AES-GCM tag (appended by SealedBox)
///
/// Key derivation: PBKDF2-HMAC-SHA256, 600 000 iterations, 32-byte key.
nonisolated final class EncryptedBlobService: Sendable {
    private static let magic: [UInt8] = [0x69, 0x44, 0x45, 0x56] // "iDEV"
    private static let version: UInt8 = 1
    private static let saltLength = 16
    private static let pbkdf2Iterations = 600_000
    private static let headerLength = 4 + 1 + saltLength + 12 // magic + version + salt + nonce

    func encrypt(data: Data, password: String) throws -> Data {
        let salt = generateRandomBytes(count: Self.saltLength)
        let key = try deriveKey(password: password, salt: salt)
        let nonce = AES.GCM.Nonce()

        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        var blob = Data(Self.magic)
        blob.append(Self.version)
        blob.append(contentsOf: salt)
        blob.append(contentsOf: nonce)
        blob.append(sealedBox.ciphertext)
        blob.append(sealedBox.tag)

        return blob
    }

    func decrypt(blob: Data, password: String) throws -> Data {
        guard blob.count > Self.headerLength + 16 else {
            throw BlobError.invalidFormat
        }

        // Verify magic bytes
        let magicSlice = [UInt8](blob[0..<4])
        guard magicSlice == Self.magic else {
            throw BlobError.invalidMagic
        }

        let blobVersion = blob[4]
        guard blobVersion == Self.version else {
            throw BlobError.unsupportedVersion(blobVersion)
        }

        let salt = [UInt8](blob[5..<21])
        let nonceBytes = [UInt8](blob[21..<33])
        let ciphertextAndTag = blob[33...]

        guard ciphertextAndTag.count >= 16 else {
            throw BlobError.invalidFormat
        }

        let ciphertext = ciphertextAndTag[ciphertextAndTag.startIndex..<ciphertextAndTag.endIndex - 16]
        let tag = ciphertextAndTag[ciphertextAndTag.endIndex - 16..<ciphertextAndTag.endIndex]

        let key = try deriveKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)

        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Key Derivation

    private func deriveKey(password: String, salt: [UInt8]) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            throw BlobError.emptyPassword
        }
        let derivedKey = pbkdf2SHA256(
            password: passwordData,
            salt: Data(salt),
            iterations: Self.pbkdf2Iterations,
            keyLength: 32
        )
        return SymmetricKey(data: derivedKey)
    }

    /// PBKDF2-HMAC-SHA256 implemented with CryptoKit HMAC.
    private func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        let blockCount = (keyLength + 31) / 32
        var derivedKey = Data()

        for blockIndex in 1...blockCount {
            let blockIndexBytes = withUnsafeBytes(of: UInt32(blockIndex).bigEndian) { Data($0) }
            let initialInput = salt + blockIndexBytes

            // U1 = HMAC(password, salt || blockIndex)
            var u = hmacSHA256(key: password, data: initialInput)
            var result = u

            for _ in 1..<iterations {
                u = hmacSHA256(key: password, data: u)
                for i in 0..<result.count {
                    result[i] ^= u[i]
                }
            }

            derivedKey.append(result)
        }

        return Data(derivedKey.prefix(keyLength))
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }

    private func generateRandomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }
}

// MARK: - Errors

nonisolated enum BlobError: Error, LocalizedError, Sendable {
    case invalidFormat
    case invalidMagic
    case unsupportedVersion(UInt8)
    case emptyPassword
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "Invalid blob format"
        case .invalidMagic: "Not an iDev backup file"
        case .unsupportedVersion(let v): "Unsupported blob version: \(v)"
        case .emptyPassword: "Password cannot be empty"
        case .decryptionFailed: "Decryption failed — wrong password?"
        }
    }
}
