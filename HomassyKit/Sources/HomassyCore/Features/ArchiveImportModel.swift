import Foundation
import Observation

/// The import sheet: reads the file once, previews the chosen part for the chosen mode, and imports on confirm.
@MainActor
@Observable
public final class ArchiveImportModel {
    public enum Phase: Equatable {
        case idle, ready, importing, finished
        case failed(String)
    }

    public enum Choice: Hashable, Sendable {
        case newSpace
        case merge(UUID)
    }

    public struct Target: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
    }

    /// A product in the archive, for the product picker.
    public struct ProductOption: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let brand: String?
        public let category: String?
        public let barcode: String?
    }

    public private(set) var phase: Phase = .idle
    public private(set) var preview: ImportPreview?
    public private(set) var targets: [Target] = []
    public private(set) var importedSpace: Space?
    public var newSpaceName = ""
    public private(set) var productOptions: [ProductOption] = []
    public private(set) var groups = Set(ArchiveSelection.Group.allCases)
    public private(set) var selectedProductIDs: Set<UUID> = []
    public var choice: Choice = .newSpace {
        didSet { if oldValue != choice { refreshPreview() } }
    }

    /// Stock can only come with at least one imported product.
    public var isStockAvailable: Bool { groups.contains(.products) && !selectedProductIDs.isEmpty }

    public var selection: ArchiveSelection {
        var groups = groups
        if !isStockAvailable { groups.remove(.stock) }
        let everyProduct = selectedProductIDs.count == productOptions.count
        return ArchiveSelection(groups: groups, productIDs: everyProduct ? nil : selectedProductIDs)
    }

    /// True when the selection would import nothing.
    public var isSelectionEmpty: Bool {
        guard let preview else { return true }
        return ArchiveEntity.allCases.allSatisfy { preview.counts(for: $0).total == 0 }
    }

    public var canConfirm: Bool {
        guard phase == .ready, !isSelectionEmpty else { return false }
        switch choice {
        case .newSpace: return !newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .merge(let id): return targets.contains { $0.id == id }
        }
    }

    @ObservationIgnored private let importer: ArchiveImporter
    @ObservationIgnored private let spaceStore: SpaceStore
    @ObservationIgnored private let prepare: @MainActor () throws -> Void
    @ObservationIgnored private var loaded: ArchivePackage.Loaded?

    public init(importer: ArchiveImporter, spaceStore: SpaceStore,
                prepare: @escaping @MainActor () throws -> Void = {}) {
        self.importer = importer
        self.spaceStore = spaceStore
        self.prepare = prepare
    }

    public func load(url: URL) {
        do {
            targets = try spaceStore.allSpaces().map { Target(id: $0.publicId, name: $0.name) }
            let loaded = try importer.read(url: url)
            self.loaded = loaded
            productOptions = loaded.contents.data.products
                .map { ProductOption(id: $0.publicId, name: $0.name, brand: $0.brand, category: $0.category,
                                     barcode: $0.barcode) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            groups = Set(ArchiveSelection.Group.allCases)
            selectedProductIDs = Set(productOptions.map(\.id))
            preview = try importer.preview(loaded)
            newSpaceName = loaded.contents.manifest.spaceName
            choice = .newSpace
            phase = .ready
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    public func setGroup(_ group: ArchiveSelection.Group, isOn: Bool) {
        if isOn {
            groups.insert(group)
            if group == .products && selectedProductIDs.isEmpty { selectedProductIDs = Set(productOptions.map(\.id)) }
        } else {
            groups.remove(group)
        }
        refreshPreview()
    }

    /// Ticks or unticks products in the picker. No product left turns the products group off; ticking one
    /// turns it back on.
    public func setProducts(_ ids: Set<UUID>, selected: Bool) {
        if selected { selectedProductIDs.formUnion(ids) } else { selectedProductIDs.subtract(ids) }
        if selectedProductIDs.isEmpty { groups.remove(.products) } else { groups.insert(.products) }
        refreshPreview()
    }

    @discardableResult
    public func confirm() -> Space? {
        guard canConfirm, let loaded else { return nil }
        phase = .importing
        do {
            try prepare()
            let mode: ImportMode
            switch choice {
            case .newSpace:
                mode = .asNewSpace(name: newSpaceName)
            case .merge(let id):
                guard let target = space(with: id) else { throw ServiceError.notFound }
                mode = .merge(into: target)
            }
            let result = try importer.importArchive(loaded, mode: mode, selection: selection)
            importedSpace = result.space
            phase = .finished
            return result.space
        } catch {
            phase = .failed(Self.message(for: error))
            return nil
        }
    }

    private func refreshPreview() {
        guard let loaded, phase == .ready else { return }
        do {
            switch choice {
            case .newSpace:
                preview = try importer.preview(loaded, selection: selection)
            case .merge(let id):
                preview = try importer.preview(loaded, mergeInto: space(with: id), selection: selection)
            }
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private func space(with id: UUID) -> Space? {
        (try? spaceStore.allSpaces())?.first { $0.publicId == id }
    }

    static func message(for error: any Error) -> String {
        if let description = (error as? any LocalizedError)?.errorDescription { return description }
        return ArchiveError.corrupted("").errorDescription ?? ""
    }
}
