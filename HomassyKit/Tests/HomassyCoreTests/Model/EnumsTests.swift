import Foundation
import Testing
@testable import HomassyCore

struct EnumsTests {
    @Test func spaceKindRawValuesAreStable() {
        #expect(SpaceKind.allCases.map(\.rawValue) == ["personal", "household"])
    }

    @Test func measureUnitRawValuesAreStable() {
        #expect(MeasureUnit.allCases.map(\.rawValue) == [
            "piece", "gram", "kilogram", "milligram", "milliliter", "centiliter", "deciliter", "liter",
            "meter", "centimeter", "millimeter", "squareMeter", "cubicMeter",
            "teaspoon", "tablespoon", "cup", "pack", "box", "bottle", "can", "jar", "bag",
        ])
    }

    @Test func measureUnitCodesAsItsRawString() throws {
        let data = try JSONEncoder().encode([MeasureUnit.squareMeter])
        #expect(String(decoding: data, as: UTF8.self) == #"["squareMeter"]"#)
        #expect(try JSONDecoder().decode([MeasureUnit].self, from: data) == [.squareMeter])
    }

    @Test func spaceKindCodesAsItsRawString() throws {
        let data = try JSONEncoder().encode(SpaceKind.allCases)
        #expect(String(decoding: data, as: UTF8.self) == #"["personal","household"]"#)
        #expect(try JSONDecoder().decode([SpaceKind].self, from: data) == SpaceKind.allCases)
    }

    @Test func measureUnitRoundTripsEveryCase() throws {
        let data = try JSONEncoder().encode(MeasureUnit.allCases)
        let raw = try JSONDecoder().decode([String].self, from: data)
        #expect(raw == MeasureUnit.allCases.map(\.rawValue))
        #expect(try JSONDecoder().decode([MeasureUnit].self, from: data) == MeasureUnit.allCases)
    }
}
