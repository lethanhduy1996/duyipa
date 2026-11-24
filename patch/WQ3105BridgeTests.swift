import Foundation
import CryptoKit
import Darwin

@main
struct WQ3105BridgeTests {
    static func dictionary(_ raw: UnsafeMutablePointer<CChar>?) -> [String: Any] {
        guard let raw else { fatalError("Missing JSON result") }
        defer { free(raw) }
        let data=Data(String(cString:raw).utf8)
        guard let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {
            fatalError("Invalid bridge JSON response")
        }
        return value
    }

    // Test v9 without committing any user/game assets. Convert a valid unprotected
    // v3 fixture into a valid v9 envelope, authenticated with v9 AAD.
    static func version9(_ v3: Data, operation: String = "replace",
                         appGroup: Bool = false) throws -> Data {
        let magic=Data("3105PATCH\0".utf8)
        precondition(v3.starts(with: magic))
        var envelope=try PropertyListSerialization.propertyList(
            from: v3.dropFirst(magic.count), format: nil) as! [String:Any]
        let uuid=envelope["packageID"] as! String
        let key=envelope["publicContentKey"] as! Data
        let cipher=envelope["encryptedPayload"] as! Data
        let plain=try AES.GCM.open(try AES.GCM.SealedBox(combined: cipher),
                 using: SymmetricKey(data:key),
                 authenticating: Data("3105PATCH/v3/payload/\(uuid)".utf8))
        var payload=try PropertyListSerialization.propertyList(
            from: plain, format: nil) as! [String:Any]
        var project=payload["project"] as! [String:Any]
        var rules=project["rules"] as! [[String:Any]]
        for i in rules.indices {
            rules[i]["operation"]=operation
            rules[i]["containerKind"]="application"
        }
        project["rules"]=rules
        project["appGroupIdentifiers"]=appGroup ? ["group.example.test"] : [String]()
        project["systemAppGroupIdentifiers"]=[String]()
        project["settings"]=[Any]()
        project["directories"]=[Any]()
        payload["project"]=project
        let body=try PropertyListSerialization.data(fromPropertyList: payload, format:.binary, options:0)
        let box=try AES.GCM.seal(body, using:SymmetricKey(data:key),
                                 authenticating:Data("3105PATCH/v9/payload/\(uuid)".utf8))
        envelope["schemaVersion"]=9
        envelope["encryptedPayload"]=box.combined!
        let enc=try PropertyListSerialization.data(fromPropertyList: envelope,format:.binary, options:0)
        return magic + enc
    }
    static func decodeFile(_ bytes: Data, password: String) -> [String: Any] {
        return bytes.withUnsafeBytes { raw in
            password.withCString { pw in
                dictionary(wq_decode_3105(raw.bindMemory(to:UInt8.self).baseAddress,
                                           raw.count,pw))
            }
        }
    }
    static func main() {
        let payload=Data("{\"feature\":true}".utf8)
        let draft:[String:Any]=[
            "name":"Local test patch",
            "files":[["bundleID":"com.example.test","path":"Documents/config.json",
                      "data":payload.base64EncodedString()]]
        ]
        let draftData=try! JSONSerialization.data(withJSONObject:draft)
        let text=String(decoding:draftData,as:UTF8.self)

        for password in ["", "test-password"] {
            let created: [String:Any] = text.withCString { pointer in
                password.withCString { pass in
                    dictionary(wq_create_3105(pointer,pass))
                }
            }
            guard let encoded=created["base64"] as? String,
                  let bytes=Data(base64Encoded:encoded) else {
                fatalError("Package export failed: \(created)")
            }
            let response:[String:Any]=bytes.withUnsafeBytes { bytes in
                password.withCString { pass in
                    dictionary(wq_decode_3105(bytes.bindMemory(to:UInt8.self).baseAddress,
                                               bytes.count,pass))
                }
            }
            guard (response["name"] as? String) == "Local test patch",
                let files=response["files"] as? [[String:Any]], files.count==1,
                files[0]["data"] as? String == payload.base64EncodedString() else {
                fatalError("Round-trip mismatch: \(response)")
            }
            if !password.isEmpty {
                let wrong:[String:Any]=bytes.withUnsafeBytes { b in
                    "incorrect-password".withCString { pass in
                        dictionary(wq_decode_3105(b.bindMemory(to:UInt8.self).baseAddress,b.count,pass))
                    }
                }
                guard wrong["error"] != nil else { fatalError("Wrong password unexpectedly accepted") }
            }
            var corrupted=bytes
            corrupted[corrupted.count-1] ^= 1
            let tampered:[String:Any]=corrupted.withUnsafeBytes { b in
                password.withCString { pass in
                    dictionary(wq_decode_3105(b.bindMemory(to:UInt8.self).baseAddress,b.count,pass))
                }
            }
            guard tampered["error"] != nil else { fatalError("Corrupted package unexpectedly accepted") }
        }
        // Actual v9 samples previously inspected from the user's own files use
        // these same fields, and have v9 key/payload AAD. No user payloads are
        // stored in GitHub.
        let baseResult: [String:Any] = text.withCString { p in
            "".withCString { pw in dictionary(wq_create_3105(p,pw)) }
        }
        let base=Data(base64Encoded:baseResult["base64"] as! String)!
        let valid=try! version9(base)
        let v9=decodeFile(valid,password:"")
        guard (v9["schemaVersion"] as? Int)==9,
            (v9["compatibility"] as? String)=="v9-replace-only",
            let files=v9["files"] as? [[String:Any]],files.count==1,
            files[0]["data"] as? String == payload.base64EncodedString() else {
            fatalError("v9 replace-only decode failed: \(v9)")
        }
        let merge=decodeFile(try! version9(base,operation:"mergeJson"),password:"")
        guard merge["error"] != nil else { fatalError("v9 merge must be rejected") }
        let groups=decodeFile(try! version9(base,appGroup:true),password:"")
        guard groups["error"] != nil else { fatalError("v9 App Group must be rejected") }
        var bad=valid
        bad[bad.count-1] ^= 1
        let corruptedV9=decodeFile(bad,password:"")
        guard corruptedV9["error"] != nil else { fatalError("v9 auth failure not detected") }
        print("PASS: .3105 v1-v3 and v9 replace-only; reject merge, App Group and tampering")
    }
}
