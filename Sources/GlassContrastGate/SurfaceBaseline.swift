import Foundation

/// The WCAG 2.1 minimum a given piece of chrome has to clear.
public enum ContrastRequirement: Sendable, Equatable, CaseIterable {

    /// Body-sized text: 4.5:1.
    case normalText

    /// 18pt+, or 14pt+ bold: 3:1.
    case largeText

    /// Icons, glyphs and the visible boundary of a control: 3:1.
    case nonText

    public var minimumRatio: Double {
        switch self {
        case .normalText: return 4.5
        case .largeText, .nonText: return 3.0
        }
    }

    public var label: String {
        switch self {
        case .normalText: return "normal text"
        case .largeText: return "large text"
        case .nonText: return "non-text"
        }
    }
}

/// One auditable surface: a foreground drawn on a material, with the
/// requirement it is claimed to meet.
///
/// The `id` is the load-bearing field. A baseline you cannot name is a
/// baseline nobody can be asked to fix.
public struct SurfaceBaseline: Sendable, Equatable {

    public let id: String
    public let foreground: SRGBColor
    public let material: Material
    public let requirement: ContrastRequirement

    public init(id: String,
                foreground: SRGBColor,
                material: Material,
                requirement: ContrastRequirement) {
        self.id = id
        self.foreground = foreground
        self.material = material
        self.requirement = requirement
    }
}
