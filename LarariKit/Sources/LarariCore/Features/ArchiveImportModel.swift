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

    /// A record of the archive, for the picker of its group.
    public struct RecordOption: Identifiable, Hashable, Sendable {
        public enum Detail: Hashable, Sendable {
            case text(String)
            case freezer
            case items(Int)
        }

        public let id: UUID
        public let title: String
        public let detail: Detail?
        /// Extra search terms besides the title (brand, barcode).
        public let keywords: [String]
    }

    public private(set) var phase: Phase = .idle
    public private(set) var preview: ImportPreview?
    public private(set) var targets: [Target] = []
    public private(set) var importedSpace: Space?
    public var newSpaceName = ""
    public private(set) var groups = Set(ArchiveSelection.Group.allCases)
    private var recordOptions: [ArchiveSelection.Group: [RecordOption]] = [:]
    private var picked: [ArchiveSelection.Group: Set<UUID>] = [:]
    public var choice: Choice = .newSpace {
        didSet { if oldValue != choice { refreshPreview() } }
    }

    /// Stock can only come with at least one imported product.
    public var isStockAvailable: Bool { groups.contains(.products) && !pickedIDs(for: .products).isEmpty }

    public var selection: ArchiveSelection {
        var groups = groups
        if !isStockAvailable { groups.remove(.stock) }
        var picks: [ArchiveSelection.Group: Set<UUID>] = [:]
        for (group, ids) in picked where ids.count < options(for: group).count {
            picks[group] = ids
        }
        return ArchiveSelection(groups: groups, picks: picks)
    }

    /// The records of `group` in the archive, sorted by title. Empty for stock.
    public func options(for group: ArchiveSelection.Group) -> [RecordOption] { recordOptions[group] ?? [] }

    /// The ticked records of `group`; none while the group is off.
    public func pickedIDs(for group: ArchiveSelection.Group) -> Set<UUID> {
        groups.contains(group) ? picked[group] ?? [] : []
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
            targets = try spaceStore.allSpaces().filter(importer.canMerge(into:)).map { Target(id: $0.publicId, name: $0.name) }
            let loaded = try importer.read(url: url)
            self.loaded = loaded
            recordOptions = Self.options(for: importer.importable(loaded.contents.data))
            groups = Set(ArchiveSelection.Group.allCases)
            picked = recordOptions.mapValues { Set($0.map(\.id)) }
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
            if picked[group]?.isEmpty ?? true { picked[group] = Set(options(for: group).map(\.id)) }
        } else {
            groups.remove(group)
        }
        refreshPreview()
    }

    /// Ticks or unticks records in a group's picker. No record left turns the group off; ticking one while
    /// the group is off turns it back on with just that record.
    public func setRecords(_ ids: Set<UUID>, in group: ArchiveSelection.Group, selected: Bool) {
        var current = pickedIDs(for: group)
        if selected { current.formUnion(ids) } else { current.subtract(ids) }
        picked[group] = current
        if current.isEmpty { groups.remove(group) } else { groups.insert(group) }
        refreshPreview()
    }

    private static func options(for data: ArchiveData) -> [ArchiveSelection.Group: [RecordOption]] {
        func sorted(_ options: [RecordOption]) -> [RecordOption] {
            options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        let itemCounts = Dictionary(grouping: data.shoppingListItems, by: \.list).mapValues(\.count)
        return [
            .products: sorted(data.products.map { product in
                let detail = [product.brand, product.category].compactMap { $0 }.joined(separator: " · ")
                return RecordOption(id: product.publicId, title: product.name,
                                    detail: detail.isEmpty ? nil : .text(detail),
                                    keywords: [product.brand, product.barcode].compactMap { $0 })
            }),
            .storageLocations: sorted(data.storageLocations.map {
                RecordOption(id: $0.publicId, title: $0.name, detail: $0.isFreezer ? .freezer : nil, keywords: [])
            }),
            .shoppingLocations: sorted(data.shoppingLocations.map {
                RecordOption(id: $0.publicId, title: $0.name, detail: nil, keywords: [])
            }),
            .shoppingLists: sorted(data.shoppingLists.map {
                RecordOption(id: $0.publicId, title: $0.name, detail: .items(itemCounts[$0.publicId] ?? 0), keywords: [])
            }),
            .members: sorted(data.members.map {
                RecordOption(id: $0.publicId, title: $0.displayName.isEmpty ? $0.userRecordName : $0.displayName,
                             detail: nil, keywords: [])
            }),
        ]
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
