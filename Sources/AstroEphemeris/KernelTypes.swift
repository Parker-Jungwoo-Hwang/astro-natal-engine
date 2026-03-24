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
