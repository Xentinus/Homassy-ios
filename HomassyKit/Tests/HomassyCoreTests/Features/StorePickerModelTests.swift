import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Store picker model")
struct StorePickerModelTests {
    let stack: ShoppingTestStack
    let locations: ShoppingLocationService

    init() throws {
        stack = try ShoppingTestStack()
        let clock = stack.now
        locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context,
                                            userRecordName: stack.user, now: { clock.date })
    }

    private func makeModel(search: FakeStoreSearch, location: FakeLocation) -> StorePickerModel {
        StorePickerModel(search: search, locations: locations, location: location, space: stack.space)
    }

    @Test func nearbyAsksOnceAndUsesTheUserLocation() async {
        let search = FakeStoreSearch(nearby: [StoreSamples.sparAstoria, StoreSamples.aldiNyugati])
        let location = FakeLocation(access: .notDetermined, grantOnRequest: true, coordinate: StoreSamples.deak)
        let model = makeModel(search: search, location: location)

        await model.loadNearby()
        #expect(location.requests == 1)
        #expect(search.calls == [.nearby(latitude: StoreSamples.deak.latitude, longitude: StoreSamples.deak.longitude,
                                         radius: StorePickerModel.nearbyRadiusMeters)])
        #expect(model.nearby == [StoreSamples.sparAstoria, StoreSamples.aldiNyugati])
        #expect(model.message == nil)
        #expect(!model.isLoading)

        await model.loadNearby()
        #expect(location.requests == 1)
    }

    @Test func withoutPermissionNearbyUsesTheMapCentre() async {
        let search = FakeStoreSearch(nearby: [StoreSamples.lidlBuda])
        let location = FakeLocation(access: .denied)
        let model = makeModel(search: search, location: location)
        let centre = Coordinate(latitude: 47.48, longitude: 19.02)
        model.mapCenter = centre

        await model.loadNearby()
        #expect(search.calls == [.nearby(latitude: 47.48, longitude: 19.02, radius: StorePickerModel.nearbyRadiusMeters)])
        #expect(model.nearby == [StoreSamples.lidlBuda])
    }

    @Test func withoutAnyCentreNearbyExplainsWhatToDo() async {
        let search = FakeStoreSearch()
        let model = makeModel(search: search, location: FakeLocation(access: .denied))
        await model.loadNearby()
        #expect(search.calls.isEmpty)
        #expect(model.message == .needsLocation)
        #expect(!model.message!.text.isEmpty)
    }

    @Test func mostRecentStoreIsTheLastResortCentre() async throws {
        try locations.upsert(StoreSamples.aldiNyugati, in: stack.space)
        let search = FakeStoreSearch()
        let model = makeModel(search: search, location: FakeLocation(access: .denied))
        model.loadRecent()
        await model.loadNearby()
        #expect(search.calls == [.nearby(latitude: StoreSamples.aldiNyugati.latitude,
                                         longitude: StoreSamples.aldiNyugati.longitude,
                                         radius: StorePickerModel.nearbyRadiusMeters)])
        #expect(model.message == .noResults)
    }

    @Test func searchUsesTheQueryAndCentre() async {
        let search = FakeStoreSearch(search: ["aldi": [StoreSamples.aldiNyugati]])
        let model = makeModel(search: search, location: FakeLocation(access: .denied))
        model.mapCenter = StoreSamples.deak
        model.query = "  aldi "
        await model.runSearch()
        #expect(search.calls.contains(.search(text: "aldi", latitude: StoreSamples.deak.latitude,
                                              longitude: StoreSamples.deak.longitude)))
        #expect(search.calls.contains(.places(text: "aldi")))      // addresses are searched in parallel
        #expect(model.searchResults == [StoreSamples.aldiNyugati])
        #expect(model.isShowingSearch)

        model.query = ""
        model.clearSearch()
        #expect(!model.isShowingSearch)
        await model.runSearch()
        #expect(search.calls.count == 2)
    }

    @Test func failuresAreReported() async {
        let search = FakeStoreSearch(fails: true)
        let model = makeModel(search: search, location: FakeLocation(access: .denied))
        model.mapCenter = StoreSamples.deak
        await model.loadNearby()
        #expect(model.nearby.isEmpty)
        #expect(model.message == .failed)
        model.query = "spar"
        await model.runSearch()
        #expect(model.searchResults.isEmpty)
        #expect(model.message == .failed)
    }

    @Test func pickStoresTheResultAndPutsItFirstInRecent() throws {
        try locations.upsert(StoreSamples.lidlBuda, in: stack.space)
        stack.now.advance(seconds: 60)
        let model = makeModel(search: FakeStoreSearch(), location: FakeLocation(access: .denied))
        let picked = try #require(model.pick(StoreSamples.sparAstoria))
        #expect(picked.mapItemIdentifier == StoreSamples.sparAstoria.mapItemIdentifier)
        #expect(model.recent.map(\.name) == ["Spar Astoria", "Lidl Buda"])
    }

    @Test func pickRecentMarksItUsed() throws {
        let lidl = try locations.upsert(StoreSamples.lidlBuda, in: stack.space)
        stack.now.advance(seconds: 10)
        try locations.upsert(StoreSamples.aldiNyugati, in: stack.space)
        stack.now.advance(seconds: 10)
        let model = makeModel(search: FakeStoreSearch(), location: FakeLocation(access: .denied))
        model.loadRecent()
        #expect(model.recent.map(\.name) == ["Aldi Nyugati", "Lidl Buda"])
        #expect(model.pickRecent(lidl.publicId) == lidl)
        #expect(model.recent.map(\.name) == ["Lidl Buda", "Aldi Nyugati"])
        model.deleteRecent(lidl.publicId)
        #expect(model.recent.map(\.name) == ["Aldi Nyugati"])
    }

    @Test func aPlaceTappedOnTheMapIsChosenWithPickSelected() throws {
        let model = StorePickerModel(search: FakeStoreSearch(), locations: locations,
                                     location: FakeLocation(access: .denied), space: stack.space)
        #expect(model.pickSelected() == nil)
        model.select(StoreSamples.lidlBuda)
        #expect(model.selectedPlace == StoreSamples.lidlBuda)
        let stored = try #require(model.pickSelected())
        #expect(stored.mapItemIdentifier == StoreSamples.lidlBuda.mapItemIdentifier)
        #expect(model.selectedPlace == nil)
        #expect(model.recent.map(\.name) == ["Lidl Buda"])
        model.select(StoreSamples.sparAstoria)
        model.clearSelection()
        #expect(model.selectedPlace == nil)
    }

    @Test func movingTheMapSearchesTheVisibleArea() async {
        let search = FakeStoreSearch(nearby: [StoreSamples.lidlBuda])
        let model = StorePickerModel(search: search, locations: locations, location: FakeLocation(access: .denied),
                                     space: stack.space)
        let buda = Coordinate(latitude: 47.48, longitude: 19.02)
        await model.searchArea(center: buda, radiusMeters: 50_000)
        #expect(model.mapCenter == buda)
        #expect(model.nearby == [StoreSamples.lidlBuda])
        #expect(search.calls == [.nearby(latitude: 47.48, longitude: 19.02,
                                         radius: StorePickerModel.areaRadiusRange.upperBound)])
        await model.searchArea(center: buda, radiusMeters: 10)
        #expect(search.calls.last == .nearby(latitude: 47.48, longitude: 19.02,
                                             radius: StorePickerModel.areaRadiusRange.lowerBound))
    }

    @Test func searchFindsShopsAndPlacesAndAPlaceMovesTheMap() async {
        let andrassy = PlaceResult(id: "andrassy", title: "Andrássy út 1", subtitle: "Budapest",
                                   coordinate: Coordinate(latitude: 47.5, longitude: 19.06))
        let search = FakeStoreSearch(nearby: [StoreSamples.sparAstoria],
                                     search: ["andrássy": [StoreSamples.aldiNyugati]], places: ["andrássy": [andrassy]])
        let model = StorePickerModel(search: search, locations: locations, location: FakeLocation(access: .denied),
                                     space: stack.space)
        model.mapCenter = StoreSamples.deak
        model.query = "andrássy"
        await model.runSearch()
        #expect(model.searchResults == [StoreSamples.aldiNyugati])
        #expect(model.placeResults == [andrassy])
        #expect(model.isShowingSearch)

        await model.focus(on: andrassy)
        #expect(model.addressFocus == andrassy)
        #expect(model.cameraTarget == andrassy.coordinate)
        #expect(model.mapCenter == andrassy.coordinate)
        #expect(model.isShowingSearch)
        #expect(model.placeResults.isEmpty)
        #expect(search.calls.last == .around(latitude: 47.5, longitude: 19.06, radius: StorePickerModel.addressRadiusMeters))
    }

    @Test func onlyPlacesFoundIsNotAFailure() async {
        let place = PlaceResult(id: "p", title: "Szeged", coordinate: Coordinate(latitude: 46.25, longitude: 20.15))
        let model = StorePickerModel(search: FakeStoreSearch(places: ["szeged": [place]]), locations: locations,
                                     location: FakeLocation(access: .denied), space: stack.space)
        model.mapCenter = StoreSamples.deak
        model.query = "szeged"
        await model.runSearch()
        #expect(model.placeResults == [place])
        #expect(model.message == nil)
    }

    @Test func anAddressQueryFocusesTheAddressAndListsThePlacesThere() async {
        let andrassy = PlaceResult(id: "a12", title: "Andrássy út 12", subtitle: "Budapest",
                                   coordinate: Coordinate(latitude: 47.5, longitude: 19.06))
        let other = PlaceResult(id: "a12b", title: "Andrássy út 12, Szeged",
                                coordinate: Coordinate(latitude: 46.25, longitude: 20.15))
        let far = StoreResult(mapItemIdentifier: "far", name: "Far", latitude: 47.5010, longitude: 19.0600)
        let near = StoreResult(mapItemIdentifier: "near", name: "Near", latitude: 47.5001, longitude: 19.0600)
        let search = FakeStoreSearch(places: ["Andrássy út 12": [andrassy, other]], around: [far, near])
        let model = makeModel(search: search, location: FakeLocation(access: .denied))
        model.mapCenter = StoreSamples.deak
        model.query = "Andrássy út 12"
        await model.runSearch()
        #expect(model.addressFocus == andrassy)
        #expect(model.searchResults.map(\.name) == ["Near", "Far"])
        #expect(model.placeResults == [other])
        #expect(model.distanceOrigin == andrassy.coordinate)
        #expect(!search.calls.contains { if case .search = $0 { true } else { false } })
    }

    @Test func anAddressWithoutAMatchFallsBackToTheBusinessSearch() async {
        let search = FakeStoreSearch(search: ["Spar 24": [StoreSamples.sparAstoria]])
        let model = makeModel(search: search, location: FakeLocation(access: .denied))
        model.mapCenter = StoreSamples.deak
        model.query = "Spar 24"
        await model.runSearch()
        #expect(model.addressFocus == nil)
        #expect(model.searchResults == [StoreSamples.sparAstoria])
        #expect(search.calls.filter { $0 == .places(text: "Spar 24") }.count == 1)
    }

    @Test func businessResultsAreNearestToTheUserFirst() async {
        let here = Coordinate(latitude: 47.4979, longitude: 19.0402)
        let close = StoreResult(mapItemIdentifier: "c", name: "Közeli posta", latitude: 47.4981, longitude: 19.0402)
        let distant = StoreResult(mapItemIdentifier: "d", name: "Távoli posta", latitude: 47.53, longitude: 19.10)
        let search = FakeStoreSearch(search: ["posta": [distant, close]])
        let model = makeModel(search: search, location: FakeLocation(access: .authorized, coordinate: here))
        await model.loadNearby()
        model.mapCenter = Coordinate(latitude: 47.53, longitude: 19.10)   // the map was panned away
        model.query = "posta"
        await model.runSearch()
        #expect(model.searchResults.map(\.name) == ["Közeli posta", "Távoli posta"])
        #expect(model.distanceOrigin == here)
        #expect(model.distanceText(for: close)?.hasSuffix("m") == true)
    }

    @Test func clearingTheSearchDropsTheAddressFocus() async {
        let place = PlaceResult(id: "p", title: "Fő utca 1", coordinate: Coordinate(latitude: 47.5, longitude: 19.0))
        let model = makeModel(search: FakeStoreSearch(), location: FakeLocation(access: .denied))
        await model.focus(on: place)
        #expect(model.isShowingSearch)
        model.clearSearch()
        #expect(model.addressFocus == nil && !model.isShowingSearch)
    }

    @Test func clearingTheQueryAfterAnAddressSearchDropsTheStaleFocus() async {
        let here = Coordinate(latitude: 47.4979, longitude: 19.0402)
        let andrassy = PlaceResult(id: "andrassy", title: "Andrássy út 12",
                                   coordinate: Coordinate(latitude: 47.5, longitude: 19.06))
        let search = FakeStoreSearch(places: ["Andrássy út 12": [andrassy]])
        let model = makeModel(search: search, location: FakeLocation(access: .authorized, coordinate: here))
        await model.loadNearby()
        model.query = "Andrássy út 12"
        await model.runSearch()
        #expect(model.addressFocus == andrassy)

        model.query = ""
        await model.runSearch()
        #expect(model.addressFocus == nil)
        #expect(!model.isShowingSearch)
        #expect(model.distanceOrigin != andrassy.coordinate)
        #expect(model.distanceOrigin == here)
    }
}
