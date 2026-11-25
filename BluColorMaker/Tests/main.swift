import Foundation

func check(_ bytes: [UInt8]) throws {
    let encoded = encodeLZ4Block(bytes)
    let decoded = try decodeBlock(encoded, expected: bytes.count, kind: 2)
    guard decoded == bytes else { fatalError("LZ4 roundtrip mismatch for \(bytes.count) bytes") }
}
var rng: UInt64 = 42
func randomByte() -> UInt8 {
    rng = rng &* 6364136223846793005 &+ 1
    return UInt8(truncatingIfNeeded: rng >> 32)
}
for n in [0, 1, 2, 4, 5, 11, 12, 13, 15, 16, 19, 255, 270, 4096, 65535, 65536, 131072, 262144] {
    try check([UInt8](repeating: 0, count: n))
    try check((0..<n).map { UInt8($0 % 17) })
    try check((0..<n).map { _ in randomByte() })
}
let repetitive = [UInt8](repeating: 7, count: 131072)
guard encodeLZ4Block(repetitive).count < 1024 else { fatalError("LZ4 compression ineffective") }
let sample = (0..<32768).map { _ in randomByte() }
try check(sample + sample + sample)
print("PASS: LZ4 synthetic compression and roundtrip checks")
