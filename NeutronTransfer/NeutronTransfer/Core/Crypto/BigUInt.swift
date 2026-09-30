// Neutron Transfer — minimal unsigned big integer for SRP-6a (up to 2048-bit).
// Wire format matches go-srp toInt/fromInt: fixed-size LITTLE-endian Data.
// Operations: compare, add, sub (a>=b), mul, mod, modPow. O(n^2) is fine for one login.
import Foundation

struct BigUInt: Sendable, Equatable {
    /// Little-endian limbs, normalized (no trailing zero limbs except [0]).
    var limbs: [UInt64]

    init(limbs: [UInt64]) {
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
        var limbs: [UInt64] = []
        var i = dataLE.startIndex
        while i < dataLE.endIndex {
            var word: UInt64 = 0
            var shift = 0
            for _ in 0..<8 {
                guard i < dataLE.endIndex else { break }
                word |= UInt64(dataLE[i]) << shift
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
            for b in 0..<8 where idx < length {
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
        var out: [UInt64] = []
        out.reserveCapacity(n + 1)
        var carry: UInt64 = 0
        for i in 0..<n {
            let x = i < a.limbs.count ? a.limbs[i] : 0
            let y = i < b.limbs.count ? b.limbs[i] : 0
            let (s1, o1) = x.addingReportingOverflow(y)
            let (s2, o2) = s1.addingReportingOverflow(carry)
            out.append(s2)
            carry = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        if carry > 0 { out.append(carry) }
        return BigUInt(limbs: out)
    }

    /// Requires a >= b.
    static func sub(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        var out: [UInt64] = []
        out.reserveCapacity(a.limbs.count)
        var borrow: UInt64 = 0
        for i in 0..<a.limbs.count {
            let x = a.limbs[i]
            let y = i < b.limbs.count ? b.limbs[i] : 0
            let (d1, o1) = x.subtractingReportingOverflow(borrow)
            let (d2, o2) = d1.subtractingReportingOverflow(y)
            out.append(d2)
            borrow = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        return BigUInt(limbs: out)
    }

    static func mul(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        if a.isZero || b.isZero { return .zero }
        var out = [UInt64](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                let (hi, lo) = a.limbs[i].multipliedFullWidth(by: b.limbs[j])
                let (s1, o1) = out[i + j].addingReportingOverflow(lo)
                out[i + j] = s1
                var c = hi + (o1 ? 1 : 0)
                let (s2, o2) = out[i + j + 1].addingReportingOverflow(carry)
                // add hi part in next iteration chain
                let (s3, o3) = s2.addingReportingOverflow(c)
                _ = o3
                out[i + j + 1] = s3
                carry = (o2 ? 1 : 0)
                c = 0 // consumed
                _ = c
            }
            var k = i + b.limbs.count
            var c = carry
            while c > 0 {
                let (s, o) = out[k].addingReportingOverflow(c)
                out[k] = s
                c = o ? 1 : 0
                k += 1
            }
        }
        return BigUInt(limbs: out)
    }

    /// Binary long division remainder. Fine for 2048-bit occasional use.
    static func mod(_ a: BigUInt, _ m: BigUInt) -> BigUInt {
        precondition(!m.isZero, "mod by zero")
        if a.compare(m) < 0 { return a }
        let shift = a.bitLength - m.bitLength
        var rem = a
        var shifted = m.shl(shift)
        for _ in stride(from: shift, through: 0, by: -1) {
            if rem.compare(shifted) >= 0 {
                rem = sub(rem, shifted)
            }
            shifted = shifted.shr1()
        }
        return rem
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
        return (limbs.count - 1) * 64 + (64 - top.leadingZeroBitCount)
    }

    func shl(_ bits: Int) -> BigUInt {
        if isZero || bits == 0 { return self }
        let words = bits / 64, rem = bits % 64
        var out = [UInt64](repeating: 0, count: limbs.count + words + 1)
        var carry: UInt64 = 0
        for i in 0..<limbs.count {
            let v = limbs[i]
            out[i + words] = (v << rem) | carry
            carry = rem == 0 ? 0 : (v >> (64 - rem))
        }
        out[limbs.count + words] = carry
        return BigUInt(limbs: out)
    }

    func shr1() -> BigUInt {
        var out = [UInt64](repeating: 0, count: limbs.count)
        var carry: UInt64 = 0
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            let v = limbs[i]
            out[i] = (v >> 1) | (carry << 63)
            carry = v & 1
        }
        return BigUInt(limbs: out)
    }
}
