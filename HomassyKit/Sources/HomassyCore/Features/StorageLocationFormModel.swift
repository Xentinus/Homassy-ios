import Foundation
import Observation

@MainActor
@Observable
public final class StorageLocationFormModel {
    public enum Mode {
        case create(Space)
        case edit(StorageLocation)
    }

    public var name: String
    public var color: StorageColor?
    public var isFreezer: Bool
    public private(set) var errorMessage: String?

    private let mode: Mode
    private let service: StorageLocationService

    public init(mode: Mode, service: StorageLocationService) {
        self.mode = mode
        self.service = service
        switch mode {
        case .create:
            name = ""
            color = nil
            isFreezer = false
        case .edit(let location):
            name = location.name
            color = location.storageColor
            isFreezer = location.isFreezer
        }
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var canSave: Bool { name.nilIfBlank != nil }

    /// Returns true when saved; otherwise `errorMessage` says why.
    public func save() -> Bool {
        do {
            switch mode {
            case .create(let space):
                try service.create(in: space, name: name, color: color, isFreezer: isFreezer)
            case .edit(let location):
                try service.update(location, name: name, color: color, isFreezer: isFreezer)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
