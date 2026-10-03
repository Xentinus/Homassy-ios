import Testing
@testable import HomassyCore

@Suite("MeasureUnitGroup")
struct MeasureUnitGroupTests {
    @Test("Every unit sits in exactly one group")
    func coversEveryUnitOnce() {
        let grouped = MeasureUnitGroup.allCases.flatMap(\.units)
        #expect(grouped.count == MeasureUnit.allCases.count)
        #expect(Set(grouped) == Set(MeasureUnit.allCases))
    }

    @Test func orderAndFirstUnits() {
        #expect(MeasureUnitGroup.allCases == [.count, .weight, .volume, .kitchen, .size])
        #expect(MeasureUnitGroup.count.units.first == .piece)
        #expect(MeasureUnitGroup.weight.units == [.milligram, .gram, .kilogram])
        #expect(MeasureUnitGroup.volume.units == [.milliliter, .centiliter, .deciliter, .liter, .cubicMeter])
    }
}
