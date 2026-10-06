import Foundation
import Observation

@MainActor
@Observable
public final class MemberSetupModel {
    public let spaceName: String
    public var name: String
    public var avatarData: Data?
    /// A `MemberColor.selectablePresets` key, or nil for automatic.
    public var colorKey: String?
    public private(set) var errorMessage: String?
    public private(set) var didSave = false

    @ObservationIgnored private let service: MemberService
    @ObservationIgnored private let space: Space

    public init(service: MemberService, space: Space) {
        self.service = service
        self.space = space
        self.spaceName = space.name
        self.name = service.suggestedDisplayName(in: space)
        self.avatarData = service.currentMember(in: space)?.avatar
        self.colorKey = service.currentMember(in: space)?.colorKey
    }

    public var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public func save() {
        errorMessage = nil
        do {
            try service.ensureCurrentMember(in: space, displayName: name, avatar: avatarData, colorKey: colorKey)
            didSave = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Households where the user chose "Later" on member setup.
public struct MemberSetupSkips {
    private static let key = "memberSetupSkippedSpaceIDs"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func isSkipped(_ spaceId: UUID) -> Bool {
        defaults.stringArray(forKey: Self.key)?.contains(spaceId.uuidString) ?? false
    }

    public func skip(_ spaceId: UUID) {
        var ids = defaults.stringArray(forKey: Self.key) ?? []
        guard !ids.contains(spaceId.uuidString) else { return }
        ids.append(spaceId.uuidString)
        defaults.set(ids, forKey: Self.key)
    }
}
