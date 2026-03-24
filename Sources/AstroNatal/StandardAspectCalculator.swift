import Foundation
import AstroSchemas

public protocol AspectCalculating: Sendable {
    func aspects(from bodies: BodiesResponse, profile: NatalProfile) throws -> [AspectResponse]
}

public struct StandardAspectCalculator: AspectCalculating {
    public init() {}

    public func aspects(from bodies: BodiesResponse, profile: NatalProfile) throws -> [AspectResponse] {
        let definitions = aspectDefinitions(for: profile)
        var results: [AspectResponse] = []

        for (index, a) in BodyID.allCases.enumerated() {
            guard let aPosition = bodies[a] else { continue }

            for b in BodyID.allCases.dropFirst(index + 1) {
                guard let bPosition = bodies[b] else { continue }
                let separation = angularSeparation(aPosition.longitude, bPosition.longitude)

                guard let bestMatch = definitions
                    .map({ definition in
                        (
                            type: definition.type,
                            orb: abs(separation - definition.exactAngle),
                            maxOrb: definition.maxOrb
                        )
                    })
                    .filter({ pair in pair.orb <= pair.maxOrb })
                    .min(by: { lhs, rhs in
                        if lhs.orb == rhs.orb {
                            return lhs.type.rawValue < rhs.type.rawValue
                        }
                        return lhs.orb < rhs.orb
                    })
                else {
                    continue
                }

                results.append(
                    AspectResponse(
                        a: a,
                        b: b,
                        type: bestMatch.type,
                        orb: bestMatch.orb
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.a == rhs.a {
                return lhs.b.rawValue < rhs.b.rawValue
            }
            return lhs.a.rawValue < rhs.a.rawValue
        }
    }

    private func aspectDefinitions(for profile: NatalProfile) -> [AspectDefinition] {
        switch profile {
        case .standardNatal:
            return [
                AspectDefinition(type: .conjunction, exactAngle: 0, maxOrb: 8),
                AspectDefinition(type: .opposition, exactAngle: 180, maxOrb: 8),
                AspectDefinition(type: .trine, exactAngle: 120, maxOrb: 6),
                AspectDefinition(type: .square, exactAngle: 90, maxOrb: 6),
                AspectDefinition(type: .sextile, exactAngle: 60, maxOrb: 4)
            ]
        case .enhancedNatal:
            return [
                AspectDefinition(type: .conjunction, exactAngle: 0, maxOrb: 10),
                AspectDefinition(type: .opposition, exactAngle: 180, maxOrb: 9),
                AspectDefinition(type: .trine, exactAngle: 120, maxOrb: 7),
                AspectDefinition(type: .square, exactAngle: 90, maxOrb: 7),
                AspectDefinition(type: .sextile, exactAngle: 60, maxOrb: 5)
            ]
        }
    }

    private func angularSeparation(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(normalizeDegrees(lhs) - normalizeDegrees(rhs))
        return min(difference, 360.0 - difference)
    }

    private func normalizeDegrees(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        return normalized >= 0 ? normalized : normalized + 360.0
    }
}

private struct AspectDefinition {
    let type: AspectType
    let exactAngle: Double
    let maxOrb: Double
}
