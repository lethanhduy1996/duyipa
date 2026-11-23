import Foundation
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
        print("PASS: .3105 export/import, password and corruption checks")
    }
}
