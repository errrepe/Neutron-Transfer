// Nucleon Transfer — folder-creation material (F4.2).
// Builds POST /drive/shares/{shareID}/folders requests exactly like Proton
// clients (go-proton-api CreateFolderReq + Proton-API-Bridge CreateNewFolder):
// fresh node keypair + passphrase per folder, passphrase encrypted to the
// PARENT keyring and detached-signed by the share's address key, name
// encrypted to the parent keyring and inline-signed by the address key, name
// hash = HMAC-SHA256 over the NFC name with the parent's hash key, node hash
// key = fresh random encrypted+signed to the NEW node keyring. The created
// folder is readable by our own DecryptChain (unlockNode with parent
// candidates + address signer points, decryptName with parent candidates).
import CryptoKit
import Foundation

enum FolderCreateError: Error, Sendable {
    case noParentECDHKey
    case noAddressSigningKey
    case badHashKeyLength
}

enum FolderCreate {
    /// Fresh node material: keypair + passphrase, with UnlockedKey views for
    /// recipients/candidates (idPrefix "new-node").
    struct NodeMaterial: Sendable {
        var generated: NodeKeyGen.GeneratedKey
        var passphrase: Data // raw node-passphrase bytes (base64-utf8)

        var keys: [KeyringCache.UnlockedKey] {
            [
                KeyringCache.UnlockedKey(
                    keyID: "new-node#22", algo: 22, seed: generated.edSeed,
                    fingerprint: generated.edFingerprint, kdfHash: 8, kdfCipher: 9,
                    curveOIDBody: NodeKeyGen.edOID
                ),
                KeyringCache.UnlockedKey(
                    keyID: "new-node#18", algo: 18, seed: generated.xScalarLE,
                    fingerprint: generated.xFingerprint, kdfHash: 8, kdfCipher: 7,
                    curveOIDBody: NodeKeyGen.ecdhOID
                ),
            ]
        }

        var ecdhRecipient: EncryptRecipient? {
            keys.first(where: { $0.algo == 18 }).flatMap { k in
                EncryptRecipient(
                    privateScalarLE: k.seed, fingerprint: k.fingerprint,
                    curveOIDBody: k.curveOIDBody, kdfHash: k.kdfHash, kdfCipher: k.kdfCipher
                )
            }
        }
    }

    /// Generates fresh node material (random passphrase when nil).
    static func generateNode(passphrase: Data? = nil) throws -> NodeMaterial {
        let pass = passphrase ?? NodeKeyGen.randomPassphrase()
        return NodeMaterial(generated: try NodeKeyGen.generate(passphrase: pass), passphrase: pass)
    }

    /// Builds the folder-create request plus the node material needed to read
    /// the folder back (pass `node` to reuse material, e.g. in tests).
    /// - `parentKeys`: unlocked PARENT keyring (share keys for a root child,
    ///   parent node keys below). The #18 key receives Name/NodePassphrase.
    /// - `parentHashKey`: parent folder's hash key, DECODED to 32 bytes
    ///   (the wire plaintext FolderProperties.NodeHashKey is base64-utf8 of
    ///   those 32 bytes — base64-decode after MessageDecrypt) for the name HMAC.
    /// - `addressKeys`: unlocked address keys; the #22 key signs
    ///   Name (inline) and NodePassphrase (detached).
    /// - `signatureAddress`/`signatureEmail`: signer identity. Live matrix
    ///   2026-09-30: SignatureAddress + creator email validates (2501
    ///   otherwise); SignatureEmail + email also validates.
    /// - `signArmoredPassphrase`: sign the ARMORED passphrase message instead
    ///   of the raw passphrase bytes (disproven 2026-09-30 — same 200501).
    /// - `xAttrPlaintext`: optional extended-attributes JSON, encrypted +
    ///   node-signed like NodeHashKey. Official folder creates OMIT XAttr
    ///   entirely (rclone-captured reference: 8 fields, no XAttr) — pass nil
    ///   for reference parity.
    static func buildRequest(
        name: String,
        parentLinkID: String,
        parentKeys: [KeyringCache.UnlockedKey],
        parentHashKey: Data,
        addressKeys: [KeyringCache.UnlockedKey],
        signatureAddress: String? = nil,
        signatureEmail: String? = nil,
        signArmoredPassphrase: Bool = false,
        xAttrPlaintext: Data? = nil,
        node: NodeMaterial? = nil
    ) throws -> (request: CreateFolderRequest, node: NodeMaterial) {
        guard parentHashKey.count == 32 else { throw FolderCreateError.badHashKeyLength }
        guard let parentECDH = parentKeys.first(where: { $0.algo == 18 }),
              let parentRecipient = EncryptRecipient(
                  privateScalarLE: parentECDH.seed, fingerprint: parentECDH.fingerprint,
                  curveOIDBody: parentECDH.curveOIDBody,
                  kdfHash: parentECDH.kdfHash, kdfCipher: parentECDH.kdfCipher
              )
        else {
            throw FolderCreateError.noParentECDHKey
        }
        guard let signer = addressKeys.first(where: { $0.algo == 22 }) else {
            throw FolderCreateError.noAddressSigningKey
        }
        let signerKeyID = signer.fingerprint.suffix(8)
        let material = try node ?? generateNode()
        let nfcName = name.precomposedStringWithCanonicalMapping

        let encPassphrase = try MessageEncrypt.encrypt(
            plaintext: material.passphrase, recipient: parentRecipient
        )
        let sigData = signArmoredPassphrase ? Data(encPassphrase.utf8) : material.passphrase
        // Creation signatures use SHA-256 + fresh 16-byte salts (rclone
        // parity — the proven-accepted folder-creator convention).
        let passSig = try DetachedSign.sign(
            data: sigData, signerSeedLE: signer.seed, signerKeyID: Data(signerKeyID),
            signerFingerprint: signer.fingerprint, hashAlgo: 8,
            salt: DetachedSign.freshSalt(16)
        )
        let encName = try MessageEncrypt.encryptSigned(
            plaintext: Data(nfcName.utf8), recipient: parentRecipient,
            signerSeedLE: signer.seed, signerKeyID: Data(signerKeyID),
            signerFingerprint: signer.fingerprint, hashAlgo: 8,
            salt: DetachedSign.freshSalt(16)
        )
        guard let nodeRecipient = material.ecdhRecipient else {
            throw FolderCreateError.noParentECDHKey
        }
        let nodeSignerID = material.generated.edFingerprint.suffix(8)
        // Convention (live-verified 2026-09-30: root NodeHashKey decrypts to
        // 44B base64-utf8): hash-key plaintext is base64 of 32 random bytes,
        // same as node passphrases — NOT raw bytes, or other clients that
        // base64-decode before HMAC would break interop.
        let hashSeed = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let hashToken = Data(hashSeed.base64EncodedString().utf8)
        let encHashKey = try MessageEncrypt.encryptSigned(
            plaintext: hashToken, recipient: nodeRecipient,
            signerSeedLE: material.generated.edSeed, signerKeyID: Data(nodeSignerID),
            signerFingerprint: material.generated.edFingerprint, hashAlgo: 8,
            salt: DetachedSign.freshSalt(16)
        )
        let encXAttr: String? = try xAttrPlaintext.map {
            try MessageEncrypt.encryptSigned(
                plaintext: $0, recipient: nodeRecipient,
                signerSeedLE: material.generated.edSeed, signerKeyID: Data(nodeSignerID),
                signerFingerprint: material.generated.edFingerprint, hashAlgo: 8,
                salt: DetachedSign.freshSalt(16)
            )
        }
        let request = CreateFolderRequest(
            parentLinkID: parentLinkID, // filled by DriveClient.createFolder
            name: encName,
            hash: NameHash.hex(name: nfcName, hashKey: parentHashKey),
            nodeKey: material.generated.armoredKey,
            nodeHashKey: encHashKey,
            nodePassphrase: encPassphrase,
            nodePassphraseSignature: passSig,
            signatureAddress: signatureAddress,
            signatureEmail: signatureEmail,
            xAttr: encXAttr
        )
        return (request, material)
    }
}

/// Link-name hash: hex(HMAC-SHA256(key: parentHashKey, msg: name)).
/// Parity source: henrybear327/go-proton-api GetNameHash (+ vectors).
enum NameHash {
    static func hex(name: String, hashKey: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(name.utf8), using: SymmetricKey(data: hashKey)
        )
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
