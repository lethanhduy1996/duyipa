import Foundation

// Edits only stored RGB values of a selected decorative Material property.
// No shader programs, alpha, render state, keywords, or game paths are changed.
enum BundleColorError: LocalizedError {
    case invalid, unsupported, tooLarge, noColors
    var errorDescription: String? {
        switch self {
        case .invalid: return "Cấu trúc UnityFS không hợp lệ."
        case .unsupported: return "Phiên bản hoặc cấu trúc UnityFS chưa được hỗ trợ."
        case .tooLarge: return "Tài nguyên giải nén vượt quá giới hạn."
        case .noColors: return "Không tìm thấy thuộc tính màu material trang trí phù hợp."
        }
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var pos: Int = 0
    var remaining: Int { bytes.count - pos }
    mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, n <= remaining else { throw BundleColorError.invalid }
        defer { pos += n }
        return Array(bytes[pos..<(pos+n)])
    }
    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= remaining else { throw BundleColorError.invalid }
        pos += n
    }
    mutating func align(_ n: Int) throws { try skip((n - pos % n) % n) }
    mutating func number(_ n: Int, little: Bool = false) throws -> UInt64 {
        let b = try take(n)
        var value: UInt64 = 0
        if little {
            for x in b.reversed() { value = (value << 8) | UInt64(x) }
        } else {
            for x in b { value = (value << 8) | UInt64(x) }
        }
        return value
    }
    mutating func count(_ max: Int, little: Bool = true) throws -> Int {
        let n = try number(4, little: little)
        guard n <= UInt64(max) else { throw BundleColorError.invalid }
        return Int(n)
    }
    mutating func cstring() throws -> String {
        let start = pos
        while pos < bytes.count && pos - start <= 1024 && bytes[pos] != 0 { pos += 1 }
        guard pos < bytes.count, pos - start <= 1024, bytes[pos] == 0,
              let s = String(bytes: bytes[start..<pos], encoding: .utf8) else { throw BundleColorError.invalid }
        pos += 1
        return s
    }
    mutating func alignedString() throws -> String {
        let n = try count(65536)
        guard let s = String(bytes: try take(n), encoding: .utf8) else { throw BundleColorError.invalid }
        try align(4)
        return s
    }
}

private func big(_ x: UInt64, _ n: Int) -> [UInt8] {
    (0..<n).reversed().map { UInt8(truncatingIfNeeded: x >> ($0*8)) }
}

private func decodeBlock(_ input: [UInt8], expected: Int, kind: Int) throws -> [UInt8] {
    guard expected >= 0 && expected <= 64 * 1024 * 1024 else { throw BundleColorError.tooLarge }
    if kind == 0 {
        guard input.count == expected else { throw BundleColorError.invalid }
        return input
    }
    guard kind == 2 || kind == 3 else { throw BundleColorError.unsupported }
    var result: [UInt8] = []
    result.reserveCapacity(expected)
    var pos = 0
    func extend(_ initial: Int) throws -> Int {
        var n = initial
        if n == 15 {
            while true {
                guard pos < input.count else { throw BundleColorError.invalid }
                let extra = Int(input[pos]); pos += 1
                guard n <= expected, extra <= expected - n else { throw BundleColorError.invalid }
                n += extra
                if extra != 255 { break }
            }
        }
        return n
    }
    while pos < input.count {
        let token = Int(input[pos]); pos += 1
        let literals = try extend(token >> 4)
        guard literals <= input.count - pos, literals <= expected - result.count else { throw BundleColorError.invalid }
        result.append(contentsOf: input[pos..<(pos+literals)]); pos += literals
        if pos == input.count { break }
        guard pos + 2 <= input.count else { throw BundleColorError.invalid }
        let distance = Int(input[pos]) | (Int(input[pos+1]) << 8); pos += 2
        let length = try extend(token & 15) + 4
        guard distance > 0, distance <= result.count, length <= expected - result.count else { throw BundleColorError.invalid }
        for _ in 0..<length { result.append(result[result.count-distance]) }
    }
    guard result.count == expected else { throw BundleColorError.invalid }
    return result
}

struct BundleColorField: Identifiable {
    let material: String
    let property: String
    fileprivate let offset: Int
    var id: Int { offset }
    var title: String { material + " · " + property }
}

struct DecorativeBundle {
    private struct Block {
        let start: Int
        let size: Int
        let flags: UInt64
        let stored: [UInt8]
    }
    private struct Node {
        let offset: Int
        let size: Int
    }
    private let prefix: [UInt8]
    private let flags: UInt64
    private let directoryTail: [UInt8]
    private let blocks: [Block]
    private let payload: [UInt8]
    let fields: [BundleColorField]

    init(_ data: Data) throws {
        var r = ByteReader(bytes: Array(data))
        guard try r.cstring() == "UnityFS" else { throw BundleColorError.invalid }
        let version = try r.number(4)
        guard version == 8 else { throw BundleColorError.unsupported }
        _ = try r.cstring()
        _ = try r.cstring()
        let prefix = Array(r.bytes[..<r.pos])
        let length = try r.number(8)
        let compressed = try r.count(4 * 1024 * 1024, little: false)
        let plain = try r.count(4 * 1024 * 1024, little: false)
        let flags = try r.number(4)
        guard length == UInt64(data.count), flags & 0x40 != 0,
              flags & 0x80 == 0, flags & ~UInt64(0x27f) == 0 else { throw BundleColorError.unsupported }
        try r.align(16)
        var directory = ByteReader(bytes: try decodeBlock(r.take(compressed), expected: plain, kind: Int(flags & 63)))
        // Only support bundles with the unused, zero directory hash.
        guard try directory.take(16).allSatisfy({ $0 == 0 }) else { throw BundleColorError.unsupported }
        let count = try directory.count(4096, little: false)
        var sizes: [(Int, Int, UInt64)] = []
        var total = 0
        for _ in 0..<count {
            let n = try directory.count(64 * 1024 * 1024, little: false)
            let c = try directory.count(32 * 1024 * 1024, little: false)
            let f = try directory.number(2)
            guard n <= 64 * 1024 * 1024 - total else { throw BundleColorError.tooLarge }
            total += n
            sizes.append((n, c, f))
        }
        let tail = Array(directory.bytes[directory.pos...])
        var nodes: [Node] = []
        let nodeCount = try directory.count(4096, little: false)
        for _ in 0..<nodeCount {
            let o = try directory.number(8)
            let n = try directory.number(8)
            _ = try directory.number(4)
            let name = try directory.cstring()
            guard o <= UInt64(total), n <= UInt64(total) - o else { throw BundleColorError.invalid }
            if name.hasPrefix("CAB-") && !name.contains(".") {
                nodes.append(Node(offset: Int(o), size: Int(n)))
            }
        }
        guard directory.remaining == 0 else { throw BundleColorError.invalid }
        if flags & 0x200 != 0 { try r.align(16) }
        var blocks: [Block] = [], payload: [UInt8] = []
        payload.reserveCapacity(total)
        for (size, compressed, f) in sizes {
            let stored = try r.take(compressed)
            let decoded = try decodeBlock(stored, expected: size, kind: Int(f & 63))
            blocks.append(Block(start: payload.count, size: size, flags: f, stored: stored))
            payload.append(contentsOf: decoded)
        }
        guard r.remaining == 0 else { throw BundleColorError.invalid }
        var fields: [BundleColorField] = []
        for node in nodes {
            let bytes = Array(payload[node.offset..<(node.offset+node.size)])
            fields += try Self.readMaterials(bytes, base: node.offset)
        }
        self.prefix = prefix
        self.flags = flags
        self.directoryTail = tail
        self.blocks = blocks
        self.payload = payload
        self.fields = fields
    }

    private static func readMaterials(_ bytes: [UInt8], base: Int) throws -> [BundleColorField] {
        var r = ByteReader(bytes: bytes)
        try r.skip(8)
        guard try r.number(4) == 22 else { throw BundleColorError.unsupported }
        try r.skip(4)
        guard try r.number(1) == 0 else { throw BundleColorError.unsupported }
        try r.skip(3)
        let metaSize = try r.number(4)
        let fileSize = try r.number(8)
        let dataStart = try r.number(8)
        try r.skip(8)
        guard fileSize == UInt64(bytes.count), dataStart <= fileSize,
              metaSize <= dataStart else { throw BundleColorError.invalid }
        _ = try r.cstring()
        try r.skip(4)
        guard try r.number(1) == 1 else { throw BundleColorError.unsupported }
        let typeCount = try r.count(1024)
        var types: [(UInt64, Bool)] = []
        // This exact Material type hash identifies the supported serialized layout.
        let materialHash: [UInt8] = [0xc6,0x00,0x98,0xac,0x66,0xa2,0x8b,0x50,0xaa,0x05,0x80,0xdb,0x11,0xbf,0x01,0x8c]
        for _ in 0..<typeCount {
            let id = try r.number(4, little: true)
            try r.skip(3)
            if id == 114 { try r.skip(16) }
            let hash = try r.take(16)
            let treeNodes = try r.count(20000)
            let strings = try r.count(2 * 1024 * 1024)
            try r.skip(treeNodes * 32)
            try r.skip(strings)
            let deps = try r.count(10000)
            try r.skip(deps * 4)
            types.append((id, id == 21 && hash == materialHash))
        }
        let objectCount = try r.count(100000)
        var fields: [BundleColorField] = []
        for _ in 0..<objectCount {
            try r.align(4)
            try r.skip(8)
            let offset = try r.number(8, little: true)
            let size = try r.number(4, little: true)
            let typeIndex = try r.count(1024)
            guard typeIndex < types.count, offset <= fileSize - dataStart,
                  size <= fileSize - dataStart - offset else { throw BundleColorError.invalid }
            if !types[typeIndex].1 { continue }
            let start = Int(dataStart + offset)
            var m = ByteReader(bytes: Array(bytes[start..<(start+Int(size))]))
            let name = try m.alignedString()
            // Ordinary decorative effects only, never avatar/spectator or depth/outline fields.
            let lower = name.lowercased()
            guard !["avatar", "chara", "cloth", "spectator", "xray", "x-ray", "outline", "silhouette", "enemy", "player", "3p"].contains(where: { lower.contains($0) }) else { continue }
            try m.skip(12)
            for _ in 0..<2 {
                let n = try m.count(4096)
                for _ in 0..<n { _ = try m.alignedString() }
            }
            try m.skip(6)
            try m.align(4)
            try m.skip(4)
            let tags = try m.count(4096)
            for _ in 0..<tags { _ = try m.alignedString(); _ = try m.alignedString() }
            let passes = try m.count(4096)
            for _ in 0..<passes { _ = try m.alignedString() }
            for stride in [28, 4, 4] {
                let n = try m.count(4096)
                for _ in 0..<n { _ = try m.alignedString(); try m.skip(stride) }
            }
            let colors = try m.count(4096)
            var materialFields: [BundleColorField] = []
            let allowed = ["_Color", "_BaseColor", "_MainColor", "_TintColor", "_Color_Tex", "_Color_DisTex"]
            for _ in 0..<colors {
                let key = try m.alignedString()
                let position = m.pos
                let values = try (0..<4).map { _ in Float(bitPattern: UInt32(try m.number(4, little: true))) }
                if allowed.contains(key), values.allSatisfy({ $0.isFinite }), values.prefix(3).allSatisfy({ $0 >= 0 && $0 <= 1 }) {
                    materialFields.append(BundleColorField(material: name, property: key, offset: base + start + position))
                }
            }
            let stacks = try m.count(4096)
            for _ in 0..<stacks { _ = try m.alignedString(); _ = try m.alignedString() }
            guard m.remaining == 0 else { throw BundleColorError.unsupported }
            fields.append(contentsOf: materialFields)
        }
        return fields
    }

    func export(fieldID: Int, red: Double, green: Double, blue: Double) throws -> Data {
        guard fields.contains(where: { $0.id == fieldID }),
              [red,green,blue].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { throw BundleColorError.noColors }
        var edited = payload
        for (i, v) in [red,green,blue].enumerated() {
            let bits = Float(v).bitPattern
            for j in 0..<4 { edited[fieldID+i*4+j] = UInt8(truncatingIfNeeded: bits >> (j*8)) }
        }
        var directory = [UInt8](repeating: 0, count: 16)
        directory += big(UInt64(blocks.count), 4)
        var stored: [[UInt8]] = []
        for b in blocks {
            let end = b.start + b.size
            let changed = b.start < fieldID+12 && end > fieldID
            // Unchanged compressed blocks are copied verbatim. Changed blocks use
            // UnityFS's supported uncompressed block representation.
            let bytes = changed ? Array(edited[b.start..<end]) : b.stored
            let f = changed ? b.flags & ~UInt64(63) : b.flags
            directory += big(UInt64(b.size), 4) + big(UInt64(bytes.count), 4) + big(f, 2)
            stored.append(bytes)
        }
        directory += directoryTail
        var output = prefix
        output += big(0, 8) + big(UInt64(directory.count), 4) + big(UInt64(directory.count), 4) + big(flags & ~UInt64(63), 4)
        while output.count % 16 != 0 { output.append(0) }
        output += directory
        if flags & 0x200 != 0 { while output.count % 16 != 0 { output.append(0) } }
        for b in stored { output += b }
        output.replaceSubrange(prefix.count..<(prefix.count+8), with: big(UInt64(output.count), 8))
        let result = Data(output)
        let verified = try DecorativeBundle(result)
        guard verified.payload == edited, verified.fields.contains(where: { $0.id == fieldID }) else { throw BundleColorError.invalid }
        return result
    }
}
