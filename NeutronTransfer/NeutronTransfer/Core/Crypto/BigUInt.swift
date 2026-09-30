// Neutron Transfer — minimal unsigned big integer for SRP-6a (up to 2048-bit).
// Wire format: fixed-size LITTLE-endian Data (matches go-srp toInt/fromInt).
//
// DESIGN: 32-bit limbs. Every intermediate (a*b + acc + carry with a,b,acc
// < 2^32) is < 2^64, so plain UInt64 arithmetic is EXACT — no fullWidth,
// no wrap-prone carry chains. Slower per-op than 64-bit limbs, but obviously
// correct; a login needs only a handful of 2048-bit modPows.
import Foundation

struct BigUInt: Sendable, Equatable {
    /// Little-endian 32-bit limbs, normalized (no trailing zero limbs except [0]).
    var limbs: [UInt32]

    init(limbs: [UInt32]) {
        var l = limbs
        while l.count > 1 && l.last == 0 { l.removeLast() }
        self.limbs = l
    }

    static let zero = BigUInt(limbs: [0])
    static let one = BigUInt(limbs: [1])
    static let two = BigUInt(limbs: [2])

    var isZero: Bool { limbs.count == 1 && limbs[0] == 0 }
    var isOne: Bool { limbs.count == 1 && limbs[0] == 1 }
    var isEven: Bool { (limbs[0] & 1) == 0 }

    init(dataLE: Data) {
        var limbs: [UInt32] = []
        var i = dataLE.startIndex
        while i < dataLE.endIndex {
            var word: UInt32 = 0
            var shift = 0
            for _ in 0..<4 {
                guard i < dataLE.endIndex else { break }
                word |= UInt32(dataLE[i]) << shift
                shift += 8
                i = dataLE.index(after: i)
            }
            limbs.append(word)
        }
        self.init(limbs: limbs.isEmpty ? [0] : limbs)
    }

    func toDataLE(length: Int) -> Data {
        var out = Data(repeating: 0, count: length)
        var idx = 0
        for limb in limbs {
            for b in 0..<4 where idx < length {
                out[idx] = UInt8((limb >> (b * 8)) & 0xFF)
                idx += 1
            }
        }
        return out
    }

    func compare(_ other: BigUInt) -> Int {
        if limbs.count != other.limbs.count {
            return limbs.count < other.limbs.count ? -1 : 1
        }
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            if limbs[i] != other.limbs[i] {
                return limbs[i] < other.limbs[i] ? -1 : 1
            }
        }
        return 0
    }

    static func add(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        let n = max(a.limbs.count, b.limbs.count)
        var out: [UInt32] = []
        out.reserveCapacity(n + 1)
        var carry: UInt64 = 0
        for i in 0..<n {
            let x: UInt64 = i < a.limbs.count ? UInt64(a.limbs[i]) : 0
            let y: UInt64 = i < b.limbs.count ? UInt64(b.limbs[i]) : 0
            let t = x + y + carry // < 2^33, exact
            out.append(UInt32(t & 0xFFFF_FFFF))
            carry = t >> 32
        }
        if carry > 0 { out.append(UInt32(carry)) }
        return BigUInt(limbs: out)
    }

    /// Requires a >= b.
    static func sub(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        precondition(a.compare(b) >= 0, "sub requires a >= b")
        var out: [UInt32] = []
        out.reserveCapacity(a.limbs.count)
        var borrow: UInt64 = 0
        for i in 0..<a.limbs.count {
            let x = UInt64(a.limbs[i])
            let y: UInt64 = i < b.limbs.count ? UInt64(b.limbs[i]) : 0
            // y + borrow <= 2^32 < 2^64: no overflow. Underflow iff x < y + borrow.
            let sub = y + borrow
            let res = x &- sub
            out.append(UInt32(res & 0xFFFF_FFFF))
            borrow = x < sub ? 1 : 0
        }
        return BigUInt(limbs: out)
    }

    static func mul(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        if a.isZero || b.isZero { return .zero }
        var out = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                // max: (2^32-1)^2 + (2^32-1) + carry(<2^32) = 2^64-1 exactly. Exact.
                let t = UInt64(a.limbs[i]) * UInt64(b.limbs[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(t & 0xFFFF_FFFF)
                carry = t >> 32
            }
            var k = i + b.limbs.count
            var c = carry
            while c > 0 {
                let t = UInt64(out[k]) + c // < 2^33, exact
                out[k] = UInt32(t & 0xFFFF_FFFF)
                c = t >> 32
                k += 1
            }
        }
        return BigUInt(limbs: out)
    }

    /// Remainder via Knuth Algorithm D long division, composed ONLY of exact
    /// add/sub/mul/compare above. Estimate never undershoots ( Knuth Thm A
    /// needs no normalization for the >= direction), verify loop decrements
    /// to the exact digit, subtraction is exact.
    static func mod(_ a: BigUInt, _ m: BigUInt) -> BigUInt {
        precondition(!m.isZero, "mod by zero")
        if a.compare(m) < 0 { return a }
        return divmod(a, m).r
    }

    /// Long division. Requires a >= m > 0.
    static func divmod(_ a: BigUInt, _ m: BigUInt) -> (q: BigUInt, r: BigUInt) {
        precondition(!m.isZero && a.compare(m) >= 0, "divmod requires a >= m > 0")
        if m.limbs.count == 1 {
            let d = UInt64(m.limbs[0])
            var rem: UInt64 = 0
            var q = [UInt32](repeating: 0, count: a.limbs.count)
            for i in stride(from: a.limbs.count - 1, through: 0, by: -1) {
                let t = (rem << 32) | UInt64(a.limbs[i]) // rem < d <= 2^32-1: exact
                q[i] = UInt32(t / d)
                rem = t % d
            }
            return (BigUInt(limbs: q), BigUInt(limbs: [UInt32(rem)]))
        }

        let n = m.limbs.count
        let mm = a.limbs.count - n
        var un = a.limbs
        while un.count < mm + n + 1 { un.append(0) }
        let vn = m.limbs
        let vBig = BigUInt(limbs: vn)
        var q = [UInt32](repeating: 0, count: mm + 1)

        for j in stride(from: mm, through: 0, by: -1) {
            // Estimate from top two window words / top divisor word.
            // Numerator < 2^64 (top window word < divisor top word by invariant),
            // so plain UInt64 division is exact. Clamp to base-1.
            var qhat: UInt64
            if un[j + n] == vn[n - 1] {
                qhat = UInt64(UInt32.max)
            } else {
                let num = (UInt64(un[j + n]) << 32) | UInt64(un[j + n - 1])
                qhat = num / UInt64(vn[n - 1])
                if qhat > UInt64(UInt32.max) { qhat = UInt64(UInt32.max) }
            }
            // Decrement until qhat * vn fits the window (exact check).
            var prod = mul(BigUInt(limbs: [UInt32(qhat & 0xFFFF_FFFF), UInt32(qhat >> 32)]), vBig)
            var window = BigUInt(limbs: Array(un[j..<(j + n + 1)]))
            while prod.compare(window) > 0 {
                qhat -= 1
                prod = mul(BigUInt(limbs: [UInt32(qhat & 0xFFFF_FFFF), UInt32(qhat >> 32)]), vBig)
            }
            window = sub(window, prod)
            for i in 0...(n) {
                un[j + i] = i < window.limbs.count ? window.limbs[i] : 0
            }
            q[j] = UInt32(qhat & 0xFFFF_FFFF)
            assert(qhat <= UInt64(UInt32.max), "quotient digit must fit 32 bits")
        }
        return (BigUInt(limbs: q), BigUInt(limbs: Array(un.prefix(n))))
    }

    static func modMul(_ a: BigUInt, _ b: BigUInt, _ m: BigUInt) -> BigUInt {
        mod(mul(a, b), m)
    }

    static func modPow(_ base: BigUInt, _ exp: BigUInt, _ mod_: BigUInt) -> BigUInt {
        precondition(!mod_.isZero, "modpow by zero")
        var result = BigUInt.one
        var b = mod(base, mod_)
        var e = exp
        while !e.isZero {
            if (e.limbs[0] & 1) == 1 {
                result = mod(mul(result, b), mod_)
            }
            e = e.shr1()
            b = mod(mul(b, b), mod_)
        }
        return result
    }

    var bitLength: Int {
        guard let top = limbs.last, top != 0 else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    func shl(_ bits: Int) -> BigUInt {
        if isZero || bits == 0 { return self }
        let words = bits / 32, rem = bits % 32
        var out = [UInt32](repeating: 0, count: limbs.count + words + 1)
        var carry: UInt32 = 0
        for i in 0..<limbs.count {
            let v = UInt64(limbs[i])
            out[i + words] = UInt32((v << rem) & 0xFFFF_FFFF) | carry
            carry = rem == 0 ? 0 : UInt32((v >> (32 - rem)) & 0xFFFF_FFFF)
        }
        out[limbs.count + words] = carry
        return BigUInt(limbs: out)
    }

    func shr1() -> BigUInt {
        var out = [UInt32](repeating: 0, count: limbs.count)
        var carry: UInt32 = 0
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            let v = limbs[i]
            out[i] = (v >> 1) | (carry << 31)
            carry = v & 1
        }
        return BigUInt(limbs: out)
    }
}
