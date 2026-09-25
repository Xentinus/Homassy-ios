import HomassyCore
import MapKit
import SwiftUI

/// Picks a store from Apple Maps: recent stores, or shops on an interactive map that follows the user's panning
/// (any shop on the map can be tapped and chosen). The search finds shops by name and addresses, which move
/// the map there.
struct StorePickerView: View {
    let onPick: (ShoppingLocation?) -> Void

    @State private var model: StorePickerModel
    @State private var completer = StoreCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapSelection: MapSelection<String>?
    @State private var placeCard: MKMapItem?
    @State private var areaSearch: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// The When-In-Use authorizer is app-only (P4-02), so the picker owns it.
    init(space: Space, services: ServiceContainer, initialTab: StorePickerModel.Tab = .recent,
         onPick: @escaping (ShoppingLocation?) -> Void) {
        self.onPick = onPick
        _model = State(initialValue: StorePickerModel(search: services.storeSearch,
                                                      locations: services.shoppingLocations,
                                                      location: CoreLocationAuthorizer(), space: space,
                                                      initialTab: initialTab))
    }

    var body: some View {
        NavigationStack {
            List {
                if model.isShowingSearch {
                    if !model.placeResults.isEmpty {
                        Section {
                            ForEach(model.placeResults) { placeRow($0) }
                        } header: {
                            Text("store.search.places")
                        }
                    }
                    if !model.searchResults.isEmpty {
                        Section {
                            ForEach(model.searchResults) { resultRow($0) }
                        } header: {
                            Text("store.search.results")
                        }
                    }
                } else {
                    Section {
                        Picker(selection: $model.tab) {
                            Text("store.tab.recent").tag(StorePickerModel.Tab.recent)
                            Text("store.tab.nearby").tag(StorePickerModel.Tab.nearby)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("store.tabs")
                    }
                    switch model.tab {
                    case .recent: recentSection
                    case .nearby: nearbySection
                    }
                }
                if let message = model.message {
                    Section { Text(verbatim: message.text).foregroundStyle(.secondary) }
                }
                Section {
                    Button("store.none", role: .destructive) {
                        onPick(nil)
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let place = model.selectedPlace { selectionBar(place) }
            }
            .navigationTitle(Text("store.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
            }
            .searchable(text: $model.query, prompt: Text("store.search.prompt"))
            .searchSuggestions {
                ForEach(completer.suggestions, id: \.self) { suggestion in
                    Text(verbatim: suggestion).searchCompletion(suggestion)
                }
            }
            .onSubmit(of: .search) { Task { await model.runSearch() } }
            .onChange(of: model.query) { _, query in
                if query.isEmpty { model.clearSearch() }
                completer.update(query: query, center: model.searchCenter)
            }
            .onChange(of: model.tab) { _, tab in
                if tab == .nearby { Task { await model.loadNearby() } }
            }
            .onChange(of: model.cameraTarget) { _, target in
                guard let target else { return }
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                    latitudinalMeters: 1_500, longitudinalMeters: 1_500))
            }
            .onChange(of: mapSelection) { _, selection in Task { await resolve(selection) } }
            .overlay { if model.isLoading { ProgressView("store.loading") } }
            .mapItemDetailSheet(item: $placeCard)
            .task {
                model.loadRecent()
                if model.tab == .nearby { await model.loadNearby() }
            }
        }
    }

    private var recentSection: some View {
        Section {
            if model.recent.isEmpty {
                Text("store.recent.empty").foregroundStyle(.secondary)
            }
            ForEach(model.recent) { store in
                Button {
                    if let location = model.pickRecent(store.id) {
                        onPick(location)
                        dismiss()
                    }
                } label: {
                    Label { Text(verbatim: store.name) } icon: { Image(systemName: "clock") }
                }
                .accessibilityIdentifier("store.recent.\(store.name)")
            }
            .onDelete { offsets in
                let ids = offsets.map { model.recent[$0].id }
                ids.forEach(model.deleteRecent)
            }
        }
    }

    private var nearbySection: some View {
        Section {
            Map(position: $position, selection: $mapSelection) {
                UserAnnotation()
                ForEach(model.nearby) { result in
                    Marker(result.name, systemImage: "cart",
                           coordinate: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude))
                        .tag(MapSelection(result.id))
                }
            }
            .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
            .frame(height: 320)
            .listRowInsets(EdgeInsets())
            .onMapCameraChange(frequency: .onEnd) { context in
                let center = Coordinate(latitude: context.region.center.latitude,
                                        longitude: context.region.center.longitude)
                let radius = context.region.span.latitudeDelta * 111_000 / 2
                areaSearch?.cancel()
                areaSearch = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await model.searchArea(center: center, radiusMeters: radius)
                }
            }
            .accessibilityIdentifier("store.map")
            Text("store.map.hint").font(.footnote).foregroundStyle(.secondary)
            ForEach(model.nearby) { resultRow($0) }
        }
    }

    private func selectionBar(_ place: StoreResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name).font(.headline)
                if let subtitle = place.subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { Task { placeCard = await mapItem(for: place) } } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel(Text("store.details"))
            Button {
                if let location = model.pickSelected() {
                    onPick(location)
                    dismiss()
                }
            } label: {
                Text("store.chooseSelected")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("store.chooseSelected")
        }
        .padding()
        .background(.bar)
    }

    /// An address or town from the search: moves the map there, and the shops around it load.
    private func placeRow(_ place: PlaceResult) -> some View {
        Button {
            Task { await model.goTo(place) }
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
        HStack {
            Button {
                if let location = model.pick(result) {
                    onPick(location)
                    dismiss()
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: result.name)
                    if let subtitle = result.subtitle {
                        Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                Task { placeCard = await mapItem(for: result) }
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("store.details"))
        }
    }

    /// A tapped marker selects our result; a tapped Apple Maps place is looked up by its feature.
    private func resolve(_ selection: MapSelection<String>?) async {
        guard let selection else {
            model.clearSelection()
            return
        }
        if let id = selection.value, let result = model.nearby.first(where: { $0.id == id }) {
            model.select(result)
        } else if let feature = selection.feature,
                  let item = try? await MKMapItemRequest(feature: feature).mapItem,
                  let result = StoreResult(mapItem: item) {
            model.select(result)
        }
    }

    /// Fresh details for the place card come from Apple Maps by identifier (§6.7).
    private func mapItem(for result: StoreResult) async -> MKMapItem? {
        guard let identifier = MKMapItem.Identifier(rawValue: result.mapItemIdentifier) else { return nil }
        return try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
    }
}
