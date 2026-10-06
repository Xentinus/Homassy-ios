import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Stock lots")
struct StockLotsModelTests {
    let hu = Locale(identifier: "hu_HU")
    let fridge = PickerOption(id: UUID(), name: "Hűtő")
    let garage = PickerOption(id: UUID(), name: "Garázs")
    let day = Date(timeIntervalSince1970: 1_790_000_000)

    func model(allowsMultiple: Bool = true) -> StockLotsModel {
        StockLotsModel(first: StockLot(quantityText: "1", storageLocationID: fridge.id, expiresAt: day),
                       storageOptions: [fridge, garage], allowsMultiple: allowsMultiple, locale: hu)
    }

    @Test func aNewLotCopiesTheLastLocationAndExpiryWithOne() {
        let lots = model()
        lots.lots[0].quantityText = "3"
        lots.lots[0].storageLocationID = garage.id
        lots.addLot()
        #expect(lots.lotCount == 2)
        #expect(lots.lots[1].quantityText == "1")
        #expect(lots.lots[1].storageLocationID == garage.id)
        #expect(lots.lots[1].expiresAt == day)
        #expect(lots.lots[0].id != lots.lots[1].id)
        #expect(lots.total == 4)
    }

    @Test func theLastLotCannotBeRemoved() {
        let lots = model()
        lots.remove(lots.lots[0].id)
        #expect(lots.lotCount == 1 && !lots.canRemove)
        lots.addLot()
        #expect(lots.canRemove)
        lots.remove(lots.lots[0].id)
        #expect(lots.lotCount == 1)
    }

    @Test func totalNeedsEveryLotValid() {
        let lots = model()
        lots.addLot()
        lots.lots[0].quantityText = "1,5"
        #expect(lots.total == Decimal(string: "2.5"))
        lots.lots[1].quantityText = "abc"
        #expect(lots.total == nil && lots.amounts == nil)
        #expect(!lots.validate())
        #expect(lots.quantityErrors[lots.lots[1].id] == coreLocalized("form.invalidQuantity"))
        #expect(lots.quantityErrors[lots.lots[0].id] == nil)
        #expect(lots.details() == nil)
        lots.lots[1].quantityText = "0"
        #expect(lots.total == nil)
    }

    @Test func detailsCarryEveryLot() throws {
        let lots = model()
        lots.addLot()
        lots.lots[1].expiresAt = nil
        let details = try #require(lots.details())
        #expect(details == [LotDetails(quantity: 1, storageLocationID: fridge.id, expiresAt: day),
                            LotDetails(quantity: 1, storageLocationID: fridge.id, expiresAt: nil)])
        #expect(lots.quantityErrors.isEmpty)
    }

    @Test func stepperMovesInWholeStepsAndStopsAtOne() {
        let lots = model()
        let id = lots.lots[0].id
        lots.step(id, by: -1)
        #expect(lots.lots[0].quantityText == "1")
        lots.step(id, by: 1)
        #expect(lots.lots[0].quantityText == "2")
        lots.lots[0].quantityText = "1,5"
        lots.step(id, by: 1)
        #expect(lots.lots[0].quantityText == "2")
        lots.lots[0].quantityText = "2,5"
        lots.step(id, by: -1)
        #expect(lots.lots[0].quantityText == "2")
    }

    @Test func editModeKeepsOneLot() {
        let lots = model(allowsMultiple: false)
        lots.addLot()
        #expect(lots.lotCount == 1)
    }

    @Test func storageNamesAndTheSingleQuantity() {
        let lots = model()
        #expect(lots.storageName(fridge.id) == "Hűtő")
        #expect(lots.storageName(nil) == nil)
        lots.setSingleQuantity("4")
        #expect(lots.total == 4)
        lots.addLot()
        lots.setSingleQuantity("9")
        #expect(lots.total == 5, "only a single lot takes the typed amount")
    }
}
