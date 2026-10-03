import Foundation

/// The product form's unit picker sections (P2-07b). Every unit is in exactly one group, smallest first.
public enum MeasureUnitGroup: String, CaseIterable, Sendable, Identifiable {
    case count, weight, volume, kitchen, size

    public var id: String { rawValue }

    public var units: [MeasureUnit] {
        switch self {
        case .count: [.piece, .pack, .box, .bag, .bottle, .jar, .can]
        case .weight: [.milligram, .gram, .kilogram]
        case .volume: [.milliliter, .centiliter, .deciliter, .liter, .cubicMeter]
        case .kitchen: [.teaspoon, .tablespoon, .cup]
        case .size: [.millimeter, .centimeter, .meter, .squareMeter]
        }
    }
}
