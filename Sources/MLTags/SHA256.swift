import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// SHA-256 für die Prüfsummen von Sicherung, Kopie und Wiederherstellung.
/// Unter macOS über CryptoKit (hardwarebeschleunigt), sonst in reinem Swift.
struct SHA256Digest {
    #if canImport(CryptoKit)
    private var hasher = CryptoKit.SHA256()

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        hasher.update(bufferPointer: bytes)
    }

    mutating func update(_ data: Data) {
        hasher.update(data: data)
    }

    mutating func finalize() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    #else
    private var portable = PortableSHA256()

    mutating func update(_ bytes: UnsafeRawBufferPointer) { portable.update(bytes) }
    mutating func update(_ data: Data) { portable.update(data) }
    mutating func finalize() -> String { portable.finalize() }
    #endif

    /// Prüfsumme (hex) von Daten.
    static func hex(_ data: Data) -> String {
        var d = SHA256Digest()
        d.update(data)
        return d.finalize()
    }
}

/// SHA-256 in reinem Swift (FIPS 180-4), für Plattformen ohne CryptoKit.
struct PortableSHA256 {
    private var h: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var buffer: [UInt8] = []
    private var length: UInt64 = 0

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard !bytes.isEmpty else { return }
        length &+= UInt64(bytes.count)
        var index = 0
        if !buffer.isEmpty {
            let take = min(64 - buffer.count, bytes.count)
            buffer.append(contentsOf: bytes[0..<take])
            index = take
            if buffer.count == 64 {
                buffer.withUnsafeBytes { process(block: $0) }
                buffer.removeAll(keepingCapacity: true)
            }
        }
        while index + 64 <= bytes.count {
            process(block: UnsafeRawBufferPointer(rebasing: bytes[index..<(index + 64)]))
            index += 64
        }
        if index < bytes.count { buffer.append(contentsOf: bytes[index...]) }
    }

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    mutating func finalize() -> String {
        var tail = buffer
        let bitLength = length &* 8
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
        tail.withUnsafeBytes { raw in
            var i = 0
            while i < raw.count {
                process(block: UnsafeRawBufferPointer(rebasing: raw[i..<(i + 64)]))
                i += 64
            }
        }
        buffer.removeAll()
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private mutating func process(block: UnsafeRawBufferPointer) {
        @inline(__always) func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { w in
            for t in 0..<16 {
                w[t] = UInt32(bigEndian: block.loadUnaligned(fromByteOffset: t * 4, as: UInt32.self))
            }
            for t in 16..<64 {
                let a = w[t - 15], b = w[t - 2]
                let s0 = rotr(a, 7) ^ rotr(a, 18) ^ (a >> 3)
                let s1 = rotr(b, 17) ^ rotr(b, 19) ^ (b >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            PortableSHA256.k.withUnsafeBufferPointer { k in
                for t in 0..<64 {
                    let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                    let ch = (e & f) ^ (~e & g)
                    let t1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                    let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                    let maj = (a & b) ^ (a & c) ^ (b & c)
                    let t2 = s0 &+ maj
                    hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
                }
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
    }

}
