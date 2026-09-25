import Foundation
import Observation

/// The import sheet: reads the file, previews it for the chosen mode, and imports on confirm.
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

    public private(set) var phase: Phase = .idle
    public private(set) var preview: ImportPreview?
    public private(set) var targets: [Target] = []
    public private(set) var importedSpace: Space?
    public var newSpaceName = ""
    public var choice: Choice = .newSpace {
        didSet { if oldValue != choice { refreshPreview() } }
    }

    public var canConfirm: Bool {
        guard phase == .ready else { return false }
        switch choice {
        case .newSpace: return !newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .merge(let id): return targets.contains { $0.id == id }
        }
    }

    @ObservationIgnored private let importer: ArchiveImporter
    @ObservationIgnored private let spaceStore: SpaceStore
    @ObservationIgnored private let prepare: @MainActor () throws -> Void
    @ObservationIgnored private var url: URL?

    public init(importer: ArchiveImporter, spaceStore: SpaceStore,
                prepare: @escaping @MainActor () throws -> Void = {}) {
        self.importer = importer
        self.spaceStore = spaceStore
        self.prepare = prepare
    }

    public func load(url: URL) {
        self.url = url
        do {
            targets = try spaceStore.allSpaces().map { Target(id: $0.publicId, name: $0.name) }
            let preview = try importer.preview(url: url)
            self.preview = preview
            newSpaceName = preview.manifest.spaceName
            choice = .newSpace
            phase = .ready
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    @discardableResult
    public func confirm() -> Space? {
        guard canConfirm, let url else { return nil }
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
            let result = try importer.importArchive(url: url, mode: mode)
            importedSpace = result.space
            phase = .finished
            return result.space
        } catch {
            phase = .failed(Self.message(for: error))
            return nil
        }
    }

    private func refreshPreview() {
        guard let url, phase == .ready else { return }
        do {
            switch choice {
            case .newSpace:
                preview = try importer.preview(url: url)
            case .merge(let id):
                preview = try importer.preview(url: url, mergeInto: space(with: id))
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
