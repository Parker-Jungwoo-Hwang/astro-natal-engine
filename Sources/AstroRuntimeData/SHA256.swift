import Foundation

public struct SHA256Hasher: Sendable {
    private static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private var state: [UInt32] = SHA256Hasher.initialState
    private var totalBytes: UInt64 = 0
    private var buffer: [UInt8] = []

    public init() {
        buffer.reserveCapacity(64)
    }

    public mutating func update(data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuffer.count
            let unsafeBuffer = UnsafeBufferPointer(start: bytes, count: count)
            update(bytes: unsafeBuffer)
        }
    }

    public mutating func update(bytes: UnsafeBufferPointer<UInt8>) {
        totalBytes &+= UInt64(bytes.count)

        for byte in bytes {
            buffer.append(byte)
            if buffer.count == 64 {
                processChunk(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
    }

    public mutating func finalize() -> [UInt8] {
        let messageBitLength = totalBytes &* 8

        buffer.append(0x80)
        while buffer.count % 64 != 56 {
            buffer.append(0)
        }

        let lengthBytes = withUnsafeBytes(of: messageBitLength.bigEndian, Array.init)
        buffer.append(contentsOf: lengthBytes)

        for chunkStart in stride(from: 0, to: buffer.count, by: 64) {
            let chunk = Array(buffer[chunkStart ..< chunkStart + 64])
            processChunk(chunk)
        }

        var digest: [UInt8] = []
        digest.reserveCapacity(32)
        for value in state {
            digest.append(UInt8((value >> 24) & 0xff))
            digest.append(UInt8((value >> 16) & 0xff))
            digest.append(UInt8((value >> 8) & 0xff))
            digest.append(UInt8(value & 0xff))
        }
        return digest
    }

    public mutating func finalizeHexString() -> String {
        finalize().map { String(format: "%02x", $0) }.joined()
    }

    private mutating func processChunk(_ chunk: [UInt8]) {
        precondition(chunk.count == 64)

        var words = [UInt32](repeating: 0, count: 64)
        for index in 0 ..< 16 {
            let base = index * 4
            let value = (UInt32(chunk[base]) << 24)
                | (UInt32(chunk[base + 1]) << 16)
                | (UInt32(chunk[base + 2]) << 8)
                | UInt32(chunk[base + 3])
            words[index] = value
        }

        for index in 16 ..< 64 {
            let s0 = smallSigma0(words[index - 15])
            let s1 = smallSigma1(words[index - 2])
            words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
        }

        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]
        var e = state[4]
        var f = state[5]
        var g = state[6]
        var h = state[7]

        for index in 0 ..< 64 {
            let t1 = h &+ bigSigma1(e) &+ choose(e, f, g) &+ SHA256Hasher.roundConstants[index] &+ words[index]
            let t2 = bigSigma0(a) &+ majority(a, b, c)
            h = g
            g = f
            f = e
            e = d &+ t1
            d = c
            c = b
            b = a
            a = t1 &+ t2
        }

        state[0] = state[0] &+ a
        state[1] = state[1] &+ b
        state[2] = state[2] &+ c
        state[3] = state[3] &+ d
        state[4] = state[4] &+ e
        state[5] = state[5] &+ f
        state[6] = state[6] &+ g
        state[7] = state[7] &+ h
    }
}

public enum SHA256 {
    public static func hexDigest(of data: Data) -> String {
        var hasher = SHA256Hasher()
        hasher.update(data: data)
        return hasher.finalizeHexString()
    }

    public static func hexDigest(ofFileAt url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw error
        }

        defer {
            try? handle.close()
        }

        var hasher = SHA256Hasher()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalizeHexString()
    }
}

@inline(__always)
private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
}

@inline(__always)
private func choose(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
    (x & y) ^ (~x & z)
}

@inline(__always)
private func majority(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
    (x & y) ^ (x & z) ^ (y & z)
}

@inline(__always)
private func bigSigma0(_ x: UInt32) -> UInt32 {
    rotateRight(x, by: 2) ^ rotateRight(x, by: 13) ^ rotateRight(x, by: 22)
}

@inline(__always)
private func bigSigma1(_ x: UInt32) -> UInt32 {
    rotateRight(x, by: 6) ^ rotateRight(x, by: 11) ^ rotateRight(x, by: 25)
}

@inline(__always)
private func smallSigma0(_ x: UInt32) -> UInt32 {
    rotateRight(x, by: 7) ^ rotateRight(x, by: 18) ^ (x >> 3)
}

@inline(__always)
private func smallSigma1(_ x: UInt32) -> UInt32 {
    rotateRight(x, by: 17) ^ rotateRight(x, by: 19) ^ (x >> 10)
}
