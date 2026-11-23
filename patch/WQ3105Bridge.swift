// WQFiles Patch bridge for the open-source 3105 package schema v1-v3.
// Implements import/decode only; modifications and rollback live in WQPatch.m.
// References: YangJiiii/3105 PatchPackageCodec.swift (GPL compatible usage).
import Foundation
import CryptoKit
import CommonCrypto
import Darwin

private struct Envelope: Decodable {
    let schemaVersion: Int
    let keyAADVersion: Int?
    let packageID: UUID
    let isPasswordProtected: Bool
    let kdfSalt: Data?
    let kdfIterations: Int?
    let wrappedContentKey: Data?
    let publicContentKey: Data?
    let keyFingerprint: Data
    let encryptedPayload: Data
}
private struct Rule: Decodable {
    let id: UUID
    let bundleID: String
    let relativePath: String
    let replacementFilename: String
    let replacementData: Data
}
private struct Project: Decodable {
    let id: UUID
    let name: String
    let rules: [Rule]
}
private struct Payload: Decodable {
    let project: Project
    let replacementDigests: [String: Data]
}
private enum ImportError: Error {
    case invalid(String)
}
private func open(_ combined: Data, key: Data, aad: String) throws -> Data {
    guard key.count == 32 else { throw ImportError.invalid("invalid key size") }
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(aad.utf8))
}
private func derive(_ password: String, salt: Data, iterations: Int) throws -> Data {
    guard salt.count == 16 && (10000...10000000).contains(iterations) else {
        throw ImportError.invalid("invalid password parameters")
    }
    var output = Data(count: 32)
    let passwordData = Data(password.utf8)
    let result = output.withUnsafeMutableBytes { out in
        passwordData.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    pass.bindMemory(to: Int8.self).baseAddress, passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                    out.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
    }
    guard result == kCCSuccess else { throw ImportError.invalid("key derivation failed") }
    return output
}
private func decode(_ data: Data, password: String?) throws -> [String: Any] {
    let magic = Data("3105PATCH\0".utf8)
    guard data.starts(with: magic) else { throw ImportError.invalid("not a 3105 file") }
    let envelope = try PropertyListDecoder().decode(Envelope.self, from: data.dropFirst(magic.count))
    guard (1...3).contains(envelope.schemaVersion) else {
        throw ImportError.invalid("unsupported 3105 schema v\(envelope.schemaVersion) (supports v1-v3)")
    }
    let uuid = envelope.packageID.uuidString
    let key: Data
    if envelope.isPasswordProtected {
        guard let password, !password.isEmpty,
              let salt = envelope.kdfSalt, let iterations = envelope.kdfIterations,
              let wrapped = envelope.wrappedContentKey else {
            throw ImportError.invalid("password_required")
        }
        let wrappingKey = try derive(password, salt: salt, iterations: iterations)
        let v = envelope.keyAADVersion ?? envelope.schemaVersion
        key = try open(wrapped, key: wrappingKey, aad: "3105PATCH/v\(v)/key/\(uuid)")
    } else {
        guard let plainKey = envelope.publicContentKey else {
            throw ImportError.invalid("missing public key")
        }
        key = plainKey
    }
    guard Data(SHA256.hash(data: key)) == envelope.keyFingerprint else {
        throw ImportError.invalid("incorrect password or corrupted package")
    }
    let decrypted = try open(envelope.encryptedPayload, key: key,
                             aad: "3105PATCH/v\(envelope.schemaVersion)/payload/\(uuid)")
    let payload = try PropertyListDecoder().decode(Payload.self, from: decrypted)
    guard payload.project.id == envelope.packageID else {
        throw ImportError.invalid("package ID mismatch")
    }
    guard payload.project.rules.count == payload.replacementDigests.count,
          payload.project.rules.count <= 1000 else {
        throw ImportError.invalid("invalid number of rules")
    }
    var files = [[String: Any]]()
    var keys = Set<String>()
    for rule in payload.project.rules {
        guard payload.replacementDigests[rule.id.uuidString] ==
                Data(SHA256.hash(data: rule.replacementData)) else {
            throw ImportError.invalid("file integrity check failed")
        }
        let key = rule.bundleID + "\0" + rule.relativePath
        guard keys.insert(key).inserted, rule.replacementData.count <= 8 * 1024 * 1024 else {
            throw ImportError.invalid("duplicate or oversized file")
        }
        files.append([
            "bundleID": rule.bundleID, "path": rule.relativePath,
            "data": rule.replacementData.base64EncodedString()
        ])
    }
    guard !files.isEmpty else { throw ImportError.invalid("package has no file replacements") }
    return ["name": payload.project.name, "files": files,
            "source": "3105", "schemaVersion": envelope.schemaVersion]
}
// C ABI, loaded with dlopen/dlsym by the Objective-C application.
// Returns an allocated UTF-8 JSON C string. Caller must free().
@_cdecl("wq_decode_3105")
public func wq_decode_3105(_ ptr: UnsafePointer<UInt8>?,
                            _ size: Int, _ pass: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let ptr, size > 0, size <= 64 * 1024 * 1024 else {
        return strdup("{\"error\":\"package is empty or too large\"}")
    }
    do {
        let package = try decode(Data(bytes: ptr, count: size),
                                 password: pass.map { String(cString: $0) })
        let result = try JSONSerialization.data(withJSONObject: package, options: [])
        return strdup(String(decoding: result, as: UTF8.self))
    } catch ImportError.invalid(let reason) {
        let result = try? JSONSerialization.data(withJSONObject: ["error":reason])
        return strdup(String(decoding: result ?? Data("{\"error\":\"import error\"}".utf8), as: UTF8.self))
    } catch {
        return strdup("{\"error\":\"incorrect password, corrupted package, or unsupported 3105 schema\"}")
    }
}
