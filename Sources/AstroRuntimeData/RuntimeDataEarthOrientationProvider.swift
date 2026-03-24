import Foundation
import AstroSchemas

public struct EarthOrientationSample: Codable, Sendable, Equatable {
    public let julianDayUTC: Double
    public let dut1Seconds: Double

    public init(julianDayUTC: Double, dut1Seconds: Double) {
        self.julianDayUTC = julianDayUTC
        self.dut1Seconds = dut1Seconds
    }
}

public struct EarthOrientationPack: Codable, Sendable, Equatable {
    public let version: String
    public let entries: [EarthOrientationSample]

    public init(version: String, entries: [EarthOrientationSample]) {
        self.version = version
        self.entries = entries
    }
}

public struct RuntimeDataEarthOrientationProvider: EarthOrientationProviding, Sendable {
    private let layout: PackStorageLayout
    private let locator: RuntimeInstalledDataLocator

    public init(
        layout: PackStorageLayout = PackStorageLayout(baseDirectory: PackStorageLayout.defaultBaseDirectory())
    ) {
        self.layout = layout
        self.locator = RuntimeInstalledDataLocator(layout: layout)
    }

    public func dut1Seconds(forJulianDayUTC julianDayUTC: Double) throws -> Double? {
        guard let packURL = try locator.installedPackURL(namedPrefix: "eop") else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: packURL)
        } catch {
            throw NatalEngineError.fileSystemFailure(error.localizedDescription)
        }

        let pack: EarthOrientationPack
        do {
            pack = try JSONDecoder().decode(EarthOrientationPack.self, from: data)
        } catch {
            throw NatalEngineError.manifestInvalid("EOP pack is invalid: \(error.localizedDescription)")
        }

        // The provider stays stateless on purpose: Stage 7/9/10/12 can construct it
        // cheaply from the shared runtime layout, and missing/out-of-range samples
        // must degrade to warnings rather than silently reusing stale dUT1 values.
        return interpolate(pack.entries, julianDayUTC: julianDayUTC)
    }
    private func interpolate(_ entries: [EarthOrientationSample], julianDayUTC: Double) -> Double? {
        let sortedEntries = entries.sorted { $0.julianDayUTC < $1.julianDayUTC }
        guard let first = sortedEntries.first, let last = sortedEntries.last else {
            return nil
        }

        // Returning `nil` outside the covered range is significant to the engine:
        // callers use that to fall back to UTC-as-UT1 and emit `standardModeWithoutEOP`
        // instead of extrapolating beyond the pack's declared support window.
        if abs(julianDayUTC - first.julianDayUTC) < 1e-9 {
            return first.dut1Seconds
        }
        if abs(julianDayUTC - last.julianDayUTC) < 1e-9 {
            return last.dut1Seconds
        }
        guard julianDayUTC > first.julianDayUTC, julianDayUTC < last.julianDayUTC else {
            return nil
        }

        for index in 0..<(sortedEntries.count - 1) {
            let lower = sortedEntries[index]
            let upper = sortedEntries[index + 1]

            if abs(julianDayUTC - lower.julianDayUTC) < 1e-9 {
                return lower.dut1Seconds
            }
            if abs(julianDayUTC - upper.julianDayUTC) < 1e-9 {
                return upper.dut1Seconds
            }

            guard julianDayUTC > lower.julianDayUTC, julianDayUTC < upper.julianDayUTC else {
                continue
            }

            let fraction = (julianDayUTC - lower.julianDayUTC) / (upper.julianDayUTC - lower.julianDayUTC)
            return lower.dut1Seconds + fraction * (upper.dut1Seconds - lower.dut1Seconds)
        }

        return nil
    }
}
