// WQFiles Patch bridge for the open-source 3105 package schema v1-v3.
// Implements import/decode only; modifications and rollback live in WQPatch.m.
// References: YangJiiii/3105 PatchPackageCodec.swift (GPL compatible usage).
import Foundation
import CryptoKit
import Security
import CommonCrypto
import Darwin

private struct Envelope: Codable {
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


// Create an interoperable 3105 schema v3 package from a single or multi-file draft.
// The caller gives JSON: {"name":"...", "files":[{"bundleID":"...", "path":"Documents/...",
// "data":"base64..."}]}. A package is created locally; it never applies itself.
private struct DraftFile: Decodable {
    let bundleID: String
    let path: String
    let data: String
}
private struct DraftInput: Decodable {
    let name: String
    let files: [DraftFile]
}
private struct ExportRule: Encodable {
    let id: UUID
    let bundleID: String
    let relativePath: String
    let replacementFilename: String
    let replacementData: Data
}
private struct ExportProject: Encodable {
    let id: UUID
    let name: String
    let author: String
    let isPrivate: Bool
    let createdAt: Date
    let updatedAt: Date
    let bundleIdentifiers: [String]
    let directories: [String] // empty in the initial editor
    let rules: [ExportRule]
}
private struct ExportPayload: Encodable {
    let project: ExportProject
    let replacementDigests: [String: Data]
}
private func randomBytes(_ count: Int) throws -> Data {
    var bytes = Data(count: count)
    let result = bytes.withUnsafeMutableBytes { ptr in
        SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
    }
    guard result == errSecSuccess else { throw ImportError.invalid("secure random generator failed") }
    return bytes
}
private func seal(_ message: Data, key: Data, aad: String) throws -> Data {
    let box = try AES.GCM.seal(message, using: SymmetricKey(data: key),
                               authenticating: Data(aad.utf8))
    guard let combined = box.combined else { throw ImportError.invalid("AES-GCM failed") }
    return combined
}
private func exportPackage(_ input: DraftInput, password: String?) throws -> Data {
    let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.utf8.count <= 120, !input.files.isEmpty,
          input.files.count <= 1000 else { throw ImportError.invalid("invalid patch name or file list") }
    var seen = Set<String>()
    var rules = [ExportRule]()
    var bundleIDs = [String]()
    for item in input.files {
        let components = item.path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2, ["Documents","Library","tmp"].contains(String(components[0])),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !item.path.hasPrefix("/"), !item.path.contains("\\"),
              item.path.utf8.count <= 1024,
              item.bundleID.count >= 3 && item.bundleID.count <= 255 &&
              item.bundleID.contains(".") && !item.bundleID.contains("/") else {
            throw ImportError.invalid("invalid bundle identifier or target path")
        }
        guard seen.insert(item.bundleID + "\u{0}" + item.path).inserted,
              let data = Data(base64Encoded: item.data), data.count <= 8 * 1024 * 1024 else {
            throw ImportError.invalid("duplicate target, invalid base64 or file larger than 8 MiB")
        }
        if !bundleIDs.contains(item.bundleID) { bundleIDs.append(item.bundleID) }
        rules.append(ExportRule(id: UUID(), bundleID: item.bundleID,
                                relativePath: item.path,
                                replacementFilename: String(components.last!),
                                replacementData: data))
    }
    let projectID = UUID()
    let project = ExportProject(id: projectID, name: name, author: "", isPrivate: false,
                                createdAt: Date(), updatedAt: Date(),
                                bundleIdentifiers: bundleIDs, directories: [], rules: rules)
    let digests = Dictionary(uniqueKeysWithValues: rules.map {
        ($0.id.uuidString, Data(SHA256.hash(data: $0.replacementData)))
    })
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let body = try encoder.encode(ExportPayload(project: project, replacementDigests: digests))
    let key = try randomBytes(32)
    let uuid = projectID.uuidString
    let ciphertext = try seal(body, key: key, aad: "3105PATCH/v3/payload/\(uuid)")
    let isProtected = !(password ?? "").isEmpty
    let salt = isProtected ? try randomBytes(16) : nil
    let count = isProtected ? 250_000 : nil
    let wrapped = isProtected ? try seal(key,
                          key: derive(password!, salt: salt!, iterations: count!),
                          aad: "3105PATCH/v3/key/\(uuid)") : nil
    let envelope = Envelope(schemaVersion: 3, keyAADVersion: isProtected ? 3 : nil,
                            packageID: projectID, isPasswordProtected: isProtected,
                            kdfSalt: salt, kdfIterations: count, wrappedContentKey: wrapped,
                            publicContentKey: isProtected ? nil : key,
                            keyFingerprint: Data(SHA256.hash(data: key)),
                            encryptedPayload: ciphertext)
    var result = Data("3105PATCH\0".utf8)
    result.append(try encoder.encode(envelope))
    // Round-trip verifies the resulting document is readable before writing a file.
    _ = try decode(result, password: password)
    return result
}

@_cdecl("wq_create_3105")
public func wq_create_3105(_ json: UnsafePointer<CChar>?,
                            _ password: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let json else { return strdup("{\"error\":\"missing patch description\"}") }
    do {
        let input = try JSONDecoder().decode(DraftInput.self, from: Data(String(cString: json).utf8))
        let secret = password.map { String(cString: $0) }
        let data = try exportPackage(input, password: secret)
        let result = try JSONSerialization.data(withJSONObject: [
            "base64": data.base64EncodedString(), "schemaVersion": 3
        ])
        return strdup(String(decoding: result, as: UTF8.self))
    } catch ImportError.invalid(let reason) {
        let data = try? JSONSerialization.data(withJSONObject: ["error": reason])
        return strdup(String(decoding: data ?? Data("{}".utf8), as: UTF8.self))
    } catch {
        return strdup("{\"error\":\"unable to create 3105 package\"}")
    }
}
