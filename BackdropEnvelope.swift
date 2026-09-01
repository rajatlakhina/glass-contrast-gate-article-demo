import Foundation

public enum AuditError: Error, Equatable, CustomStringConvertible {

    /// An envelope with no samples cannot produce a worst case, and silently
    /// returning the nominal value would be the exact lie the audit exists to
    /// catch. So it is a typed error at construction time.
    case emptyEnvelope

    /// A sweep needs at least two samples to be a sweep.
    case sweepTooSmall(requested: Int)

    public var description: String {
        switch self {
        case .emptyEnvelope:
            return "A backdrop envelope needs at least one sample."
        case .sweepTooSmall(let requested):
            return "A grey sweep needs at least 2 samples, got \(requested)."
        }
    }
}

/// The range of content a piece of chrome has to survive sitting on top of.
///
/// A design system declares one nominal background and checks contrast against
/// it. Translucent chrome does not have one background — it has whatever the
/// user scrolled underneath it. The envelope is that set, made explicit.
public struct BackdropEnvelope: Sendable, Equatable {

    public let samples: [SRGBColor]
    public let name: String

    /// Creates an envelope. Throws rather than accepting an empty sample set.
    public init(name: String, samples: [SRGBColor]) throws {
        guard !samples.isEmpty else { throw AuditError.emptyEnvelope }
        self.name = name
        self.samples = samples
    }

    /// A neutral sweep from black to white in `count` evenly spaced steps.
    ///
    /// This is the cheapest envelope that still finds the cliff: for any
    /// monotone foreground/tint pair the worst case lies somewhere on the
    /// greyscale line, and the sweep says where.
    public static func greySweep(count: Int) throws -> BackdropEnvelope {
        guard count >= 2 else { throw AuditError.sweepTooSmall(requested: count) }
        let steps = (0..<count).map { index -> SRGBColor in
            .grey(Double(index) / Double(count - 1))
        }
        return try BackdropEnvelope(name: "grey sweep (\(count) steps)", samples: steps)
    }

    /// A small envelope of saturated content colours, for the case where the
    /// chrome sits over photography or media artwork rather than over a
    /// neutral scroll view.
    public static func photographic() throws -> BackdropEnvelope {
        try BackdropEnvelope(name: "photographic", samples: [
            SRGBColor(hex: 0x0B1020),   // night sky
            SRGBColor(hex: 0x7A4B2A),   // skin / earth midtone
            SRGBColor(hex: 0x1E6F3C),   // foliage
            SRGBColor(hex: 0xC9A227),   // low sun
            SRGBColor(hex: 0xEDE7DC),   // overcast sky
            SRGBColor(hex: 0xF7F7F7)    // blown highlight
        ])
    }
}
