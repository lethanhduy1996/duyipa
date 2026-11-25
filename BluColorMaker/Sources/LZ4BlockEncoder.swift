import Foundation

// Standard raw LZ4 block encoder for general-purpose decorative Unity assets.
// Bounded search depth, 64 KiB match window, final literal constraints.
func encodeLZ4Block(_ input: [UInt8]) -> [UInt8] {
    let count = input.count
    if count == 0 { return [] }
    var output: [UInt8] = []
    output.reserveCapacity(count + count / 255 + 16)
    var head = [Int](repeating: -1, count: 65536)
    // Ring of previous offsets: entries older than 65535 are never traversed.
    var previous = [Int](repeating: -1, count: 65536)
    func key(_ i: Int) -> Int {
        let word = UInt32(input[i]) | (UInt32(input[i + 1]) << 8)
            | (UInt32(input[i + 2]) << 16) | (UInt32(input[i + 3]) << 24)
        return Int((word &* 2654435761) >> 16)
    }
    func remember(_ i: Int) {
        let h = key(i)
        previous[i & 65535] = head[h]
        head[h] = i
    }
    func appendLength(_ length: Int) {
        var remaining = length
        while remaining >= 255 {
            output.append(255)
            remaining -= 255
        }
        output.append(UInt8(remaining))
    }
    func emit(_ anchor: Int, _ i: Int, _ length: Int, _ distance: Int) {
        let literalCount = i - anchor
        let matchCode = length > 0 ? length - 4 : 0
        output.append(UInt8((min(literalCount, 15) << 4) | min(matchCode, 15)))
        if literalCount >= 15 { appendLength(literalCount - 15) }
        output.append(contentsOf: input[anchor..<i])
        if length > 0 {
            output.append(UInt8(distance & 255))
            output.append(UInt8(distance >> 8))
            if matchCode >= 15 { appendLength(matchCode - 15) }
        }
    }
    var anchor = 0
    var i = 0
    while i <= count - 12 {
        let h = key(i)
        var candidate = head[h]
        var best = 3
        var distance = 0
        var probes = 0
        let limit = count - 5 - i
        while candidate >= 0 && candidate < i && i - candidate <= 65535 && probes < 32 {
            if input[candidate] == input[i] && input[candidate + 1] == input[i + 1]
                && input[candidate + 2] == input[i + 2] && input[candidate + 3] == input[i + 3] {
                var length = 4
                while length < limit && input[candidate + length] == input[i + length] { length += 1 }
                if length > best {
                    best = length
                    distance = i - candidate
                    if length >= 255 || length == limit { break }
                }
            }
            candidate = previous[candidate & 65535]
            probes += 1
        }
        remember(i)
        if best >= 4 {
            emit(anchor, i, best, distance)
            let end = i + best
            if i + 1 < end {
                for j in (i + 1)..<end { remember(j) }
            }
            i = end
            anchor = i
        } else { i += 1 }
    }
    emit(anchor, count, 0, 0)
    return output
}
