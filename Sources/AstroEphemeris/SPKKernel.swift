import Foundation
import AstroSchemas

public struct SPKKernel: Sendable {
    static let recordSizeBytes = 1024
    static let recordSizeWords = 128
    static let j2000JulianDay = 2_451_545.0
    static let secondsPerDay = 86_400.0
    static let maximumResolutionDepth = 32

    public let url: URL?
    public let header: DAFFileHeader
    public let segments: [SPKSegmentDescriptor]

    private let data: Data
    private let endianness: DAFEndianness
    private let descriptorsByTarget: [Int: [SPKSegmentDescriptor]]

    public init(url: URL) throws {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count >= Self.recordSizeBytes else {
            throw SPKKernelError.unreadableFile
        }

        try self.init(data: data, sourceURL: url)
    }

    public init(data: Data, sourceURL: URL? = nil) throws {
        guard data.count >= Self.recordSizeBytes else {
            throw SPKKernelError.unreadableFile
        }

        let header = try Self.parseHeader(in: data)
        let endianness = try Self.detectEndianness(in: data, headerHint: header.binaryFormat)
        let segments = try Self.parseSegments(in: data, endianness: endianness, header: header)

        self.url = sourceURL
        self.header = header
        self.segments = segments
        self.data = data
        self.endianness = endianness
        self.descriptorsByTarget = Dictionary(grouping: segments, by: \.targetNAIFID)
    }

    public var supportedNAIFBodies: Set<Int> {
        Set(descriptorsByTarget.keys)
    }

    public var looksLikeSPK: Bool {
        header.idWord.hasPrefix("DAF/SPK")
    }

    public func hasBody(_ body: NAIFBody) -> Bool {
        hasNAIFBody(body.rawValue)
    }

    public func hasNAIFBody(_ naifID: Int) -> Bool {
        supportedNAIFBodies.contains(naifID)
    }

    public func coverageEnvelope(for body: NAIFBody) -> ClosedRange<Double>? {
        coverageEnvelope(naifID: body.rawValue)
    }

    public func coverageEnvelope(naifID: Int) -> ClosedRange<Double>? {
        guard let descriptors = descriptorsByTarget[naifID], !descriptors.isEmpty else {
            return nil
        }

        let lowerBound = descriptors.map(\.startETSecondsPastJ2000).min()!
        let upperBound = descriptors.map(\.endETSecondsPastJ2000).max()!
        return lowerBound ... upperBound
    }

    public func stateVector(for body: NAIFBody, tdbJulianDay: Double) throws -> StateVector {
        try stateVector(naifID: body.rawValue, tdbJulianDay: tdbJulianDay)
    }

    public func stateVector(naifID: Int, tdbJulianDay: Double) throws -> StateVector {
        let et = Self.etSecondsPastJ2000(fromTDBJulianDay: tdbJulianDay)
        return try stateVector(naifID: naifID, etSecondsPastJ2000: et)
    }

    public func stateVector(for body: NAIFBody, etSecondsPastJ2000: Double) throws -> StateVector {
        try stateVector(naifID: body.rawValue, etSecondsPastJ2000: etSecondsPastJ2000)
    }

    public func stateVector(naifID: Int, etSecondsPastJ2000: Double) throws -> StateVector {
        var cache: [Int: StateVector] = [NAIFBody.solarSystemBarycenter.rawValue: .zero]
        return try resolveState(
            naifID: naifID,
            etSecondsPastJ2000: etSecondsPastJ2000,
            cache: &cache,
            depth: 0
        )
    }

    private func resolveState(
        naifID: Int,
        etSecondsPastJ2000: Double,
        cache: inout [Int: StateVector],
        depth: Int
    ) throws -> StateVector {
        if let cached = cache[naifID] {
            return cached
        }

        guard depth < Self.maximumResolutionDepth else {
            throw SPKKernelError.recursionLimitExceeded
        }

        // SPK segments are relative to a center body, so a public state-vector lookup
        // can recurse through several centers before reaching the solar-system
        // barycenter. The per-call cache keeps sibling lookups from re-walking the
        // same chain and is part of the correctness story, not just a micro-opt.
        guard let descriptor = bestDescriptor(target: naifID, etSecondsPastJ2000: etSecondsPastJ2000) else {
            throw SPKKernelError.bodyNotFound(
                body: naifID,
                tdbJulianDay: Self.tdbJulianDay(fromETSecondsPastJ2000: etSecondsPastJ2000)
            )
        }

        let relativeState = try evaluate(descriptor: descriptor, etSecondsPastJ2000: etSecondsPastJ2000)
        let centerState = try resolveState(
            naifID: descriptor.centerNAIFID,
            etSecondsPastJ2000: etSecondsPastJ2000,
            cache: &cache,
            depth: depth + 1
        )

        let resolved = relativeState + centerState
        cache[naifID] = resolved
        return resolved
    }

    private func bestDescriptor(target: Int, etSecondsPastJ2000: Double) -> SPKSegmentDescriptor? {
        guard let descriptors = descriptorsByTarget[target] else {
            return nil
        }

        return descriptors.reversed().first {
            etSecondsPastJ2000 >= $0.startETSecondsPastJ2000 && etSecondsPastJ2000 <= $0.endETSecondsPastJ2000
        }
    }

    private func evaluate(descriptor: SPKSegmentDescriptor, etSecondsPastJ2000: Double) throws -> StateVector {
        guard descriptor.frameNAIFID == 1 else {
            throw SPKKernelError.malformedKernel("Unsupported SPK frame ID: \(descriptor.frameNAIFID)")
        }

        switch descriptor.dataType {
        case 2:
            return try evaluateType2(descriptor: descriptor, etSecondsPastJ2000: etSecondsPastJ2000)
        default:
            throw SPKKernelError.unsupportedSegmentType(descriptor.dataType)
        }
    }

    private func evaluateType2(descriptor: SPKSegmentDescriptor, etSecondsPastJ2000: Double) throws -> StateVector {
        let initialEpoch = try readDouble(atAddress: descriptor.finalAddress - 3)
        let intervalLength = try readDouble(atAddress: descriptor.finalAddress - 2)
        let recordSize = Int(round(try readDouble(atAddress: descriptor.finalAddress - 1)))
        let recordCount = Int(round(try readDouble(atAddress: descriptor.finalAddress)))

        guard intervalLength > 0, recordSize > 2, recordCount > 0 else {
            throw SPKKernelError.malformedKernel("Invalid Type 2 segment directory values.")
        }

        let expectedWordCount = recordCount * recordSize + 4
        let actualWordCount = descriptor.finalAddress - descriptor.initialAddress + 1
        guard actualWordCount == expectedWordCount else {
            throw SPKKernelError.malformedKernel(
                "Type 2 descriptor/address size mismatch for segment \(descriptor.name)."
            )
        }

        var recordIndex = Int(floor((etSecondsPastJ2000 - initialEpoch) / intervalLength))
        if recordIndex < 0 { recordIndex = 0 }
        if recordIndex >= recordCount { recordIndex = recordCount - 1 }

        let recordStartAddress = descriptor.initialAddress + recordIndex * recordSize
        let midpoint = try readDouble(atAddress: recordStartAddress)
        let radius = try readDouble(atAddress: recordStartAddress + 1)

        guard radius > 0 else {
            throw SPKKernelError.malformedKernel("Invalid Type 2 record radius.")
        }

        let coefficientCount = (recordSize - 2) / 3
        guard coefficientCount > 0, (2 + 3 * coefficientCount) == recordSize else {
            throw SPKKernelError.malformedKernel("Invalid Type 2 coefficient packing.")
        }

        let xCoefficients = try readDoubles(atAddress: recordStartAddress + 2, count: coefficientCount)
        let yCoefficients = try readDoubles(atAddress: recordStartAddress + 2 + coefficientCount, count: coefficientCount)
        let zCoefficients = try readDoubles(atAddress: recordStartAddress + 2 + 2 * coefficientCount, count: coefficientCount)

        let normalizedTime = min(1.0, max(-1.0, (etSecondsPastJ2000 - midpoint) / radius))

        let x = Chebyshev.evaluateWithDerivative(coefficients: xCoefficients, x: normalizedTime)
        let y = Chebyshev.evaluateWithDerivative(coefficients: yCoefficients, x: normalizedTime)
        let z = Chebyshev.evaluateWithDerivative(coefficients: zCoefficients, x: normalizedTime)

        return StateVector(
            positionX: x.value,
            positionY: y.value,
            positionZ: z.value,
            velocityX: x.derivative / radius,
            velocityY: y.derivative / radius,
            velocityZ: z.derivative / radius
        )
    }

    private func readDouble(atAddress address: Int) throws -> Double {
        guard address >= 1 else {
            throw SPKKernelError.malformedKernel("Invalid DAF address: \(address)")
        }

        let byteOffset = (address - 1) * MemoryLayout<Double>.size
        return try Self.readDouble(in: data, byteOffset: byteOffset, endianness: endianness)
    }

    private func readDoubles(atAddress startAddress: Int, count: Int) throws -> [Double] {
        guard count >= 0 else {
            throw SPKKernelError.malformedKernel("Negative DAF read count.")
        }

        return try (0 ..< count).map { index in
            try readDouble(atAddress: startAddress + index)
        }
    }
}

private extension SPKKernel {
    static func parseHeader(in data: Data) throws -> DAFFileHeader {
        let idWord = ascii(in: data, byteOffset: 0, length: 8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard idWord.hasPrefix("DAF/SPK") else {
            throw SPKKernelError.invalidHeader
        }

        let binaryFormat = ascii(in: data, byteOffset: 88, length: 8).trimmingCharacters(in: .whitespacesAndNewlines)
        let endianness = try detectEndianness(in: data, headerHint: binaryFormat)

        let nd = Int(try readInt32(in: data, byteOffset: 8, endianness: endianness))
        let ni = Int(try readInt32(in: data, byteOffset: 12, endianness: endianness))
        let firstSummaryRecord = Int(try readInt32(in: data, byteOffset: 76, endianness: endianness))
        let lastSummaryRecord = Int(try readInt32(in: data, byteOffset: 80, endianness: endianness))
        let firstFreeAddress = Int(try readInt32(in: data, byteOffset: 84, endianness: endianness))
        let internalFileName = ascii(in: data, byteOffset: 16, length: 60)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0\n\r\t"))

        guard nd == 2, ni == 6 else {
            throw SPKKernelError.malformedKernel("This Stage 2 reader supports only ND=2 and NI=6 SPK summaries.")
        }

        guard firstSummaryRecord >= 0, lastSummaryRecord >= 0, firstFreeAddress >= 1 else {
            throw SPKKernelError.malformedKernel("Invalid file-record control addresses.")
        }

        return DAFFileHeader(
            idWord: idWord,
            nd: nd,
            ni: ni,
            internalFileName: internalFileName,
            firstSummaryRecord: firstSummaryRecord,
            lastSummaryRecord: lastSummaryRecord,
            firstFreeAddress: firstFreeAddress,
            binaryFormat: binaryFormat
        )
    }

    static func detectEndianness(in data: Data, headerHint: String) throws -> DAFEndianness {
        let normalizedHint = headerHint.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedHint.hasPrefix("LTL-IEEE") {
            return .littleIEEE
        }

        if normalizedHint.hasPrefix("BIG-IEEE") {
            return .bigIEEE
        }

        let ndLittle = try? readInt32(in: data, byteOffset: 8, endianness: .littleIEEE)
        let niLittle = try? readInt32(in: data, byteOffset: 12, endianness: .littleIEEE)
        if ndLittle == 2, niLittle == 6 {
            return .littleIEEE
        }

        let ndBig = try? readInt32(in: data, byteOffset: 8, endianness: .bigIEEE)
        let niBig = try? readInt32(in: data, byteOffset: 12, endianness: .bigIEEE)
        if ndBig == 2, niBig == 6 {
            return .bigIEEE
        }

        throw SPKKernelError.unsupportedBinaryFormat(normalizedHint)
    }

    static func parseSegments(in data: Data, endianness: DAFEndianness, header: DAFFileHeader) throws -> [SPKSegmentDescriptor] {
        guard header.firstSummaryRecord != 0 else {
            return []
        }

        let summarySizeDoubles = header.nd + ((header.ni + 1) / 2)
        let nameLength = 8 * summarySizeDoubles
        let maximumSummariesPerRecord = (recordSizeWords - 3) / summarySizeDoubles

        var segments: [SPKSegmentDescriptor] = []
        var currentSummaryRecord = header.firstSummaryRecord
        var visitedRecords = Set<Int>()

        while currentSummaryRecord != 0 {
            guard visitedRecords.insert(currentSummaryRecord).inserted else {
                throw SPKKernelError.malformedKernel("Summary record cycle detected.")
            }

            let summaryRecordOffset = try byteOffset(forRecord: currentSummaryRecord, dataCount: data.count)
            let nextSummaryRecord = Int(round(try readDouble(in: data, byteOffset: summaryRecordOffset, endianness: endianness)))
            let summaryCount = Int(round(try readDouble(in: data, byteOffset: summaryRecordOffset + 16, endianness: endianness)))

            guard (0 ... maximumSummariesPerRecord).contains(summaryCount) else {
                throw SPKKernelError.malformedKernel("Invalid summary count in record \(currentSummaryRecord).")
            }

            let nameRecordOffset = try byteOffset(forRecord: currentSummaryRecord + 1, dataCount: data.count)

            for index in 0 ..< summaryCount {
                let descriptorByteOffset = summaryRecordOffset + 24 + index * summarySizeDoubles * MemoryLayout<Double>.size
                let startET = try readDouble(in: data, byteOffset: descriptorByteOffset, endianness: endianness)
                let endET = try readDouble(in: data, byteOffset: descriptorByteOffset + 8, endianness: endianness)
                let packedIntegers = try readInt32s(
                    in: data,
                    byteOffset: descriptorByteOffset + header.nd * MemoryLayout<Double>.size,
                    count: header.ni,
                    endianness: endianness
                )

                let nameOffset = nameRecordOffset + index * nameLength
                let name = ascii(in: data, byteOffset: nameOffset, length: nameLength)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \0\n\r\t"))

                let descriptor = SPKSegmentDescriptor(
                    name: name,
                    startETSecondsPastJ2000: startET,
                    endETSecondsPastJ2000: endET,
                    targetNAIFID: Int(packedIntegers[0]),
                    centerNAIFID: Int(packedIntegers[1]),
                    frameNAIFID: Int(packedIntegers[2]),
                    dataType: Int(packedIntegers[3]),
                    initialAddress: Int(packedIntegers[4]),
                    finalAddress: Int(packedIntegers[5])
                )

                guard descriptor.initialAddress >= 1, descriptor.finalAddress >= descriptor.initialAddress else {
                    throw SPKKernelError.malformedKernel("Invalid DAF addresses in segment \(name).")
                }

                segments.append(descriptor)
            }

            currentSummaryRecord = nextSummaryRecord
        }

        return segments
    }

    static func byteOffset(forRecord recordNumber: Int, dataCount: Int) throws -> Int {
        guard recordNumber >= 1 else {
            throw SPKKernelError.malformedKernel("Invalid record number: \(recordNumber)")
        }

        let offset = (recordNumber - 1) * recordSizeBytes
        guard offset + recordSizeBytes <= dataCount else {
            throw SPKKernelError.malformedKernel("Record \(recordNumber) exceeds file size.")
        }

        return offset
    }

    static func ascii(in data: Data, byteOffset: Int, length: Int) -> String {
        guard byteOffset >= 0, length >= 0, byteOffset + length <= data.count else {
            return ""
        }

        return String(decoding: data[byteOffset ..< (byteOffset + length)], as: UTF8.self)
    }

    static func readDouble(in data: Data, byteOffset: Int, endianness: DAFEndianness) throws -> Double {
        let raw = try readUInt64(in: data, byteOffset: byteOffset, endianness: endianness)
        return Double(bitPattern: raw)
    }

    static func readInt32(in data: Data, byteOffset: Int, endianness: DAFEndianness) throws -> Int32 {
        guard byteOffset >= 0, byteOffset + 4 <= data.count else {
            throw SPKKernelError.malformedKernel("Read beyond file bounds at byte offset \(byteOffset).")
        }

        let b0 = UInt32(data[byteOffset])
        let b1 = UInt32(data[byteOffset + 1])
        let b2 = UInt32(data[byteOffset + 2])
        let b3 = UInt32(data[byteOffset + 3])

        let raw: UInt32
        switch endianness {
        case .littleIEEE:
            raw = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        case .bigIEEE:
            raw = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }

        return Int32(bitPattern: raw)
    }

    static func readInt32s(in data: Data, byteOffset: Int, count: Int, endianness: DAFEndianness) throws -> [Int32] {
        guard count >= 0 else {
            throw SPKKernelError.malformedKernel("Negative Int32 read count.")
        }

        return try (0 ..< count).map { index in
            try readInt32(in: data, byteOffset: byteOffset + index * 4, endianness: endianness)
        }
    }

    static func readUInt64(in data: Data, byteOffset: Int, endianness: DAFEndianness) throws -> UInt64 {
        guard byteOffset >= 0, byteOffset + 8 <= data.count else {
            throw SPKKernelError.malformedKernel("Read beyond file bounds at byte offset \(byteOffset).")
        }

        let b0 = UInt64(data[byteOffset])
        let b1 = UInt64(data[byteOffset + 1])
        let b2 = UInt64(data[byteOffset + 2])
        let b3 = UInt64(data[byteOffset + 3])
        let b4 = UInt64(data[byteOffset + 4])
        let b5 = UInt64(data[byteOffset + 5])
        let b6 = UInt64(data[byteOffset + 6])
        let b7 = UInt64(data[byteOffset + 7])

        switch endianness {
        case .littleIEEE:
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56)
        case .bigIEEE:
            return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) | (b4 << 24) | (b5 << 16) | (b6 << 8) | b7
        }
    }

    static func etSecondsPastJ2000(fromTDBJulianDay tdbJulianDay: Double) -> Double {
        (tdbJulianDay - j2000JulianDay) * secondsPerDay
    }

    static func tdbJulianDay(fromETSecondsPastJ2000 et: Double) -> Double {
        (et / secondsPerDay) + j2000JulianDay
    }
}

private extension StateVector {
    static let zero = StateVector(
        positionX: 0,
        positionY: 0,
        positionZ: 0,
        velocityX: 0,
        velocityY: 0,
        velocityZ: 0
    )

    static func + (lhs: StateVector, rhs: StateVector) -> StateVector {
        StateVector(
            positionX: lhs.positionX + rhs.positionX,
            positionY: lhs.positionY + rhs.positionY,
            positionZ: lhs.positionZ + rhs.positionZ,
            velocityX: lhs.velocityX + rhs.velocityX,
            velocityY: lhs.velocityY + rhs.velocityY,
            velocityZ: lhs.velocityZ + rhs.velocityZ
        )
    }
}
