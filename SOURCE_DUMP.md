# AstroNatalEngine Stage 2 Source Dump

## Package.swift

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AstroNatalEngine",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AstroNatalEngine",
            targets: ["AstroNatalEngine"]
        )
    ],
    targets: [
        .target(
            name: "AstroSchemas"
        ),
        .target(
            name: "AstroRuntimeData",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroEphemeris",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroNatalEngine",
            dependencies: [
                "AstroSchemas",
                "AstroRuntimeData",
                "AstroEphemeris"
            ]
        ),
        .testTarget(
            name: "AstroSchemasTests",
            dependencies: ["AstroSchemas"]
        ),
        .testTarget(
            name: "AstroRuntimeDataTests",
            dependencies: [
                "AstroRuntimeData",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroEphemerisTests",
            dependencies: [
                "AstroEphemeris",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroNatalEngineTests",
            dependencies: [
                "AstroNatalEngine",
                "AstroSchemas",
                "AstroRuntimeData",
                "AstroEphemeris"
            ]
        )
    ]
)
```

## README.md

```swift
# AstroNatalEngine

A pure-Swift natal-chart engine package organized around a runtime-downloaded data model.

Current package status:
- Stage 1: schemas, facade, `prepare()` state machine, runtime data manifest and pack storage
- Stage 2: `AstroEphemeris` module with a minimum DAF/SPK reader, Type 2 Chebyshev evaluation, and regression tests for Sun, Earth, and Moon state-vector lookup

Notes:
- The `AstroEphemeris` module intentionally implements only the minimum subset needed for the project standard.
- The package includes an optional `de442.bsp` smoke test that runs only when `ASTRO_DE442_PATH` points at a real kernel on disk.
- Time conversion, frame conversion, houses, and final chart assembly remain later stages.
```

## Sources/AstroEphemeris/Chebyshev.swift

```swift
import Foundation

struct Chebyshev {
    struct EvaluationResult: Sendable, Equatable {
        let value: Double
        let derivative: Double
    }

    /// Evaluates a Chebyshev series and its derivative with respect to the
    /// normalized independent variable `x` in the interval [-1, 1].
    ///
    /// The SPK Type 2 evaluator later divides the derivative by the record radius
    /// to convert from d/dx to d/dt.
    static func evaluateWithDerivative(coefficients: [Double], x: Double) -> EvaluationResult {
        guard !coefficients.isEmpty else {
            return EvaluationResult(value: 0, derivative: 0)
        }

        if coefficients.count == 1 {
            return EvaluationResult(value: coefficients[0], derivative: 0)
        }

        var value = coefficients[0] + coefficients[1] * x
        var derivative = coefficients[1]

        var tMinusTwo = 1.0
        var tMinusOne = x

        // U_0(x) = 1. For n >= 2, dT_n/dx = n * U_{n-1}(x).
        var uMinusTwo = 1.0
        var uMinusOne = 2.0 * x

        if coefficients.count == 2 {
            return EvaluationResult(value: value, derivative: derivative)
        }

        for degree in 2 ..< coefficients.count {
            let t = 2.0 * x * tMinusOne - tMinusTwo
            value += coefficients[degree] * t
            derivative += Double(degree) * coefficients[degree] * uMinusOne

            let u = 2.0 * x * uMinusOne - uMinusTwo
            tMinusTwo = tMinusOne
            tMinusOne = t
            uMinusTwo = uMinusOne
            uMinusOne = u
        }

        return EvaluationResult(value: value, derivative: derivative)
    }
}
```

## Sources/AstroEphemeris/JPLEphemerisProvider.swift

```swift
import Foundation
import AstroSchemas

/// Thin Stage 2 provider that adapts the low-level SPK kernel to the public
/// `EphemerisProvider` protocol used by the engine facade.
///
/// Returned state vectors are barycentric J2000 Cartesian states in kilometers
/// and kilometers per second. Later stages will convert these into geocentric
/// apparent ecliptic quantities.
public struct JPLEphemerisProvider: EphemerisProvider, Sendable {
    public let kernel: SPKKernel

    public init(kernel: SPKKernel) {
        self.kernel = kernel
    }

    public init(kernelURL: URL) throws {
        self.kernel = try SPKKernel(url: kernelURL)
    }

    public func stateVector(for body: BodyID, tdbJulianDay: Double) throws -> StateVector {
        try stateVector(forPreferredTargets: NAIFBody.preferredTargets(for: body), tdbJulianDay: tdbJulianDay)
    }

    public func earthStateVector(tdbJulianDay: Double) throws -> StateVector {
        try stateVector(forPreferredTargets: [.earth, .earthMoonBarycenter], tdbJulianDay: tdbJulianDay)
    }

    public func stateVector(forNAIFBody body: NAIFBody, tdbJulianDay: Double) throws -> StateVector {
        try translateKernelError {
            try kernel.stateVector(for: body, tdbJulianDay: tdbJulianDay)
        }
    }

    public func hasNAIFBody(_ body: NAIFBody) -> Bool {
        kernel.hasBody(body)
    }

    private func stateVector(forPreferredTargets targets: [NAIFBody], tdbJulianDay: Double) throws -> StateVector {
        var sawSupportedTarget = false

        for target in targets {
            guard kernel.hasBody(target) else {
                continue
            }

            sawSupportedTarget = true
            do {
                return try kernel.stateVector(for: target, tdbJulianDay: tdbJulianDay)
            } catch let error as SPKKernelError {
                switch error {
                case .bodyNotFound:
                    continue
                default:
                    throw translateKernelError(error)
                }
            }
        }

        if sawSupportedTarget {
            throw NatalEngineError.kernelOutOfRange
        }

        if let primaryTarget = targets.first {
            throw SPKKernelError.bodyNotFound(body: primaryTarget.rawValue, tdbJulianDay: tdbJulianDay)
        }

        throw NatalEngineError.kernelOutOfRange
    }

    private func translateKernelError<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SPKKernelError {
            throw translateKernelError(error)
        }
    }

    private func translateKernelError(_ error: SPKKernelError) -> Error {
        switch error {
        case .bodyNotFound:
            return NatalEngineError.kernelOutOfRange
        default:
            return error
        }
    }
}
```

## Sources/AstroEphemeris/KernelTypes.swift

```swift
import Foundation

public enum SPKKernelError: Error, Sendable, Equatable {
    case unreadableFile
    case invalidHeader
    case unsupportedBinaryFormat(String)
    case malformedKernel(String)
    case unsupportedSegmentType(Int)
    case bodyNotFound(body: Int, tdbJulianDay: Double)
    case recursionLimitExceeded
}

extension SPKKernelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The SPK kernel file could not be read."
        case .invalidHeader:
            return "The file does not look like a DAF/SPK kernel."
        case let .unsupportedBinaryFormat(format):
            return "Unsupported DAF binary format: \(format)."
        case let .malformedKernel(message):
            return "Malformed SPK kernel: \(message)"
        case let .unsupportedSegmentType(type):
            return "Unsupported SPK segment type: \(type)."
        case let .bodyNotFound(body, tdbJulianDay):
            return "No segment covers NAIF body \(body) at TDB Julian day \(tdbJulianDay)."
        case .recursionLimitExceeded:
            return "Kernel body-center recursion limit exceeded."
        }
    }
}

enum DAFEndianness: Sendable, Equatable {
    case littleIEEE
    case bigIEEE
}

public struct DAFFileHeader: Sendable, Equatable {
    public let idWord: String
    public let nd: Int
    public let ni: Int
    public let internalFileName: String
    public let firstSummaryRecord: Int
    public let lastSummaryRecord: Int
    public let firstFreeAddress: Int
    public let binaryFormat: String

    public init(
        idWord: String,
        nd: Int,
        ni: Int,
        internalFileName: String,
        firstSummaryRecord: Int,
        lastSummaryRecord: Int,
        firstFreeAddress: Int,
        binaryFormat: String
    ) {
        self.idWord = idWord
        self.nd = nd
        self.ni = ni
        self.internalFileName = internalFileName
        self.firstSummaryRecord = firstSummaryRecord
        self.lastSummaryRecord = lastSummaryRecord
        self.firstFreeAddress = firstFreeAddress
        self.binaryFormat = binaryFormat
    }
}

public struct SPKSegmentDescriptor: Sendable, Equatable {
    public let name: String
    public let startETSecondsPastJ2000: Double
    public let endETSecondsPastJ2000: Double
    public let targetNAIFID: Int
    public let centerNAIFID: Int
    public let frameNAIFID: Int
    public let dataType: Int
    public let initialAddress: Int
    public let finalAddress: Int

    public init(
        name: String,
        startETSecondsPastJ2000: Double,
        endETSecondsPastJ2000: Double,
        targetNAIFID: Int,
        centerNAIFID: Int,
        frameNAIFID: Int,
        dataType: Int,
        initialAddress: Int,
        finalAddress: Int
    ) {
        self.name = name
        self.startETSecondsPastJ2000 = startETSecondsPastJ2000
        self.endETSecondsPastJ2000 = endETSecondsPastJ2000
        self.targetNAIFID = targetNAIFID
        self.centerNAIFID = centerNAIFID
        self.frameNAIFID = frameNAIFID
        self.dataType = dataType
        self.initialAddress = initialAddress
        self.finalAddress = finalAddress
    }
}
```

## Sources/AstroEphemeris/NAIFBody.swift

```swift
import Foundation
import AstroSchemas

/// The subset of NAIF body identifiers needed for the engine's natal-chart pipeline.
///
/// The generic JPL planetary kernels expose barycenters for most planetary systems,
/// along with direct bodies for the Sun, Earth, Moon, Mercury, and Venus. For the
/// outer planets, using the system barycenter is the accepted Stage 2 approximation;
/// later stages can layer additional satellite kernels if a future product version
/// ever requires planet-center reconstruction.
public enum NAIFBody: Int, Sendable, Codable, CaseIterable {
    case solarSystemBarycenter = 0
    case mercuryBarycenter = 1
    case venusBarycenter = 2
    case earthMoonBarycenter = 3
    case marsBarycenter = 4
    case jupiterBarycenter = 5
    case saturnBarycenter = 6
    case uranusBarycenter = 7
    case neptuneBarycenter = 8
    case plutoBarycenter = 9
    case sun = 10

    case mercury = 199
    case venus = 299
    case moon = 301
    case earth = 399
    case mars = 499
    case jupiter = 599
    case saturn = 699
    case uranus = 799
    case neptune = 899
    case pluto = 999

    public var displayName: String {
        switch self {
        case .solarSystemBarycenter: return "Solar System Barycenter"
        case .mercuryBarycenter: return "Mercury Barycenter"
        case .venusBarycenter: return "Venus Barycenter"
        case .earthMoonBarycenter: return "Earth-Moon Barycenter"
        case .marsBarycenter: return "Mars Barycenter"
        case .jupiterBarycenter: return "Jupiter Barycenter"
        case .saturnBarycenter: return "Saturn Barycenter"
        case .uranusBarycenter: return "Uranus Barycenter"
        case .neptuneBarycenter: return "Neptune Barycenter"
        case .plutoBarycenter: return "Pluto Barycenter"
        case .sun: return "Sun"
        case .mercury: return "Mercury"
        case .venus: return "Venus"
        case .moon: return "Moon"
        case .earth: return "Earth"
        case .mars: return "Mars"
        case .jupiter: return "Jupiter"
        case .saturn: return "Saturn"
        case .uranus: return "Uranus"
        case .neptune: return "Neptune"
        case .pluto: return "Pluto"
        }
    }
}

extension NAIFBody {
    static func preferredTargets(for body: BodyID) -> [NAIFBody] {
        switch body {
        case .sun:
            return [.sun]
        case .moon:
            return [.moon]
        case .mercury:
            return [.mercury, .mercuryBarycenter]
        case .venus:
            return [.venus, .venusBarycenter]
        case .mars:
            return [.mars, .marsBarycenter]
        case .jupiter:
            return [.jupiter, .jupiterBarycenter]
        case .saturn:
            return [.saturn, .saturnBarycenter]
        case .uranus:
            return [.uranus, .uranusBarycenter]
        case .neptune:
            return [.neptune, .neptuneBarycenter]
        case .pluto:
            return [.pluto, .plutoBarycenter]
        }
    }
}
```

## Sources/AstroEphemeris/SPKKernel.swift

```swift
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
```

## Sources/AstroNatalEngine/Exports.swift

```swift
@_exported import AstroSchemas
@_exported import AstroRuntimeData
@_exported import AstroEphemeris
```

## Sources/AstroNatalEngine/NatalChartComputer.swift

```swift
import Foundation
import AstroSchemas

public struct NatalEngineEnvironment: Sendable, Equatable {
    public let engineVersion: String
    public let dataVersions: EngineDataVersions

    public init(engineVersion: String, dataVersions: EngineDataVersions) {
        self.engineVersion = engineVersion
        self.dataVersions = dataVersions
    }
}

public protocol NatalChartComputer: Sendable {
    func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse
}

public struct StubNatalChartComputer: NatalChartComputer {
    public init() {}

    public func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        _ = request
        _ = environment
        throw NatalEngineError.featureNotImplemented(
            "Chart computation begins in later stages (ephemeris, time axis, frames, and houses)."
        )
    }
}
```

## Sources/AstroNatalEngine/NatalChartEngine.swift

```swift
import Foundation
import AstroSchemas

public actor NatalChartEngine {
    private enum PreparationState {
        case idle
        case preparing(Task<NatalEngineEnvironment, Error>)
        case ready(NatalEngineEnvironment)
    }

    private let configuration: NatalEngineConfiguration
    private var preparationState: PreparationState = .idle

    public init(configuration: NatalEngineConfiguration) {
        self.configuration = configuration
    }

    public func prepare() async throws {
        switch preparationState {
        case .ready:
            return
        case let .preparing(task):
            _ = try await task.value
        case .idle:
            let task = Task { [configuration] in
                try await configuration.dataPackStore.ensureReady()
                let dataVersions = try await configuration.dataPackStore.installedDataVersions()
                return NatalEngineEnvironment(
                    engineVersion: configuration.engineVersion,
                    dataVersions: dataVersions
                )
            }
            preparationState = .preparing(task)
            do {
                let environment = try await task.value
                preparationState = .ready(environment)
            } catch {
                preparationState = .idle
                throw error
            }
        }
    }

    public func generate(_ request: ResolvedBirthRequest) async throws -> NatalChartResponse {
        try RequestValidator.validate(request)
        let environment = try preparedEnvironment()
        return try await configuration.chartComputer.generate(request: request, environment: environment)
    }

    public func generate(_ request: RawBirthRequest) async throws -> NatalChartResponse {
        try RequestValidator.validate(request)
        let resolved = try await configuration.birthResolver.resolve(request)
        return try await generate(resolved)
    }

    public func generateJSON(_ requestData: Data) async throws -> Data {
        let response: NatalChartResponse
        let decoder = JSONDecoder()

        if let resolved = try? decoder.decode(ResolvedBirthRequest.self, from: requestData) {
            response = try await generate(resolved)
        } else if let raw = try? decoder.decode(RawBirthRequest.self, from: requestData) {
            response = try await generate(raw)
        } else {
            throw NatalEngineError.malformedRequest("Input data is neither natal.raw.v1 nor natal.resolved.v1.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(response)
    }

    public func preparedDataVersions() throws -> EngineDataVersions {
        try preparedEnvironment().dataVersions
    }

    private func preparedEnvironment() throws -> NatalEngineEnvironment {
        switch preparationState {
        case let .ready(environment):
            return environment
        case .idle, .preparing:
            throw NatalEngineError.engineNotPrepared
        }
    }
}
```

## Sources/AstroNatalEngine/NatalEngineConfiguration.swift

```swift
import Foundation
import AstroSchemas
import AstroRuntimeData

public struct NatalEngineConfiguration: Sendable {
    public let engineVersion: String
    public let birthResolver: any BirthResolver
    public let dataPackStore: any DataPackStore
    public let chartComputer: any NatalChartComputer

    public init(
        engineVersion: String = "0.2.0-stage2",
        birthResolver: any BirthResolver,
        dataPackStore: any DataPackStore,
        chartComputer: any NatalChartComputer = StubNatalChartComputer()
    ) {
        self.engineVersion = engineVersion
        self.birthResolver = birthResolver
        self.dataPackStore = dataPackStore
        self.chartComputer = chartComputer
    }
}

public extension NatalEngineConfiguration {
    static func stage2(
        engineVersion: String = "0.2.0-stage2",
        manifestURL: URL?,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        chartComputer: any NatalChartComputer = StubNatalChartComputer()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: chartComputer
        )
    }

    static func stage1(
        engineVersion: String = "0.1.0-stage1",
        manifestURL: URL?,
        baseDirectory: URL = PackStorageLayout.defaultBaseDirectory(),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        runtimeDataOptions: FileSystemDataPackStore.Options = .init(),
        birthResolver: any BirthResolver = StrictBirthResolver(),
        chartComputer: any NatalChartComputer = StubNatalChartComputer()
    ) -> NatalEngineConfiguration {
        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: baseDirectory),
            httpClient: httpClient,
            options: runtimeDataOptions
        )

        return NatalEngineConfiguration(
            engineVersion: engineVersion,
            birthResolver: birthResolver,
            dataPackStore: store,
            chartComputer: chartComputer
        )
    }
}
```

## Sources/AstroNatalEngine/StrictBirthResolver.swift

```swift
import Foundation
import AstroSchemas

public struct StrictBirthResolver: BirthResolver {
    public init() {}

    public func resolve(_ raw: RawBirthRequest) async throws -> ResolvedBirthRequest {
        try RequestValidator.validate(raw)

        guard let offset = raw.birth.utcOffsetMinutesAtBirth else {
            throw NatalEngineError.timezoneUnresolved
        }

        let timeZoneId = raw.birth.timeZoneId ?? Self.syntheticTimeZoneID(offsetMinutes: offset)
        let ambiguityPolicy = raw.birth.ambiguityPolicy ?? .earlier
        let timePrecision = raw.birth.timePrecision ?? .minute

        return ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: raw.birth.localDateTime,
                timeZoneId: timeZoneId,
                utcOffsetMinutesAtBirth: offset,
                ambiguityPolicy: ambiguityPolicy,
                timePrecision: timePrecision
            ),
            location: raw.location,
            subject: raw.subject,
            profile: raw.profile
        )
    }

    private static func syntheticTimeZoneID(offsetMinutes: Int) -> String {
        let sign = offsetMinutes >= 0 ? "+" : "-"
        let absolute = abs(offsetMinutes)
        let hours = absolute / 60
        let minutes = absolute % 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }
}
```

## Sources/AstroRuntimeData/FileSystemDataPackStore.swift

```swift
import Foundation
import AstroSchemas

public actor FileSystemDataPackStore: DataPackStore {
    public struct Options: Sendable, Equatable {
        public let eagerlyDownloadOptionalPackIDs: Set<String>
        public let allowOfflineManifestFallback: Bool
        public let verifyExistingFilesOnPrepare: Bool

        public init(
            eagerlyDownloadOptionalPackIDs: Set<String> = [],
            allowOfflineManifestFallback: Bool = true,
            verifyExistingFilesOnPrepare: Bool = true
        ) {
            self.eagerlyDownloadOptionalPackIDs = eagerlyDownloadOptionalPackIDs
            self.allowOfflineManifestFallback = allowOfflineManifestFallback
            self.verifyExistingFilesOnPrepare = verifyExistingFilesOnPrepare
        }
    }

    private let manifestURL: URL?
    private let layout: PackStorageLayout
    private let httpClient: any RuntimeHTTPClient
    private let options: Options
    private let fileManager: FileManager
    private var cachedManifest: EngineDataManifest?

    public init(
        manifestURL: URL?,
        layout: PackStorageLayout = PackStorageLayout(baseDirectory: PackStorageLayout.defaultBaseDirectory()),
        httpClient: any RuntimeHTTPClient = URLSessionRuntimeHTTPClient(),
        options: Options = Options(),
        fileManager: FileManager = .default
    ) {
        self.manifestURL = manifestURL
        self.layout = layout
        self.httpClient = httpClient
        self.options = options
        self.fileManager = fileManager
    }

    public func ensureReady() async throws {
        try createBaseDirectoriesIfNeeded()
        let manifest = try await loadPreferredManifest()
        try persistManifest(manifest)

        for descriptor in manifest.packs where shouldInstall(descriptor) {
            try await ensurePackAvailable(descriptor)
        }

        for descriptor in manifest.packs where descriptor.required {
            guard fileManager.fileExists(atPath: layout.packFileURL(for: descriptor).path) else {
                throw NatalEngineError.missingRequiredPack(descriptor.id)
            }
        }

        cachedManifest = manifest
    }

    public func installedDataVersions() async throws -> EngineDataVersions {
        if let cachedManifest {
            return cachedManifest.derivedDataVersions()
        }

        let manifest = try loadLocalManifest()
        return manifest.derivedDataVersions()
    }

    private func shouldInstall(_ descriptor: DataPackDescriptor) -> Bool {
        descriptor.required || options.eagerlyDownloadOptionalPackIDs.contains(descriptor.id)
    }

    private func createBaseDirectoriesIfNeeded() throws {
        let directories = [
            layout.baseDirectory,
            layout.packsDirectory,
            layout.cacheDirectory,
            layout.logsDirectory,
            layout.stagingDirectory
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func loadPreferredManifest() async throws -> EngineDataManifest {
        if let manifestURL {
            do {
                let response = try await httpClient.get(manifestURL)
                guard (200 ..< 300).contains(response.statusCode) else {
                    throw NatalEngineError.networkFailure("Manifest download returned HTTP \(response.statusCode).")
                }
                return try decodeManifest(response.data)
            } catch {
                if options.allowOfflineManifestFallback {
                    return try loadLocalManifest()
                }
                if let natalError = error as? NatalEngineError {
                    throw natalError
                }
                throw NatalEngineError.networkFailure(error.localizedDescription)
            }
        }

        return try loadLocalManifest()
    }

    private func loadLocalManifest() throws -> EngineDataManifest {
        guard fileManager.fileExists(atPath: layout.manifestFileURL.path) else {
            throw NatalEngineError.missingRequiredPack("manifest")
        }

        let data = try Data(contentsOf: layout.manifestFileURL)
        return try decodeManifest(data)
    }

    private func decodeManifest(_ data: Data) throws -> EngineDataManifest {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(EngineDataManifest.self, from: data)
        } catch {
            throw NatalEngineError.manifestInvalid(error.localizedDescription)
        }
    }

    private func persistManifest(_ manifest: EngineDataManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: layout.manifestFileURL, options: .atomic)
    }

    private func ensurePackAvailable(_ descriptor: DataPackDescriptor) async throws {
        let destination = layout.packFileURL(for: descriptor)

        if fileManager.fileExists(atPath: destination.path) {
            if options.verifyExistingFilesOnPrepare {
                if try verifyFile(at: destination, descriptor: descriptor) {
                    return
                }
            } else {
                return
            }
        }

        guard let remoteURL = descriptor.remoteURL else {
            throw NatalEngineError.manifestInvalid("Invalid pack URL for \(descriptor.id).")
        }

        let response: HTTPDataResponse
        do {
            response = try await httpClient.get(remoteURL)
        } catch {
            if let natalError = error as? NatalEngineError {
                throw natalError
            }
            throw NatalEngineError.networkFailure(error.localizedDescription)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw NatalEngineError.networkFailure("Pack \(descriptor.id) returned HTTP \(response.statusCode).")
        }

        let stagingURL = layout.stagingDirectory.appendingPathComponent(UUID().uuidString)
        try response.data.write(to: stagingURL, options: .atomic)

        do {
            guard response.data.count == Int(descriptor.bytes) else {
                throw NatalEngineError.manifestInvalid("Byte count mismatch for \(descriptor.id).")
            }

            let digest = try SHA256.hexDigest(ofFileAt: stagingURL)
            guard digest == descriptor.sha256 else {
                throw NatalEngineError.dataPackChecksumMismatch(descriptor.id)
            }

            try fileManager.createDirectory(at: layout.packDirectory(for: descriptor), withIntermediateDirectories: true)
            try replaceItem(at: destination, with: stagingURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func verifyFile(at url: URL, descriptor: DataPackDescriptor) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard bytes == descriptor.bytes else {
            return false
        }

        let digest = try SHA256.hexDigest(ofFileAt: url)
        return digest == descriptor.sha256
    }

    private func replaceItem(at destination: URL, with stagingURL: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            #if canImport(Darwin)
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagingURL)
            #else
            let backupURL = layout.stagingDirectory.appendingPathComponent(UUID().uuidString + ".bak")
            try fileManager.moveItem(at: destination, to: backupURL)
            do {
                try fileManager.moveItem(at: stagingURL, to: destination)
                try? fileManager.removeItem(at: backupURL)
            } catch {
                try? fileManager.moveItem(at: backupURL, to: destination)
                throw error
            }
            #endif
        } else {
            try fileManager.moveItem(at: stagingURL, to: destination)
        }
    }
}
```

## Sources/AstroRuntimeData/HTTPClient.swift

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPDataResponse: Sendable, Equatable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol RuntimeHTTPClient: Sendable {
    func get(_ url: URL) async throws -> HTTPDataResponse
}

public struct URLSessionRuntimeHTTPClient: RuntimeHTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> HTTPDataResponse {
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        return HTTPDataResponse(data: data, statusCode: statusCode)
    }
}
```

## Sources/AstroRuntimeData/RuntimeDataModels.swift

```swift
import Foundation
import AstroSchemas

public struct EngineDataManifest: Codable, Sendable, Equatable {
    public let manifestVersion: String
    public let engineDataVersion: String
    public let packs: [DataPackDescriptor]

    public init(manifestVersion: String, engineDataVersion: String, packs: [DataPackDescriptor]) {
        self.manifestVersion = manifestVersion
        self.engineDataVersion = engineDataVersion
        self.packs = packs
    }
}

public struct DataPackDescriptor: Codable, Sendable, Equatable {
    public let id: String
    public let required: Bool
    public let url: String
    public let sha256: String
    public let bytes: Int64

    public init(id: String, required: Bool, url: String, sha256: String, bytes: Int64) {
        self.id = id
        self.required = required
        self.url = url
        self.sha256 = sha256.lowercased()
        self.bytes = bytes
    }

    public var remoteURL: URL? {
        URL(string: url)
    }

    public var fileName: String {
        guard let remoteURL else { return id }
        let last = remoteURL.lastPathComponent
        return last.isEmpty ? id : last
    }
}

public struct PackStorageLayout: Sendable, Equatable {
    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public var manifestFileURL: URL {
        baseDirectory.appendingPathComponent("manifest.json")
    }

    public var packsDirectory: URL {
        baseDirectory.appendingPathComponent("packs", isDirectory: true)
    }

    public var cacheDirectory: URL {
        baseDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    public var logsDirectory: URL {
        baseDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public var stagingDirectory: URL {
        baseDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    public func packDirectory(for descriptor: DataPackDescriptor) -> URL {
        packsDirectory.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    public func packFileURL(for descriptor: DataPackDescriptor) -> URL {
        packDirectory(for: descriptor).appendingPathComponent(descriptor.fileName)
    }

    public static func defaultBaseDirectory(fileManager: FileManager = .default) -> URL {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("AstroNatalEngine", isDirectory: true)
        #else
        let home = fileManager.homeDirectoryForCurrentUser
        let localShare = home.appendingPathComponent(".local/share", isDirectory: true)
        return localShare.appendingPathComponent("AstroNatalEngine", isDirectory: true)
        #endif
    }
}

public extension EngineDataManifest {
    func derivedDataVersions() -> EngineDataVersions {
        let ephemeris = pack(namedPrefix: "ephemeris")?.fileName ?? "unknown"
        let timeCore = pack(namedPrefix: "time-core")
            .map { versionSuffix(from: $0.id, prefix: "time-core-") ?? engineDataVersion }
            ?? engineDataVersion
        let tzdb = pack(namedPrefix: "tzdb").flatMap { versionSuffix(from: $0.id, prefix: "tzdb-") }
        let eop = pack(namedPrefix: "eop").flatMap { versionSuffix(from: $0.id, prefix: "eop-") }
        return EngineDataVersions(ephemeris: ephemeris, timeCore: timeCore, tzdb: tzdb, eop: eop)
    }

    func pack(namedPrefix prefix: String) -> DataPackDescriptor? {
        packs.first(where: { $0.id.hasPrefix(prefix) })
    }

    private func versionSuffix(from id: String, prefix: String) -> String? {
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }
}
```

## Sources/AstroRuntimeData/SHA256.swift

```swift
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
```

## Sources/AstroSchemas/Enums.swift

```swift
import Foundation

public enum NatalProfile: String, Codable, Sendable, CaseIterable {
    case standardNatal
    case enhancedNatal
}

public enum AmbiguityPolicy: String, Codable, Sendable, CaseIterable {
    case earlier
    case later
    case reject
}

public enum BirthTimePrecision: String, Codable, Sendable, CaseIterable {
    case day
    case hour
    case minute
    case second
    case unknown
}

public enum HouseSystem: String, Codable, Sendable, CaseIterable {
    case placidus
    case equal
}

public enum BodyID: String, Codable, Sendable, CaseIterable, Hashable {
    case sun
    case moon
    case mercury
    case venus
    case mars
    case jupiter
    case saturn
    case uranus
    case neptune
    case pluto
}

public enum AngleID: String, Codable, Sendable, CaseIterable {
    case asc
    case mc
    case ic
    case dc
}

public enum AspectType: String, Codable, Sendable, CaseIterable {
    case conjunction
    case opposition
    case trine
    case square
    case sextile
}

public enum ZodiacSign: String, Codable, Sendable, CaseIterable {
    case aries = "Aries"
    case taurus = "Taurus"
    case gemini = "Gemini"
    case cancer = "Cancer"
    case leo = "Leo"
    case virgo = "Virgo"
    case libra = "Libra"
    case scorpio = "Scorpio"
    case sagittarius = "Sagittarius"
    case capricorn = "Capricorn"
    case aquarius = "Aquarius"
    case pisces = "Pisces"
}

public enum NatalWarningCode: String, Codable, Sendable, CaseIterable {
    case pre1970TimezoneBestEffort = "pre1970_timezone_best_effort"
    case standardModeWithoutEOP = "standard_mode_without_eop"
    case placidusFallbackApplied = "placidus_fallback_applied"
    case birthTimePrecisionLow = "birth_time_precision_low"
    case hostProvidedOffsetOverrodeTZDB = "host_provided_offset_overrode_tzdb"
}
```

## Sources/AstroSchemas/Errors.swift

```swift
import Foundation

public enum NatalEngineError: Error, Sendable, Equatable {
    case engineNotPrepared
    case missingRequiredPack(String)
    case kernelOutOfRange
    case timezoneUnresolved
    case ambiguousLocalTime
    case invalidCoordinates
    case unsupportedProfile
    case dataPackChecksumMismatch(String)
    case invalidSchemaVersion(expected: String, actual: String)
    case invalidBirthDateRange
    case invalidUTCOffset
    case malformedRequest(String)
    case featureNotImplemented(String)
    case networkFailure(String)
    case fileSystemFailure(String)
    case manifestInvalid(String)
}

extension NatalEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .engineNotPrepared:
            return "NatalChartEngine.prepare() must complete before generate() is called."
        case let .missingRequiredPack(packID):
            return "Missing required data pack: \(packID)."
        case .kernelOutOfRange:
            return "The requested birth date is outside the supported kernel range."
        case .timezoneUnresolved:
            return "The birth time could not be resolved to a stable UTC offset."
        case .ambiguousLocalTime:
            return "The local birth time is ambiguous and requires an explicit ambiguity policy."
        case .invalidCoordinates:
            return "Latitude or longitude is out of range."
        case .unsupportedProfile:
            return "The requested natal profile is not supported."
        case let .dataPackChecksumMismatch(packID):
            return "Checksum verification failed for data pack \(packID)."
        case let .invalidSchemaVersion(expected, actual):
            return "Invalid schema version. Expected \(expected), got \(actual)."
        case .invalidBirthDateRange:
            return "Birth date must be between 1900-01-01 and 2150-12-31."
        case .invalidUTCOffset:
            return "UTC offset is outside the valid range."
        case let .malformedRequest(message):
            return "Malformed request: \(message)"
        case let .featureNotImplemented(feature):
            return "Feature not implemented yet: \(feature)."
        case let .networkFailure(message):
            return "Network failure: \(message)"
        case let .fileSystemFailure(message):
            return "File system failure: \(message)"
        case let .manifestInvalid(message):
            return "Manifest is invalid: \(message)"
        }
    }
}
```

## Sources/AstroSchemas/Protocols.swift

```swift
import Foundation

public struct StateVector: Codable, Sendable, Equatable {
    public let positionX: Double
    public let positionY: Double
    public let positionZ: Double
    public let velocityX: Double
    public let velocityY: Double
    public let velocityZ: Double

    public init(
        positionX: Double,
        positionY: Double,
        positionZ: Double,
        velocityX: Double,
        velocityY: Double,
        velocityZ: Double
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.velocityZ = velocityZ
    }
}

public struct HouseContext: Codable, Sendable, Equatable {
    public let julianDayUT: Double
    public let latitude: Double
    public let longitude: Double
    public let system: HouseSystem

    public init(julianDayUT: Double, latitude: Double, longitude: Double, system: HouseSystem) {
        self.julianDayUT = julianDayUT
        self.latitude = latitude
        self.longitude = longitude
        self.system = system
    }
}

public struct HouseResult: Codable, Sendable, Equatable {
    public let system: HouseSystem
    public let cusps: [Double]
    public let fallbackApplied: Bool
    public let iterations: Int

    public init(system: HouseSystem, cusps: [Double], fallbackApplied: Bool, iterations: Int) {
        self.system = system
        self.cusps = cusps
        self.fallbackApplied = fallbackApplied
        self.iterations = iterations
    }
}

public protocol BirthResolver: Sendable {
    func resolve(_ raw: RawBirthRequest) async throws -> ResolvedBirthRequest
}

public protocol EphemerisProvider: Sendable {
    func stateVector(for body: BodyID, tdbJulianDay: Double) throws -> StateVector
}

public protocol HouseSolver: Sendable {
    func solve(_ context: HouseContext) throws -> HouseResult
}

public protocol DataPackStore: Sendable {
    func ensureReady() async throws
    func installedDataVersions() async throws -> EngineDataVersions
}
```

## Sources/AstroSchemas/Requests.swift

```swift
import Foundation

public struct BirthLocation: Codable, Sendable, Equatable {
    public let city: String?
    public let latitude: Double
    public let longitude: Double

    public init(city: String?, latitude: Double, longitude: Double) {
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct BirthSubject: Codable, Sendable, Equatable {
    public let gender: String?

    public init(gender: String?) {
        self.gender = gender
    }
}

public struct RawBirth: Codable, Sendable, Equatable {
    public let localDateTime: String
    public let timeZoneId: String?
    public let utcOffsetMinutesAtBirth: Int?
    public let ambiguityPolicy: AmbiguityPolicy?
    public let timePrecision: BirthTimePrecision?

    public init(
        localDateTime: String,
        timeZoneId: String? = nil,
        utcOffsetMinutesAtBirth: Int? = nil,
        ambiguityPolicy: AmbiguityPolicy? = nil,
        timePrecision: BirthTimePrecision? = nil
    ) {
        self.localDateTime = localDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.ambiguityPolicy = ambiguityPolicy
        self.timePrecision = timePrecision
    }
}

public struct ResolvedBirth: Codable, Sendable, Equatable {
    public let localDateTime: String
    public let timeZoneId: String
    public let utcOffsetMinutesAtBirth: Int
    public let ambiguityPolicy: AmbiguityPolicy
    public let timePrecision: BirthTimePrecision

    public init(
        localDateTime: String,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        ambiguityPolicy: AmbiguityPolicy,
        timePrecision: BirthTimePrecision
    ) {
        self.localDateTime = localDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.ambiguityPolicy = ambiguityPolicy
        self.timePrecision = timePrecision
    }
}

public struct RawBirthRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let birth: RawBirth
    public let location: BirthLocation
    public let subject: BirthSubject
    public let profile: NatalProfile

    public init(
        schemaVersion: String = SchemaVersion.rawRequest,
        birth: RawBirth,
        location: BirthLocation,
        subject: BirthSubject,
        profile: NatalProfile
    ) {
        self.schemaVersion = schemaVersion
        self.birth = birth
        self.location = location
        self.subject = subject
        self.profile = profile
    }
}

public struct ResolvedBirthRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let birth: ResolvedBirth
    public let location: BirthLocation
    public let subject: BirthSubject
    public let profile: NatalProfile

    public init(
        schemaVersion: String = SchemaVersion.resolvedRequest,
        birth: ResolvedBirth,
        location: BirthLocation,
        subject: BirthSubject,
        profile: NatalProfile
    ) {
        self.schemaVersion = schemaVersion
        self.birth = birth
        self.location = location
        self.subject = subject
        self.profile = profile
    }
}
```

## Sources/AstroSchemas/Responses.swift

```swift
import Foundation

public struct EngineDataVersions: Codable, Sendable, Equatable {
    public let ephemeris: String
    public let timeCore: String
    public let tzdb: String?
    public let eop: String?

    public init(ephemeris: String, timeCore: String, tzdb: String? = nil, eop: String? = nil) {
        self.ephemeris = ephemeris
        self.timeCore = timeCore
        self.tzdb = tzdb
        self.eop = eop
    }
}

public struct InputEcho: Codable, Sendable, Equatable {
    public let birthLocalDateTime: String
    public let timeZoneId: String
    public let utcOffsetMinutesAtBirth: Int
    public let latitude: Double
    public let longitude: Double
    public let gender: String?

    public init(
        birthLocalDateTime: String,
        timeZoneId: String,
        utcOffsetMinutesAtBirth: Int,
        latitude: Double,
        longitude: Double,
        gender: String?
    ) {
        self.birthLocalDateTime = birthLocalDateTime
        self.timeZoneId = timeZoneId
        self.utcOffsetMinutesAtBirth = utcOffsetMinutesAtBirth
        self.latitude = latitude
        self.longitude = longitude
        self.gender = gender
    }
}

public struct NatalResponseTimes: Codable, Sendable, Equatable {
    public let utc: String
    public let julianDayUTC: Double
    public let julianDayTT: Double
    public let julianDayTDB: Double?
    public let deltaTSeconds: Double
    public let dut1Seconds: Double?

    public init(
        utc: String,
        julianDayUTC: Double,
        julianDayTT: Double,
        julianDayTDB: Double? = nil,
        deltaTSeconds: Double,
        dut1Seconds: Double? = nil
    ) {
        self.utc = utc
        self.julianDayUTC = julianDayUTC
        self.julianDayTT = julianDayTT
        self.julianDayTDB = julianDayTDB
        self.deltaTSeconds = deltaTSeconds
        self.dut1Seconds = dut1Seconds
    }
}

public struct AnglesResponse: Codable, Sendable, Equatable {
    public let asc: Double
    public let mc: Double
    public let ic: Double
    public let dc: Double

    public init(asc: Double, mc: Double, ic: Double, dc: Double) {
        self.asc = asc
        self.mc = mc
        self.ic = ic
        self.dc = dc
    }

    public static let zero = AnglesResponse(asc: 0, mc: 0, ic: 0, dc: 0)
}

public struct HousesResponse: Codable, Sendable, Equatable {
    public let system: HouseSystem
    public let cusps: [Double]

    public init(system: HouseSystem, cusps: [Double]) {
        self.system = system
        self.cusps = cusps
    }

    public static let empty = HousesResponse(system: .placidus, cusps: Array(repeating: 0, count: 12))
}

public struct BodyPosition: Codable, Sendable, Equatable {
    public let longitude: Double
    public let latitude: Double
    public let speedLongitude: Double
    public let retrograde: Bool
    public let sign: ZodiacSign
    public let house: Int

    public init(
        longitude: Double,
        latitude: Double,
        speedLongitude: Double,
        retrograde: Bool,
        sign: ZodiacSign,
        house: Int
    ) {
        self.longitude = longitude
        self.latitude = latitude
        self.speedLongitude = speedLongitude
        self.retrograde = retrograde
        self.sign = sign
        self.house = house
    }
}

public struct BodiesResponse: Codable, Sendable, Equatable {
    public var sun: BodyPosition?
    public var moon: BodyPosition?
    public var mercury: BodyPosition?
    public var venus: BodyPosition?
    public var mars: BodyPosition?
    public var jupiter: BodyPosition?
    public var saturn: BodyPosition?
    public var uranus: BodyPosition?
    public var neptune: BodyPosition?
    public var pluto: BodyPosition?

    public init(
        sun: BodyPosition? = nil,
        moon: BodyPosition? = nil,
        mercury: BodyPosition? = nil,
        venus: BodyPosition? = nil,
        mars: BodyPosition? = nil,
        jupiter: BodyPosition? = nil,
        saturn: BodyPosition? = nil,
        uranus: BodyPosition? = nil,
        neptune: BodyPosition? = nil,
        pluto: BodyPosition? = nil
    ) {
        self.sun = sun
        self.moon = moon
        self.mercury = mercury
        self.venus = venus
        self.mars = mars
        self.jupiter = jupiter
        self.saturn = saturn
        self.uranus = uranus
        self.neptune = neptune
        self.pluto = pluto
    }

    public static let empty = BodiesResponse()

    public subscript(body: BodyID) -> BodyPosition? {
        get {
            switch body {
            case .sun: return sun
            case .moon: return moon
            case .mercury: return mercury
            case .venus: return venus
            case .mars: return mars
            case .jupiter: return jupiter
            case .saturn: return saturn
            case .uranus: return uranus
            case .neptune: return neptune
            case .pluto: return pluto
            }
        }
        set {
            switch body {
            case .sun: sun = newValue
            case .moon: moon = newValue
            case .mercury: mercury = newValue
            case .venus: venus = newValue
            case .mars: mars = newValue
            case .jupiter: jupiter = newValue
            case .saturn: saturn = newValue
            case .uranus: uranus = newValue
            case .neptune: neptune = newValue
            case .pluto: pluto = newValue
            }
        }
    }
}

public struct AspectResponse: Codable, Sendable, Equatable {
    public let a: BodyID
    public let b: BodyID
    public let type: AspectType
    public let orb: Double

    public init(a: BodyID, b: BodyID, type: AspectType, orb: Double) {
        self.a = a
        self.b = b
        self.type = type
        self.orb = orb
    }
}

public struct EngineWarning: Codable, Sendable, Equatable {
    public let code: NatalWarningCode
    public let message: String

    public init(code: NatalWarningCode, message: String) {
        self.code = code
        self.message = message
    }
}

public struct NatalChartResponse: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let engineVersion: String
    public let dataVersions: EngineDataVersions
    public let profile: NatalProfile
    public let inputEcho: InputEcho
    public let times: NatalResponseTimes
    public let angles: AnglesResponse
    public let houses: HousesResponse
    public let bodies: BodiesResponse
    public let aspects: [AspectResponse]
    public let warnings: [EngineWarning]

    public init(
        schemaVersion: String = SchemaVersion.response,
        engineVersion: String,
        dataVersions: EngineDataVersions,
        profile: NatalProfile,
        inputEcho: InputEcho,
        times: NatalResponseTimes,
        angles: AnglesResponse,
        houses: HousesResponse,
        bodies: BodiesResponse,
        aspects: [AspectResponse],
        warnings: [EngineWarning]
    ) {
        self.schemaVersion = schemaVersion
        self.engineVersion = engineVersion
        self.dataVersions = dataVersions
        self.profile = profile
        self.inputEcho = inputEcho
        self.times = times
        self.angles = angles
        self.houses = houses
        self.bodies = bodies
        self.aspects = aspects
        self.warnings = warnings
    }
}
```

## Sources/AstroSchemas/SchemaVersion.swift

```swift
import Foundation

public enum SchemaVersion {
    public static let rawRequest = "natal.raw.v1"
    public static let resolvedRequest = "natal.resolved.v1"
    public static let response = "natal.response.v1"
}
```

## Sources/AstroSchemas/Validation.swift

```swift
import Foundation

public enum RequestValidator {
    public static func validate(_ request: RawBirthRequest) throws {
        try validateSchema(actual: request.schemaVersion, expected: SchemaVersion.rawRequest)
        try validateCoordinates(request.location)
        try validateSupportedYear(from: request.birth.localDateTime)
        if let offset = request.birth.utcOffsetMinutesAtBirth {
            try validateUTCOffset(offset)
        }
    }

    public static func validate(_ request: ResolvedBirthRequest) throws {
        try validateSchema(actual: request.schemaVersion, expected: SchemaVersion.resolvedRequest)
        try validateCoordinates(request.location)
        try validateSupportedYear(from: request.birth.localDateTime)
        try validateUTCOffset(request.birth.utcOffsetMinutesAtBirth)
    }

    public static func validateCoordinates(_ location: BirthLocation) throws {
        guard (-90.0 ... 90.0).contains(location.latitude), (-180.0 ... 180.0).contains(location.longitude) else {
            throw NatalEngineError.invalidCoordinates
        }
    }

    public static func validateSupportedYear(from localDateTime: String) throws {
        guard let year = extractYear(from: localDateTime) else {
            throw NatalEngineError.malformedRequest("localDateTime must start with yyyy-MM-ddTHH:mm[:ss].")
        }

        guard (1900 ... 2150).contains(year) else {
            throw NatalEngineError.invalidBirthDateRange
        }
    }

    public static func validateUTCOffset(_ offsetMinutes: Int) throws {
        guard (-14 * 60 ... 14 * 60).contains(offsetMinutes) else {
            throw NatalEngineError.invalidUTCOffset
        }
    }

    public static func extractYear(from localDateTime: String) -> Int? {
        guard localDateTime.count >= 4 else { return nil }
        let prefix = String(localDateTime.prefix(4))
        return Int(prefix)
    }

    private static func validateSchema(actual: String, expected: String) throws {
        guard actual == expected else {
            throw NatalEngineError.invalidSchemaVersion(expected: expected, actual: actual)
        }
    }
}
```

## Tests/AstroEphemerisTests/DE442SmokeTests.swift

```swift
import XCTest
import AstroEphemeris
import AstroSchemas

final class DE442SmokeTests: XCTestCase {
    func testReadsRealDE442KernelWhenAvailable() throws {
        guard let kernelURL = Self.locateKernelURL() else {
            throw XCTSkip("Set ASTRO_DE442_PATH to run the real-kernel smoke test.")
        }

        let kernel = try SPKKernel(url: kernelURL)

        XCTAssertTrue(kernel.looksLikeSPK)
        XCTAssertTrue(kernel.hasBody(.sun))
        XCTAssertTrue(kernel.hasBody(.earth))
        XCTAssertTrue(kernel.hasBody(.moon))

        let jd = 2_451_545.0
        let sun = try kernel.stateVector(for: .sun, tdbJulianDay: jd)
        let earth = try kernel.stateVector(for: .earth, tdbJulianDay: jd)
        let moon = try kernel.stateVector(for: .moon, tdbJulianDay: jd)

        XCTAssertTrue([sun, earth, moon].allSatisfy(\.isFinite))
    }

    private static func locateKernelURL() -> URL? {
        if let environmentPath = ProcessInfo.processInfo.environment["ASTRO_DE442_PATH"], !environmentPath.isEmpty {
            let url = URL(fileURLWithPath: environmentPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }
}

private extension StateVector {
    var isFinite: Bool {
        [positionX, positionY, positionZ, velocityX, velocityY, velocityZ].allSatisfy(\.isFinite)
    }
}
```

## Tests/AstroEphemerisTests/JPLEphemerisProviderTests.swift

```swift
import XCTest
import AstroEphemeris
import AstroSchemas

final class JPLEphemerisProviderTests: XCTestCase {
    func testProviderRegressionCasesForSunEarthAndMoon() throws {
        let provider = JPLEphemerisProvider(kernel: try makeReferenceKernel())

        let cases: [(et: Double, body: BodyID, expected: StateVector)] = [
            (
                et: -5.0,
                body: .sun,
                expected: StateVector(positionX: 5.0, positionY: 10.0, positionZ: 15.0, velocityX: 1.0, velocityY: 2.0, velocityZ: 3.0)
            ),
            (
                et: 5.0,
                body: .sun,
                expected: StateVector(positionX: 15.0, positionY: 30.0, positionZ: 45.0, velocityX: 1.0, velocityY: 2.0, velocityZ: 3.0)
            ),
            (
                et: -5.0,
                body: .moon,
                expected: StateVector(positionX: 99.045, positionY: 198.09, positionZ: 297.135, velocityX: 0.091, velocityY: 0.182, velocityZ: 0.273)
            ),
            (
                et: 5.0,
                body: .moon,
                expected: StateVector(positionX: 99.955, positionY: 199.91, positionZ: 299.865, velocityX: 0.091, velocityY: 0.182, velocityZ: 0.273)
            )
        ]

        for regressionCase in cases {
            let jd = 2_451_545.0 + (regressionCase.et / 86_400.0)
            let state = try provider.stateVector(for: regressionCase.body, tdbJulianDay: jd)
            assertState(state, equals: regressionCase.expected)
        }

        let earthJD = 2_451_545.0 + (5.0 / 86_400.0)
        let earth = try provider.earthStateVector(tdbJulianDay: earthJD)
        assertState(
            earth,
            equals: StateVector(positionX: 99.45, positionY: 198.9, positionZ: 298.35, velocityX: 0.09, velocityY: 0.18, velocityZ: 0.27)
        )
    }

    func testProviderFallsBackToMarsBarycenterWhenPlanetCenterAbsent() throws {
        let kernel = try SPKKernel(
            data: SyntheticSPKFixture.makeKernelData(
                segments: [
                    SyntheticSPKFixture.linearSegment(
                        name: "MARS_BARY",
                        target: 4,
                        center: 0,
                        positionAtZero: (50, 60, 70),
                        velocity: (0.5, 0.6, 0.7)
                    )
                ]
            )
        )

        let provider = JPLEphemerisProvider(kernel: kernel)
        let jd = 2_451_545.0 + (4.0 / 86_400.0)
        let mars = try provider.stateVector(for: BodyID.mars, tdbJulianDay: jd)

        assertState(
            mars,
            equals: StateVector(positionX: 52.0, positionY: 62.4, positionZ: 72.8, velocityX: 0.5, velocityY: 0.6, velocityZ: 0.7)
        )
    }

    private func makeReferenceKernel() throws -> SPKKernel {
        let segments = [
            SyntheticSPKFixture.linearSegment(
                name: "SUN",
                target: 10,
                center: 0,
                positionAtZero: (10, 20, 30),
                velocity: (1, 2, 3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "EMB",
                target: 3,
                center: 0,
                positionAtZero: (100, 200, 300),
                velocity: (0.1, 0.2, 0.3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "EARTH",
                target: 399,
                center: 3,
                positionAtZero: (-1, -2, -3),
                velocity: (-0.01, -0.02, -0.03)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "MOON",
                target: 301,
                center: 399,
                positionAtZero: (0.5, 1.0, 1.5),
                velocity: (0.001, 0.002, 0.003)
            )
        ]

        return try SPKKernel(data: SyntheticSPKFixture.makeKernelData(segments: segments))
    }

    private func assertState(
        _ actual: StateVector,
        equals expected: StateVector,
        positionAccuracy: Double = 5e-4,
        velocityAccuracy: Double = 1e-12
    ) {
        XCTAssertEqual(actual.positionX, expected.positionX, accuracy: positionAccuracy)
        XCTAssertEqual(actual.positionY, expected.positionY, accuracy: positionAccuracy)
        XCTAssertEqual(actual.positionZ, expected.positionZ, accuracy: positionAccuracy)
        XCTAssertEqual(actual.velocityX, expected.velocityX, accuracy: velocityAccuracy)
        XCTAssertEqual(actual.velocityY, expected.velocityY, accuracy: velocityAccuracy)
        XCTAssertEqual(actual.velocityZ, expected.velocityZ, accuracy: velocityAccuracy)
    }
}
```

## Tests/AstroEphemerisTests/SPKKernelTests.swift

```swift
import XCTest
import AstroEphemeris
import AstroSchemas

final class SPKKernelTests: XCTestCase {
    func testParsesHeaderDescriptorsAndSegmentNames() throws {
        let kernel = try makeReferenceKernel()

        XCTAssertTrue(kernel.looksLikeSPK)
        XCTAssertEqual(kernel.header.idWord, "DAF/SPK")
        XCTAssertEqual(kernel.header.nd, 2)
        XCTAssertEqual(kernel.header.ni, 6)
        XCTAssertEqual(kernel.header.binaryFormat, "LTL-IEEE")
        XCTAssertEqual(kernel.segments.count, 4)
        XCTAssertEqual(kernel.segments.map(\.name), ["SUN", "EMB", "EARTH", "MOON"])
        XCTAssertEqual(kernel.segments.map(\.targetNAIFID), [10, 3, 399, 301])
        XCTAssertTrue(kernel.hasBody(.sun))
        XCTAssertTrue(kernel.hasBody(.earth))
        XCTAssertTrue(kernel.hasBody(.moon))
        XCTAssertEqual(kernel.coverageEnvelope(for: .sun), -10.0 ... 10.0)
    }

    func testEvaluatesType2StateVectorAndCenterComposition() throws {
        let kernel = try makeReferenceKernel()
        let jd = 2_451_545.0 + (5.0 / 86_400.0)

        let sun = try kernel.stateVector(for: .sun, tdbJulianDay: jd)
        let earth = try kernel.stateVector(for: .earth, tdbJulianDay: jd)
        let moon = try kernel.stateVector(for: .moon, tdbJulianDay: jd)

        assertState(
            sun,
            equals: StateVector(positionX: 15.0, positionY: 30.0, positionZ: 45.0, velocityX: 1.0, velocityY: 2.0, velocityZ: 3.0)
        )
        assertState(
            earth,
            equals: StateVector(positionX: 99.45, positionY: 198.9, positionZ: 298.35, velocityX: 0.09, velocityY: 0.18, velocityZ: 0.27)
        )
        assertState(
            moon,
            equals: StateVector(positionX: 99.955, positionY: 199.91, positionZ: 299.865, velocityX: 0.091, velocityY: 0.182, velocityZ: 0.273)
        )
    }

    func testLaterOverlappingSegmentWins() throws {
        let segments = [
            SyntheticSPKFixture.linearSegment(
                name: "SUN_A",
                target: 10,
                center: 0,
                positionAtZero: (10, 20, 30),
                velocity: (1, 2, 3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "SUN_B",
                target: 10,
                center: 0,
                positionAtZero: (100, 200, 300),
                velocity: (10, 20, 30)
            )
        ]

        let kernel = try SPKKernel(data: SyntheticSPKFixture.makeKernelData(segments: segments))
        let jd = 2_451_545.0 + (5.0 / 86_400.0)
        let sun = try kernel.stateVector(for: .sun, tdbJulianDay: jd)

        assertState(
            sun,
            equals: StateVector(positionX: 150.0, positionY: 300.0, positionZ: 450.0, velocityX: 10.0, velocityY: 20.0, velocityZ: 30.0)
        )
    }

    func testRejectsUnsupportedSegmentType() throws {
        let kernel = try SPKKernel(
            data: SyntheticSPKFixture.makeKernelData(
                segments: [
                    SyntheticSPKFixture.linearSegment(
                        name: "BAD",
                        target: 10,
                        center: 0,
                        positionAtZero: (1, 2, 3),
                        velocity: (0, 0, 0),
                        dataType: 3
                    )
                ]
            )
        )

        XCTAssertThrowsError(try kernel.stateVector(for: .sun, tdbJulianDay: 2_451_545.0)) { error in
            XCTAssertEqual(error as? SPKKernelError, .unsupportedSegmentType(3))
        }
    }

    private func makeReferenceKernel() throws -> SPKKernel {
        let segments = [
            SyntheticSPKFixture.linearSegment(
                name: "SUN",
                target: 10,
                center: 0,
                positionAtZero: (10, 20, 30),
                velocity: (1, 2, 3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "EMB",
                target: 3,
                center: 0,
                positionAtZero: (100, 200, 300),
                velocity: (0.1, 0.2, 0.3)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "EARTH",
                target: 399,
                center: 3,
                positionAtZero: (-1, -2, -3),
                velocity: (-0.01, -0.02, -0.03)
            ),
            SyntheticSPKFixture.linearSegment(
                name: "MOON",
                target: 301,
                center: 399,
                positionAtZero: (0.5, 1.0, 1.5),
                velocity: (0.001, 0.002, 0.003)
            )
        ]

        return try SPKKernel(data: SyntheticSPKFixture.makeKernelData(segments: segments))
    }

    private func assertState(
        _ actual: StateVector,
        equals expected: StateVector,
        positionAccuracy: Double = 5e-4,
        velocityAccuracy: Double = 1e-12
    ) {
        XCTAssertEqual(actual.positionX, expected.positionX, accuracy: positionAccuracy)
        XCTAssertEqual(actual.positionY, expected.positionY, accuracy: positionAccuracy)
        XCTAssertEqual(actual.positionZ, expected.positionZ, accuracy: positionAccuracy)
        XCTAssertEqual(actual.velocityX, expected.velocityX, accuracy: velocityAccuracy)
        XCTAssertEqual(actual.velocityY, expected.velocityY, accuracy: velocityAccuracy)
        XCTAssertEqual(actual.velocityZ, expected.velocityZ, accuracy: velocityAccuracy)
    }
}
```

## Tests/AstroEphemerisTests/SyntheticSPKFixture.swift

```swift
import Foundation

struct SyntheticType2Segment {
    let name: String
    let target: Int
    let center: Int
    let frame: Int
    let dataType: Int
    let startET: Double
    let endET: Double
    let midpoint: Double
    let radius: Double
    let xCoefficients: [Double]
    let yCoefficients: [Double]
    let zCoefficients: [Double]

    init(
        name: String,
        target: Int,
        center: Int,
        frame: Int = 1,
        dataType: Int = 2,
        startET: Double,
        endET: Double,
        midpoint: Double,
        radius: Double,
        xCoefficients: [Double],
        yCoefficients: [Double],
        zCoefficients: [Double]
    ) {
        precondition(xCoefficients.count == yCoefficients.count)
        precondition(yCoefficients.count == zCoefficients.count)
        self.name = name
        self.target = target
        self.center = center
        self.frame = frame
        self.dataType = dataType
        self.startET = startET
        self.endET = endET
        self.midpoint = midpoint
        self.radius = radius
        self.xCoefficients = xCoefficients
        self.yCoefficients = yCoefficients
        self.zCoefficients = zCoefficients
    }

    var recordSizeWords: Int {
        2 + xCoefficients.count + yCoefficients.count + zCoefficients.count
    }

    var recordCount: Int { 1 }

    var directoryWordCount: Int { 4 }

    var totalWordCount: Int { recordSizeWords + directoryWordCount }

    var initialEpoch: Double {
        midpoint - radius
    }
}

enum SyntheticSPKFixture {
    static func linearSegment(
        name: String,
        target: Int,
        center: Int,
        positionAtZero: (Double, Double, Double),
        velocity: (Double, Double, Double),
        coverage: ClosedRange<Double> = -10.0 ... 10.0,
        frame: Int = 1,
        dataType: Int = 2
    ) -> SyntheticType2Segment {
        let midpoint = (coverage.lowerBound + coverage.upperBound) / 2.0
        let radius = (coverage.upperBound - coverage.lowerBound) / 2.0

        return SyntheticType2Segment(
            name: name,
            target: target,
            center: center,
            frame: frame,
            dataType: dataType,
            startET: coverage.lowerBound,
            endET: coverage.upperBound,
            midpoint: midpoint,
            radius: radius,
            xCoefficients: [positionAtZero.0, velocity.0 * radius],
            yCoefficients: [positionAtZero.1, velocity.1 * radius],
            zCoefficients: [positionAtZero.2, velocity.2 * radius]
        )
    }

    static func makeKernelData(segments: [SyntheticType2Segment]) -> Data {
        precondition(!segments.isEmpty)
        precondition(segments.count <= 25, "This test fixture builder supports one summary record.")

        let dataWordCount = segments.reduce(0) { $0 + $1.totalWordCount }
        let dataRecordCount = Int(ceil(Double(dataWordCount) / 128.0))
        let totalRecordCount = 3 + dataRecordCount
        let fileSize = totalRecordCount * 1024

        var data = Data(repeating: 0, count: fileSize)

        writeASCII("DAF/SPK ", to: &data, byteOffset: 0, fixedLength: 8)
        writeInt32(2, to: &data, byteOffset: 8)
        writeInt32(6, to: &data, byteOffset: 12)
        writeASCII("Synthetic Stage2 SPK", to: &data, byteOffset: 16, fixedLength: 60)
        writeInt32(2, to: &data, byteOffset: 76)
        writeInt32(2, to: &data, byteOffset: 80)

        let dataStartAddress = 385
        let freeAddress = dataStartAddress + dataWordCount
        writeInt32(Int32(freeAddress), to: &data, byteOffset: 84)
        writeASCII("LTL-IEEE", to: &data, byteOffset: 88, fixedLength: 8)

        let summaryRecordOffset = 1024
        writeDouble(0.0, to: &data, byteOffset: summaryRecordOffset)
        writeDouble(0.0, to: &data, byteOffset: summaryRecordOffset + 8)
        writeDouble(Double(segments.count), to: &data, byteOffset: summaryRecordOffset + 16)

        let nameRecordOffset = 2048
        var nextAddress = dataStartAddress

        for (index, segment) in segments.enumerated() {
            let descriptorOffset = summaryRecordOffset + 24 + index * 40
            writeDouble(segment.startET, to: &data, byteOffset: descriptorOffset)
            writeDouble(segment.endET, to: &data, byteOffset: descriptorOffset + 8)
            writeInt32(Int32(segment.target), to: &data, byteOffset: descriptorOffset + 16)
            writeInt32(Int32(segment.center), to: &data, byteOffset: descriptorOffset + 20)
            writeInt32(Int32(segment.frame), to: &data, byteOffset: descriptorOffset + 24)
            writeInt32(Int32(segment.dataType), to: &data, byteOffset: descriptorOffset + 28)
            writeInt32(Int32(nextAddress), to: &data, byteOffset: descriptorOffset + 32)
            writeInt32(Int32(nextAddress + segment.totalWordCount - 1), to: &data, byteOffset: descriptorOffset + 36)

            writeASCII(segment.name, to: &data, byteOffset: nameRecordOffset + index * 40, fixedLength: 40)

            let segmentByteOffset = (nextAddress - 1) * 8
            writeDouble(segment.midpoint, to: &data, byteOffset: segmentByteOffset)
            writeDouble(segment.radius, to: &data, byteOffset: segmentByteOffset + 8)

            var coefficientOffset = segmentByteOffset + 16
            for coefficient in segment.xCoefficients {
                writeDouble(coefficient, to: &data, byteOffset: coefficientOffset)
                coefficientOffset += 8
            }
            for coefficient in segment.yCoefficients {
                writeDouble(coefficient, to: &data, byteOffset: coefficientOffset)
                coefficientOffset += 8
            }
            for coefficient in segment.zCoefficients {
                writeDouble(coefficient, to: &data, byteOffset: coefficientOffset)
                coefficientOffset += 8
            }

            writeDouble(segment.initialEpoch, to: &data, byteOffset: coefficientOffset)
            writeDouble(segment.radius * 2.0, to: &data, byteOffset: coefficientOffset + 8)
            writeDouble(Double(segment.recordSizeWords), to: &data, byteOffset: coefficientOffset + 16)
            writeDouble(Double(segment.recordCount), to: &data, byteOffset: coefficientOffset + 24)

            nextAddress += segment.totalWordCount
        }

        return data
    }

    private static func writeASCII(_ string: String, to data: inout Data, byteOffset: Int, fixedLength: Int) {
        let bytes = Array(string.utf8.prefix(fixedLength))
        guard byteOffset >= 0, byteOffset + fixedLength <= data.count else { return }
        for index in 0 ..< fixedLength {
            data[byteOffset + index] = index < bytes.count ? bytes[index] : 0x20
        }
    }

    private static func writeInt32(_ value: Int32, to data: inout Data, byteOffset: Int) {
        let raw = UInt32(bitPattern: value)
        let bytes: [UInt8] = [
            UInt8(raw & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 24) & 0xFF)
        ]
        writeBytes(bytes, to: &data, byteOffset: byteOffset)
    }

    private static func writeDouble(_ value: Double, to data: inout Data, byteOffset: Int) {
        let raw = value.bitPattern
        let bytes: [UInt8] = [
            UInt8(raw & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 32) & 0xFF),
            UInt8((raw >> 40) & 0xFF),
            UInt8((raw >> 48) & 0xFF),
            UInt8((raw >> 56) & 0xFF)
        ]
        writeBytes(bytes, to: &data, byteOffset: byteOffset)
    }

    private static func writeBytes(_ bytes: [UInt8], to data: inout Data, byteOffset: Int) {
        guard byteOffset >= 0, byteOffset + bytes.count <= data.count else { return }
        for (index, byte) in bytes.enumerated() {
            data[byteOffset + index] = byte
        }
    }
}
```

## Tests/AstroNatalEngineTests/NatalChartEngineTests.swift

```swift
import XCTest
@testable import AstroNatalEngine
@testable import AstroSchemas

final class NatalChartEngineTests: XCTestCase {
    func testGenerateThrowsBeforePrepare() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)

        let request = makeResolvedRequest()

        do {
            _ = try await engine.generate(request)
            XCTFail("Expected engineNotPrepared")
        } catch let error as NatalEngineError {
            XCTAssertEqual(error, .engineNotPrepared)
        }
    }

    func testPrepareThenGenerateReturnsChartFromComputer() async throws {
        let configuration = NatalEngineConfiguration(
            engineVersion: "1.0.0-test",
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)

        try await engine.prepare()
        let response = try await engine.generate(makeResolvedRequest())

        XCTAssertEqual(response.engineVersion, "1.0.0-test")
        XCTAssertEqual(response.dataVersions.ephemeris, "de442.bsp")
        XCTAssertEqual(response.profile, .standardNatal)
        XCTAssertEqual(response.inputEcho.timeZoneId, "Asia/Seoul")
    }

    func testGenerateRawUsesResolver() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)
        try await engine.prepare()

        let raw = RawBirthRequest(
            birth: RawBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: nil,
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: "female"),
            profile: .standardNatal
        )

        let response = try await engine.generate(raw)
        XCTAssertEqual(response.inputEcho.timeZoneId, "UTC+09:00")
    }

    func testGenerateJSONDecodesResolvedRequest() async throws {
        let configuration = NatalEngineConfiguration(
            birthResolver: StrictBirthResolver(),
            dataPackStore: MockDataPackStore(),
            chartComputer: EchoChartComputer()
        )
        let engine = NatalChartEngine(configuration: configuration)
        try await engine.prepare()

        let requestData = try JSONEncoder().encode(makeResolvedRequest())
        let responseData = try await engine.generateJSON(requestData)
        let decoded = try JSONDecoder().decode(NatalChartResponse.self, from: responseData)

        XCTAssertEqual(decoded.schemaVersion, SchemaVersion.response)
        XCTAssertEqual(decoded.inputEcho.birthLocalDateTime, "1994-11-03T14:25:00")
    }

    private func makeResolvedRequest() -> ResolvedBirthRequest {
        ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: "female"),
            profile: .standardNatal
        )
    }
}

private actor MockDataPackStore: DataPackStore {
    func ensureReady() async throws {}

    func installedDataVersions() async throws -> EngineDataVersions {
        EngineDataVersions(ephemeris: "de442.bsp", timeCore: "2026.03.0", tzdb: "2026a")
    }
}

private struct EchoChartComputer: NatalChartComputer {
    func generate(
        request: ResolvedBirthRequest,
        environment: NatalEngineEnvironment
    ) async throws -> NatalChartResponse {
        NatalChartResponse(
            engineVersion: environment.engineVersion,
            dataVersions: environment.dataVersions,
            profile: request.profile,
            inputEcho: InputEcho(
                birthLocalDateTime: request.birth.localDateTime,
                timeZoneId: request.birth.timeZoneId,
                utcOffsetMinutesAtBirth: request.birth.utcOffsetMinutesAtBirth,
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                gender: request.subject.gender
            ),
            times: NatalResponseTimes(
                utc: "1994-11-03T05:25:00Z",
                julianDayUTC: 2449660.725694,
                julianDayTT: 2449660.726438,
                deltaTSeconds: 60.2
            ),
            angles: .zero,
            houses: .empty,
            bodies: .empty,
            aspects: [],
            warnings: [
                EngineWarning(
                    code: .standardModeWithoutEOP,
                    message: "Calculated in standardNatal mode without UT1 correction."
                )
            ]
        )
    }
}
```

## Tests/AstroRuntimeDataTests/FileSystemDataPackStoreTests.swift

```swift
import XCTest
@testable import AstroRuntimeData
@testable import AstroSchemas

final class FileSystemDataPackStoreTests: XCTestCase {
    func testEnsureReadyDownloadsRequiredPacksAndPersistsManifest() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifestURL = URL(string: "https://cdn.example.com/astro/manifest.json")!
        let ephemerisURL = URL(string: "https://cdn.example.com/astro/de442.bsp")!
        let timeCoreURL = URL(string: "https://cdn.example.com/astro/time-core-2026.03.json")!

        let ephemerisData = Data("ephemeris-payload".utf8)
        let timeCoreData = Data("time-core-payload".utf8)

        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [
                DataPackDescriptor(
                    id: "ephemeris-de442",
                    required: true,
                    url: ephemerisURL.absoluteString,
                    sha256: SHA256.hexDigest(of: ephemerisData),
                    bytes: Int64(ephemerisData.count)
                ),
                DataPackDescriptor(
                    id: "time-core-2026.03",
                    required: true,
                    url: timeCoreURL.absoluteString,
                    sha256: SHA256.hexDigest(of: timeCoreData),
                    bytes: Int64(timeCoreData.count)
                )
            ]
        )

        let manifestData = try JSONEncoder().encode(manifest)
        let client = MockHTTPClient(responses: [
            manifestURL: HTTPDataResponse(data: manifestData, statusCode: 200),
            ephemerisURL: HTTPDataResponse(data: ephemerisData, statusCode: 200),
            timeCoreURL: HTTPDataResponse(data: timeCoreData, statusCode: 200)
        ])

        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: tempDirectory),
            httpClient: client
        )

        try await store.ensureReady()
        let versions = try await store.installedDataVersions()

        XCTAssertEqual(versions.ephemeris, "de442.bsp")
        XCTAssertEqual(versions.timeCore, "2026.03")
        XCTAssertNil(versions.tzdb)

        let ephemerisPath = tempDirectory
            .appendingPathComponent("packs", isDirectory: true)
            .appendingPathComponent("ephemeris-de442", isDirectory: true)
            .appendingPathComponent("de442.bsp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ephemerisPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("manifest.json").path))
    }

    func testEnsureReadyThrowsOnChecksumMismatch() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifestURL = URL(string: "https://cdn.example.com/astro/manifest.json")!
        let packURL = URL(string: "https://cdn.example.com/astro/de442.bsp")!
        let packData = Data("corrupted".utf8)

        let manifest = EngineDataManifest(
            manifestVersion: "1",
            engineDataVersion: "2026.03.0",
            packs: [
                DataPackDescriptor(
                    id: "ephemeris-de442",
                    required: true,
                    url: packURL.absoluteString,
                    sha256: String(repeating: "0", count: 64),
                    bytes: Int64(packData.count)
                )
            ]
        )

        let client = MockHTTPClient(responses: [
            manifestURL: HTTPDataResponse(data: try JSONEncoder().encode(manifest), statusCode: 200),
            packURL: HTTPDataResponse(data: packData, statusCode: 200)
        ])

        let store = FileSystemDataPackStore(
            manifestURL: manifestURL,
            layout: PackStorageLayout(baseDirectory: tempDirectory),
            httpClient: client
        )

        do {
            try await store.ensureReady()
            XCTFail("Expected checksum mismatch")
        } catch let error as NatalEngineError {
            XCTAssertEqual(error, .dataPackChecksumMismatch("ephemeris-de442"))
        }
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct MockHTTPClient: RuntimeHTTPClient {
    let responses: [URL: HTTPDataResponse]

    func get(_ url: URL) async throws -> HTTPDataResponse {
        guard let response = responses[url] else {
            throw NatalEngineError.networkFailure("No mock response for \(url.absoluteString)")
        }
        return response
    }
}
```

## Tests/AstroSchemasTests/SchemaRoundTripTests.swift

```swift
import XCTest
@testable import AstroSchemas

final class SchemaRoundTripTests: XCTestCase {
    func testResolvedRequestRoundTrips() throws {
        let request = ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: "1994-11-03T14:25:00",
                timeZoneId: "Asia/Seoul",
                utcOffsetMinutesAtBirth: 540,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780),
            subject: BirthSubject(gender: "female"),
            profile: .standardNatal
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(ResolvedBirthRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testRawRequestValidationRejectsOutOfRangeCoordinates() {
        let request = RawBirthRequest(
            birth: RawBirth(localDateTime: "1994-11-03T14:25:00"),
            location: BirthLocation(city: "Nowhere", latitude: 92.0, longitude: 10.0),
            subject: BirthSubject(gender: nil),
            profile: .standardNatal
        )

        XCTAssertThrowsError(try RequestValidator.validate(request)) { error in
            XCTAssertEqual(error as? NatalEngineError, .invalidCoordinates)
        }
    }

    func testResolvedRequestValidationRejectsOutOfRangeYear() {
        let request = ResolvedBirthRequest(
            birth: ResolvedBirth(
                localDateTime: "1899-12-31T23:59:00",
                timeZoneId: "UTC+00:00",
                utcOffsetMinutesAtBirth: 0,
                ambiguityPolicy: .earlier,
                timePrecision: .minute
            ),
            location: BirthLocation(city: nil, latitude: 0.0, longitude: 0.0),
            subject: BirthSubject(gender: nil),
            profile: .standardNatal
        )

        XCTAssertThrowsError(try RequestValidator.validate(request)) { error in
            XCTAssertEqual(error as? NatalEngineError, .invalidBirthDateRange)
        }
    }
}
```

