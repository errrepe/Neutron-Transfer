// Neutron Transfer — Drive read models.
// Shapes mirror rclone/go-proton-api share_types.go, volume_types.go and
// ProtonMail/go-proton-api link_types.go (default encoding/json => keys are
// the capitalized Go field names). IDs and names are encrypted blobs here;
// decryption lands in F3b (key hierarchy unlock).
import Foundation

// MARK: - Volumes

struct Volume: Decodable, Sendable {
    var volumeID: String
    var creationTime: Int64
    var modifyTime: Int64
    var maxSpace: Int64?
    var usedSpace: Int64
    var downloadedBytes: Int64
    var uploadedBytes: Int64
    var state: Int
    var share: VolumeShare
    var restoreStatus: Int?

    enum CodingKeys: String, CodingKey {
        case volumeID = "VolumeID"
        case creationTime = "CreationTime"
        case modifyTime = "ModifyTime"
        case maxSpace = "MaxSpace"
        case usedSpace = "UsedSpace"
        case downloadedBytes = "DownloadedBytes"
        case uploadedBytes = "UploadedBytes"
        case state = "State"
        case share = "Share"
        case restoreStatus = "RestoreStatus"
    }
}

struct VolumeShare: Decodable, Sendable {
    var shareID: String
    var linkID: String
    enum CodingKeys: String, CodingKey {
        case shareID = "ShareID"
        case linkID = "LinkID"
    }
}

struct VolumesResponse: Decodable, Sendable {
    var volumes: [Volume]
    enum CodingKeys: String, CodingKey { case volumes = "Volumes" }
}

// MARK: - Shares

struct ShareMetadata: Decodable, Sendable {
    var shareID: String
    var linkID: String
    var volumeID: String
    var type: Int
    var state: Int
    var creationTime: Int64
    var modifyTime: Int64
    var creator: String?
    var flags: Int?
    var locked: Bool?
    var volumeSoftDeleted: Bool?

    enum CodingKeys: String, CodingKey {
        case shareID = "ShareID"
        case linkID = "LinkID"
        case volumeID = "VolumeID"
        case type = "Type"
        case state = "State"
        case creationTime = "CreationTime"
        case modifyTime = "ModifyTime"
        case creator = "Creator"
        case flags = "Flags"
        case locked = "Locked"
        case volumeSoftDeleted = "VolumeSoftDeleted"
    }
}

struct DriveShare: Decodable, Sendable {
    var shareID: String
    var linkID: String
    var volumeID: String
    var type: Int
    var state: Int
    var addressID: String?
    var addressKeyID: String?
    var key: String?
    var passphrase: String?
    var passphraseSignature: String?

    enum CodingKeys: String, CodingKey {
        case shareID = "ShareID"
        case linkID = "LinkID"
        case volumeID = "VolumeID"
        case type = "Type"
        case state = "State"
        case addressID = "AddressID"
        case addressKeyID = "AddressKeyID"
        case key = "Key"
        case passphrase = "Passphrase"
        case passphraseSignature = "PassphraseSignature"
    }
}

struct SharesResponse: Decodable, Sendable {
    var shares: [ShareMetadata]
    enum CodingKeys: String, CodingKey { case shares = "Shares" }
}

struct ShareResponse: Decodable, Sendable {
    var share: DriveShare
    enum CodingKeys: String, CodingKey { case share = "Share" }
}

// MARK: - Links

/// A file or folder node. Name/IDs are encrypted until F3b unlock.
struct DriveLink: Decodable, Sendable, Identifiable {
    var id: String { linkID }
    var linkID: String
    var parentLinkID: String?
    /// 1 = folder, 2 = file (go-proton-api LinkTypeFolder/File).
    var type: Int
    /// Encrypted name (armored PGP). Hash is the encrypted name HMAC.
    var name: String
    var hash: String?
    var size: Int64
    /// 0 draft, 1 active, 2 trashed, 3 deleted, 4 restoring.
    var state: Int
    var mimeType: String?
    var createTime: Int64
    var modifyTime: Int64
    var expirationTime: Int64?
    var nodeKey: String?
    var nodePassphrase: String?
    var nodePassphraseSignature: String?
    var fileProperties: FileProperties?
    var folderProperties: FolderProperties?

    var isFolder: Bool { type == 1 }
    var isActive: Bool { state == 1 }

    enum CodingKeys: String, CodingKey {
        case linkID = "LinkID"
        case parentLinkID = "ParentLinkID"
        case type = "Type"
        case name = "Name"
        case hash = "Hash"
        case size = "Size"
        case state = "State"
        case mimeType = "MIMEType"
        case createTime = "CreateTime"
        case modifyTime = "ModifyTime"
        case expirationTime = "ExpirationTime"
        case nodeKey = "NodeKey"
        case nodePassphrase = "NodePassphrase"
        case nodePassphraseSignature = "NodePassphraseSignature"
        case fileProperties = "FileProperties"
        case folderProperties = "FolderProperties"
    }
}

struct FileProperties: Decodable, Sendable {
    var contentKeyPacket: String?
    var contentKeyPacketSignature: String?
    var activeRevision: RevisionMetadata?

    enum CodingKeys: String, CodingKey {
        case contentKeyPacket = "ContentKeyPacket"
        case contentKeyPacketSignature = "ContentKeyPacketSignature"
        case activeRevision = "ActiveRevision"
    }
}

struct FolderProperties: Decodable, Sendable {
    var nodeHashKey: String?
    enum CodingKeys: String, CodingKey { case nodeHashKey = "NodeHashKey" }
}

struct RevisionMetadata: Decodable, Sendable {
    var id: String?
    var createTime: Int64?
    var size: Int64?
    var manifestSignature: String?
    var signatureEmail: String?
    var state: Int?
    var thumbnail: Bool?
    var thumbnailHash: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case createTime = "CreateTime"
        case size = "Size"
        case manifestSignature = "ManifestSignature"
        case signatureEmail = "SignatureEmail"
        case state = "State"
        case thumbnail = "Thumbnail"
        case thumbnailHash = "ThumbnailHash"
    }
}

struct LinkResponse: Decodable, Sendable {
    var link: DriveLink
    enum CodingKeys: String, CodingKey { case link = "Link" }
}

struct LinksResponse: Decodable, Sendable {
    var links: [DriveLink]
    enum CodingKeys: String, CodingKey { case links = "Links" }
}
