import HomassyCore
import MapKit
import SwiftUI

/// Picks a store (P2-08c, the Apple Maps pattern): a full map behind a bottom card with the search, the recent
/// stores and the shops nearby. The search finds any business, nearest first; an address jumps the map there and
/// lists the places at it. Tap a marker or any Apple Maps place to select it.
struct StorePickerView: View {
    let onPick: (ShoppingLocation?) -> Void

    fileprivate enum Outcome { case cancelled, picked(ShoppingLocation?) }
    static let lowDetentHeight: CGFloat = 200
    static let lowDetent = PresentationDetent.height(lowDetentHeight)

    @State private var model: StorePickerModel
    @State private var completer = StoreCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapSelection: MapSelection<String>?
    @State private var areaSearch: Task<Void, Never>?
    /// The region the map last settled on, so the nearby shops can reload there when a search is cleared.
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showsCard = true
    @State private var detent: PresentationDetent = .medium
    @State private var outcome: Outcome?
    /// Area searches wait for the first nearby load, so the list does not flicker or load twice.
    @State private var hasLoadedNearby = false
    /// The card's top edge and the map's bottom edge (global), measured, so the map can keep clear of the card.
    @State private var cardTop: CGFloat?
    @State private var mapBottom: CGFloat?
    /// How much of the map the card covers, applied once the card settles on a detent (not while it is dragged).
    @State private var mapInset = Self.lowDetentHeight
    @State private var lowInset = Self.lowDetentHeight
    @State private var insetUpdate: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreDirectory.self) private var directory

    /// The When-In-Use authorizer is app-only (P4-02), so the picker owns it.
    init(space: Space, services: ServiceContainer, onPick: @escaping (ShoppingLocation?) -> Void) {
        self.onPick = onPick
        _model = State(initialValue: StorePickerModel(search: services.storeSearch, locations: services.shoppingLocations,
                                                      location: CoreLocationAuthorizer(), space: space))
    }

    var body: some View {
        insetMap
            .ignoresSafeArea(edges: .bottom)
            // The picker closes only through the card, so its onDismiss stays the one place that reports.
            .interactiveDismissDisabled()
            .sheet(isPresented: $showsCard, onDismiss: finish) {
                StorePickerCard(model: model, completer: completer, detent: $detent, close: close) { top in
                    cardTop = top
                    settleMapInset()
                }
                    .environment(directory)
                    .presentationDetents([Self.lowDetent, .medium, .large], selection: $detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
            .onChange(of: model.cameraTarget) { _, target in
                guard let target = target?.coordinate else { return }
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                    latitudinalMeters: 1_500, longitudinalMeters: 1_500))
            }
            // A newer selection cancels the lookup of an older one, so the highlighted place is the one chosen.
            .task(id: mapSelection) { await resolve(mapSelection) }
            .onChange(of: model.addressFocus) { _, focus in if focus != nil { detent = .medium } }
            .onChange(of: model.selectedPlace) { _, place in
                if place != nil && detent == Self.lowDetent { detent = .medium }
            }
            .onChange(of: model.isShowingSearch) { _, showing in
                // The shown list swaps, so a selection from the old one is stale.
                clearMapSelection()
                if showing {
                    areaSearch?.cancel()
                } else if let visibleRegion {
                    scheduleAreaSearch(in: visibleRegion)
                }
            }
            .onChange(of: shownResults.map(\.id)) { _, ids in
                // Only a marker selection belongs to the list; an Apple Maps place stays on the map.
                if let id = mapSelection?.value, !ids.contains(id) { clearMapSelection() }
            }
            .task {
                model.loadRecent()
                await model.loadNearby()
                hasLoadedNearby = true
            }
            .task { await directory.refreshLocation() }
            .onChange(of: detent) { settleMapInset() }
            .onDisappear {
                areaSearch?.cancel()
                insetUpdate?.cancel()
            }
    }

    /// The results the map and the list show: the search, or the shops nearby.
    private var shownResults: [StoreResult] { model.isShowingSearch ? model.searchResults : model.nearby }

    /// The card's height is kept out of the map, so the camera centres in the visible part and MapKit puts its
    /// logo and Legal link above the card.
    private var insetMap: some View {
        map
            .safeAreaPadding(.bottom, mapInset)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
                mapBottom = bottom
                settleMapInset()
            }
    }

    /// Measures what the card covers once it has stopped moving, so dragging it does not slide the map.
    /// The large detent hides the map, so it keeps the low detent's inset.
    private func settleMapInset() {
        insetUpdate?.cancel()
        insetUpdate = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let cardTop, let mapBottom else { return }
            let covered = max(0, mapBottom - cardTop)
            if detent == Self.lowDetent { lowInset = covered }
            mapInset = detent == .large ? lowInset : covered
        }
    }

    /// The card closes first; its onDismiss then reports the pick and closes the picker (two sheets, in order).
    private func close(_ result: Outcome) {
        guard outcome == nil else { return }   // the card may still be animating away
        outcome = result
        showsCard = false
    }

    private func finish() {
        if case .picked(let location) = outcome { onPick(location) }
        dismiss()
    }

    private var map: some View {
        Map(position: $position, selection: $mapSelection) {
            UserAnnotation()
            ForEach(shownResults) { result in
                Marker(result.name, systemImage: "storefront",
                       coordinate: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude))
                    .tag(MapSelection(result.id))
            }
        }
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            guard hasLoadedNearby, !model.isShowingSearch else {
                areaSearch?.cancel()
                return
            }
            scheduleAreaSearch(in: context.region)
        }
        .accessibilityIdentifier("store.map")
        .accessibilityHint(Text("store.map.hint"))
    }

    /// The shops in the visible area, debounced; never while search or address results are showing.
    /// Cancelling also covers an in-flight search: `searchArea` drops its results once its task is cancelled.
    private func scheduleAreaSearch(in region: MKCoordinateRegion) {
        let center = Coordinate(latitude: region.center.latitude, longitude: region.center.longitude)
        let radius = region.span.latitudeDelta * 111_000 / 2
        areaSearch?.cancel()
        areaSearch = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !model.isShowingSearch else { return }
            await model.searchArea(center: center, radiusMeters: radius)
        }
    }

    private func clearMapSelection() {
        mapSelection = nil
        model.clearSelection()
    }

    /// A tapped marker selects our result; a tapped Apple Maps place is looked up by its feature.
    private func resolve(_ selection: MapSelection<String>?) async {
        guard let selection else {
            model.clearSelection()
            return
        }
        if let id = selection.value, let result = shownResults.first(where: { $0.id == id }) {
            model.select(result)
        } else if let feature = selection.feature {
            model.clearSelection()   // "Choose" must not save the previous place while this one loads
            let item = try? await MKMapItemRequest(feature: feature).mapItem
            guard !Task.isCancelled, let item, let result = StoreResult(mapItem: item) else { return }
            model.select(result)
        }
    }
}

/// The bottom card: the search field, then the selection, the search results or Recent and Nearby.
private struct StorePickerCard: View {
    @Bindable var model: StorePickerModel
    let completer: StoreCompleter
    @Binding var detent: PresentationDetent
    let close: (StorePickerView.Outcome) -> Void
    /// Reports the card's top edge (global), so the map behind it can keep clear of it.
    let reportTop: (CGFloat) -> Void

    @FocusState private var searchFocused: Bool
    @Environment(StoreDirectory.self) private var directory
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            list
        }
        .overlay { if model.isLoading { ProgressView("store.loading") } }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { reportTop($0) }
    }

    private var header: some View {
        HStack {
            Button("common.cancel") { close(.cancelled) }
            Spacer()
            Text("store.title").font(.headline)
            Spacer()
            // Keeps the title centred: as wide as the cancel button, and invisible.
            Text("common.cancel").hidden().accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("store.search.prompt", text: $model.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { Task { await model.runSearch() } }
                .autocorrectionDisabled()
                .accessibilityIdentifier("store.search")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("store.search.clear"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: searchFocused) { _, focused in if focused { detent = .large } }
        .onChange(of: model.query) { _, query in
            if query.isEmpty { model.clearSearch() }
            completer.update(query: query, center: model.searchCenter)
        }
    }

    private var list: some View {
        List {
            if let place = model.selectedPlace { selectionSection(place) }
            if showsSuggestions {
                suggestionsSection
            } else if model.isShowingSearch {
                Section {
                    ForEach(model.searchResults) { resultRow($0) }
                } header: {
                    Text(model.addressFocus != nil ? "store.results.atAddress" : "store.search.results")
                }
                if !model.placeResults.isEmpty {
                    Section {
                        ForEach(model.placeResults) { placeRow($0) }
                    } header: {
                        Text("store.search.places")
                    }
                }
            } else {
                recentSection
                Section {
                    ForEach(model.nearby) { resultRow($0) }
                } header: {
                    Text("store.tab.nearby")
                }
            }
            if let message = model.message {
                Section { Text(verbatim: message.text).foregroundStyle(.secondary) }
            }
            Section {
                Button("store.none", role: .destructive) { close(.picked(nil)) }
                    .accessibilityIdentifier("store.none")
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// Suggestions while the user edits the query; the results of the submitted query come back once they stop.
    private var showsSuggestions: Bool {
        searchFocused && !model.query.isEmpty && !completer.suggestions.isEmpty
            && model.query != model.submittedQuery
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(completer.suggestions, id: \.self) { suggestion in
                Button {
                    model.query = suggestion
                    searchFocused = false
                    Task { await model.runSearch() }
                } label: {
                    Label {
                        Text(verbatim: suggestion).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
    }

    /// A place tapped on the map, waiting for "Choose". At accessibility sizes the button goes under the name.
    private func selectionSection(_ place: StoreResult) -> some View {
        Section {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    selectedName(place)
                    chooseButton
                }
            } else {
                HStack(spacing: 12) {
                    selectedName(place)
                    Spacer(minLength: 0)
                    chooseButton
                }
            }
        }
    }

    private func selectedName(_ place: StoreResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: place.name).font(.headline)
            if let subtitle = place.subtitle {
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var chooseButton: some View {
        Button {
            if let location = model.pickSelected() { close(.picked(location)) }
        } label: {
            Text("store.chooseSelected")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("store.chooseSelected")
    }

    private var recentSection: some View {
        Section {
            if model.recent.isEmpty {
                Text("store.recent.empty").foregroundStyle(.secondary)
            }
            ForEach(model.recent) { store in
                Button {
                    if let location = model.pickRecent(store.id) { close(.picked(location)) }
                } label: {
                    Label {
                        Text(verbatim: store.name).foregroundStyle(.primary)
                        if let subtitle = directory.subtitle(ofStore: store.id) {
                            Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "clock") }
                }
                .accessibilityIdentifier("store.recent.\(store.name)")
            }
            .onDelete { offsets in
                let ids = offsets.map { model.recent[$0].id }
                ids.forEach(model.deleteRecent)
            }
        } header: {
            Text("store.tab.recent")
        }
    }

    /// An address or town from the search: jumps the map there and lists the places at it.
    private func placeRow(_ place: PlaceResult) -> some View {
        Button {
            searchFocused = false
            Task { await model.focus(on: place) }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: place.title).foregroundStyle(.primary)
                    if let subtitle = place.subtitle {
                        Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
        .accessibilityIdentifier("store.place.\(place.title)")
    }

    private func resultRow(_ result: StoreResult) -> some View {
        Button {
            if let location = model.pick(result) { close(.picked(location)) }
        } label: {
            Group {
                if typeSize.isAccessibilitySize {
                    // At accessibility sizes the distance goes under the name.
                    VStack(alignment: .leading, spacing: 2) {
                        resultName(result)
                        distance(of: result)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        resultName(result)
                        Spacer(minLength: 8)
                        distance(of: result)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("store.result.\(result.name)")
    }

    private func resultName(_ result: StoreResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: result.name).foregroundStyle(.primary)
            if let subtitle = result.subtitle {
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func distance(of result: StoreResult) -> some View {
        if let distance = model.distanceText(for: result) {
            Text(verbatim: distance).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
