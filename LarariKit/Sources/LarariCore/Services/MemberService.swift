import CloudKit
import CoreData
import Foundation

@MainActor
public final class MemberService {
    public static var newMemberName: String {
        String(localized: "member.newMember", defaultValue: "New member", bundle: .module)
    }

    private let persistence: PersistenceController
    private let spaceStore: SpaceStore
    private let sharing: SharingService
    private let userRecordName: String

    public init(persistence: PersistenceController, spaceStore: SpaceStore, sharing: SharingService, userRecordName: String) {
        self.persistence = persistence
        self.spaceStore = spaceStore
        self.sharing = sharing
        self.userRecordName = userRecordName
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    @discardableResult
    public func ensureCurrentMember(in space: Space, displayName: String, avatar: Data?,
                                    colorKey: String? = nil) throws -> Member {
        guard space.kind == .household else { throw SharingError.personalSpace }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ServiceError.nameRequired }
        guard sharing.canEdit(space) else { throw ServiceError.readOnlySpace }

        let member = currentMember(in: space) ?? {
            let inserted = spaceStore.insert(Member.self, in: space, by: userRecordName)
            inserted.space = space
            return inserted
        }()
        member.userRecordName = userRecordName
        member.colorSeed = userRecordName
        member.displayName = name
        member.colorKey = colorKey.flatMap { MemberColor.preset(forKey: $0)?.key }
        if avatar != member.avatar {
            member.avatar = try avatar.map(ImageProcessor.prepare)
        }
        member.stamp(by: userRecordName)
        try context.save()
        return member
    }

    /// The current user's record; the oldest wins if two devices created one concurrently
    /// (P5-04's deduplication removes the other).
    public func currentMember(in space: Space) -> Member? {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "space == %@ AND userRecordName == %@", space, userRecordName)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try? context.fetch(request).first
    }

    public func members(in space: Space) throws -> [Member] {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "space == %@", space)
        return try context.fetch(request)
            .sorted { ($0.displayName ?? "").localizedStandardCompare($1.displayName ?? "") == .orderedAscending }
    }

    public func displayName(for userRecordName: String, in space: Space) -> String {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "space == %@ AND userRecordName == %@ AND displayName != %@", space, userRecordName, "")
        request.fetchLimit = 1
        let name = (try? context.fetch(request).first)?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false ? name : nil) ?? Self.newMemberName
    }

    /// The member's hand-picked colour key in `space`, for rings drawn outside the member list (P5-04).
    public func colorKey(for userRecordName: String, in space: Space) -> String? {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "space == %@ AND userRecordName == %@", space, userRecordName)
        request.fetchLimit = 1
        return (try? context.fetch(request).first)?.colorKey
    }

    public func needsSetup(in space: Space) -> Bool {
        guard space.kind == .household, sharing.role(for: space) != .notShared, sharing.canEdit(space) else { return false }
        let name = currentMember(in: space)?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
    }

    public func suggestedDisplayName(in space: Space) -> String {
        if let own = currentMember(in: space)?.displayName, !own.trimmingCharacters(in: .whitespaces).isEmpty { return own }
        if let elsewhere = sharing.suggestedOwnerDisplayName() { return elsewhere }
        if sharing.isCloudBacked, let share = sharing.share(for: space),
           let fromCloudKit = MemberDirectory.suggestedName(from: ParticipantSnapshot.snapshots(of: share, currentUserRecordName: userRecordName)) {
            return fromCloudKit
        }
        return ""
    }

    public func memberRows(in space: Space) -> [MemberRow] {
        // Local mode: LocalCloudSharing's share has no real participants; list the Member records only.
        let share = sharing.isCloudBacked ? sharing.share(for: space) : nil
        let participants = share.map {
            ParticipantSnapshot.snapshots(of: $0, currentUserRecordName: userRecordName)
        } ?? []
        let members = ((try? members(in: space)) ?? []).map(MemberSnapshot.init)
        return MemberDirectory.rows(participants: participants, members: members,
                                    currentUserRecordName: userRecordName, newMemberName: Self.newMemberName,
                                    currentUserIsOwner: sharing.role(for: space) == .owner)
    }
}
