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
