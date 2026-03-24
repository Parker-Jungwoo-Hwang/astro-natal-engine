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
