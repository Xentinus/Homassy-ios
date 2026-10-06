import Foundation
import Observation

@MainActor
@Observable
public final class NewHouseholdModel {
    public var name = ""
    public var ownerDisplayName: String
    public private(set) var isCreating = false
    public private(set) var createdSpace: Space?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: SharingService

    public init(service: SharingService) {
        self.service = service
        self.ownerDisplayName = service.suggestedOwnerDisplayName() ?? ""
    }

    public var canCreate: Bool {
        !isCreating && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func create() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            createdSpace = try await service.createHousehold(name: name, ownerDisplayName: ownerDisplayName)
        } catch let error as SharingError {
            if case let .createdButNotShared(id) = error { createdSpace = service.space(withPublicId: id) }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
