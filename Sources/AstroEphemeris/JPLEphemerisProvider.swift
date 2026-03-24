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

        // The engine is tolerant of kernels that expose barycenters instead of planet
        // centers for some bodies. This ordered fallback is what lets the higher chart
        // stages treat `BodyID` as stable even when the underlying kernel inventory
        // changes between test fixtures and real DE442 data.
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
            // A matching body with no covering segment means "date out of coverage",
            // not "unknown body", so callers can surface the user-facing kernel-range
            // error instead of leaking kernel internals.
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
