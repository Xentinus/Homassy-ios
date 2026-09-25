import HomassyCore
import MapKit
import SwiftUI

/// Picks a store from Apple Maps: recent stores, nearby shops on a small map, or a name search.
struct StorePickerView: View {
    let onPick: (ShoppingLocation?) -> Void

    @State private var model: StorePickerModel
    @State private var completer = StoreCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var placeCard: MKMapItem?
    @Environment(\.dismiss) private var dismiss

    /// The When-In-Use authorizer is app-only (P4-02), so the picker owns it.
    init(space: Space, services: ServiceContainer, onPick: @escaping (ShoppingLocation?) -> Void) {
        self.onPick = onPick
        _model = State(initialValue: StorePickerModel(search: services.storeSearch,
                                                      locations: services.shoppingLocations,
                                                      location: CoreLocationAuthorizer(), space: space))
    }

    var body: some View {
        NavigationStack {
            List {
                if model.isShowingSearch {
                    Section {
                        ForEach(model.searchResults) { resultRow($0) }
                    } header: {
                        Text("store.search.results")
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
            .onChange(of: model.nearby) { _, _ in position = .automatic }
            .overlay { if model.isLoading { ProgressView("store.loading") } }
            .mapItemDetailSheet(item: $placeCard)
            .task { model.loadRecent() }
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
            Map(position: $position) {
                UserAnnotation()
                ForEach(model.nearby) { result in
                    Marker(result.name, systemImage: "cart",
                           coordinate: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude))
                }
            }
            .frame(height: 200)
            .listRowInsets(EdgeInsets())
            .onMapCameraChange(frequency: .onEnd) { context in
                model.mapCenter = Coordinate(latitude: context.region.center.latitude,
                                             longitude: context.region.center.longitude)
            }
            ForEach(model.nearby) { resultRow($0) }
            Button { Task { await model.loadNearby() } } label: {
                Label("store.searchHere", systemImage: "arrow.clockwise")
            }
        }
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

    /// Fresh details for the place card come from Apple Maps by identifier (§6.7).
    private func mapItem(for result: StoreResult) async -> MKMapItem? {
        guard let identifier = MKMapItem.Identifier(rawValue: result.mapItemIdentifier) else { return nil }
        return try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
    }
}
