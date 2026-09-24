import Foundation

public enum SpaceKind: String, Sendable, CaseIterable, Codable {
    case personal, household
}

/// Named `MeasureUnit` because Foundation already has `Unit`. Raw values are persisted and must never change.
public enum MeasureUnit: String, Sendable, CaseIterable, Codable {
    case piece, gram, kilogram, milligram, milliliter, centiliter, deciliter, liter,
         meter, centimeter, millimeter, squareMeter, cubicMeter,
         teaspoon, tablespoon, cup, pack, box, bottle, can, jar, bag
}
