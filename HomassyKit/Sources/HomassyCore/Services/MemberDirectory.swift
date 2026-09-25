import CloudKit
import Foundation

/// A Sendable copy of what the app needs from CKShare.Participant.
public struct ParticipantSnapshot: Sendable, Equatable, Identifiable {
    public enum Role: Sendable, Equatable { case owner, member }
    public enum Permission: Sendable, Equatable { case readOnly, readWrite, unknown }
    public enum Acceptance: Sendable, Equatable { case pending, accepted, removed, unknown }

    public let id: String
    public let userRecordName: String?
    public let nameComponents: PersonNameComponents?
    public let role: Role
    public let permission: Permission
    public let acceptance: Acceptance
    public let isCurrentUser: Bool

    public init(id: String, userRecordName: String?, nameComponents: PersonNameComponents?,
                role: Role, permission: Permission, acceptance: Acceptance, isCurrentUser: Bool) {
        self.id = id
        self.userRecordName = userRecordName
        self.nameComponents = nameComponents
        self.role = role
        self.permission = permission
        self.acceptance = acceptance
        self.isCurrentUser = isCurrentUser
    }

    /// On the owner's device the owner's own record name reads as CKCurrentUserDefaultName, so the
    /// current participant is mapped to the real userRecordName the app stamps on records.
    @MainActor
    public static func snapshots(of share: CKShare, currentUserRecordName: String) -> [ParticipantSnapshot] {
        let current = share.currentUserParticipant
        return share.participants.enumerated().map { index, participant in
            let isCurrent = current.map { $0 == participant } ?? false
            let rawName = participant.userIdentity.userRecordID?.recordName
            let recordName = isCurrent ? currentUserRecordName : (rawName == CKCurrentUserDefaultName ? nil : rawName)
            let lookup = participant.userIdentity.lookupInfo
            let id = recordName ?? lookup?.emailAddress ?? lookup?.phoneNumber ?? "participant-\(index)"

            let permission: Permission
            switch participant.permission {
            case .readOnly: permission = .readOnly
            case .readWrite: permission = .readWrite
            default: permission = .unknown
            }
            let acceptance: Acceptance
            switch participant.acceptanceStatus {
            case .pending: acceptance = .pending
            case .accepted: acceptance = .accepted
            case .removed: acceptance = .removed
            default: acceptance = .unknown
            }
            return ParticipantSnapshot(
                id: id, userRecordName: recordName, nameComponents: participant.userIdentity.nameComponents,
                role: participant.role == .owner ? .owner : .member,
                permission: permission, acceptance: acceptance, isCurrentUser: isCurrent)
        }
    }
}

public struct MemberSnapshot: Sendable, Equatable {
    public let userRecordName: String
    public let displayName: String
    public let colorSeed: String
    public let avatar: Data?
    public let colorKey: String?

    public init(userRecordName: String, displayName: String, colorSeed: String, avatar: Data?, colorKey: String? = nil) {
        self.userRecordName = userRecordName
        self.displayName = displayName
        self.colorSeed = colorSeed
        self.avatar = avatar
        self.colorKey = colorKey
    }

    @MainActor
    public init(_ member: Member) {
        let record = member.userRecordName ?? ""
        let seed = member.colorSeed ?? ""
        self.init(userRecordName: record, displayName: member.displayName ?? "",
                  colorSeed: seed.isEmpty ? record : seed,
                  avatar: member.avatar, colorKey: member.colorKey)
    }
}

public struct MemberRow: Identifiable, Equatable, Sendable {
    public enum Status: Sendable, Equatable { case active, invited, departed }

    public let id: String
    public let displayName: String
    public let userRecordName: String?
    public let colorSeed: String?
    public let colorKey: String?
    public let avatar: Data?
    public let isOwner: Bool
    public let permission: ParticipantSnapshot.Permission
    public let status: Status
    public let isCurrentUser: Bool
}

public enum MemberDirectory {
    /// `currentUserIsOwner` only matters without participants (local mode or an unshared household):
    /// it marks the user's own row as the owner, which a share's participant list says otherwise.
    public static func rows(participants: [ParticipantSnapshot], members: [MemberSnapshot],
                            currentUserRecordName: String, newMemberName: String,
                            currentUserIsOwner: Bool = false) -> [MemberRow] {
        var membersByRecord: [String: MemberSnapshot] = [:]
        for member in members where membersByRecord[member.userRecordName] == nil {
            membersByRecord[member.userRecordName] = member
        }
        func name(_ member: MemberSnapshot?) -> String? {
            guard let trimmed = member?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }

        var rows: [MemberRow] = []
        var covered = Set<String>()

        if participants.isEmpty {
            for member in membersByRecord.values {
                rows.append(MemberRow(id: member.userRecordName, displayName: name(member) ?? newMemberName,
                                      userRecordName: member.userRecordName, colorSeed: member.colorSeed,
                                      colorKey: member.colorKey, avatar: member.avatar,
                                      isOwner: member.userRecordName == currentUserRecordName && currentUserIsOwner,
                                      permission: .readWrite, status: .active,
                                      isCurrentUser: member.userRecordName == currentUserRecordName))
            }
            return sorted(rows)
        }

        for participant in participants {
            let member = participant.userRecordName.flatMap { membersByRecord[$0] }
            if let record = participant.userRecordName { covered.insert(record) }
            let status: MemberRow.Status
            switch participant.acceptance {
            case .accepted, .unknown: status = .active
            case .pending: status = .invited
            case .removed:
                guard member != nil else { continue }
                status = .departed
            }
            let lookupName = participant.acceptance == .pending
                ? participant.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                : nil
            rows.append(MemberRow(
                id: participant.id,
                displayName: name(member) ?? lookupName.flatMap { $0.isEmpty ? nil : $0 } ?? newMemberName,
                userRecordName: participant.userRecordName,
                colorSeed: member?.colorSeed ?? participant.userRecordName,
                colorKey: member?.colorKey,
                avatar: member?.avatar,
                isOwner: participant.role == .owner,
                permission: participant.permission,
                status: status,
                isCurrentUser: participant.isCurrentUser || participant.userRecordName == currentUserRecordName))
        }

        for member in membersByRecord.values where !covered.contains(member.userRecordName) {
            rows.append(MemberRow(id: member.userRecordName, displayName: name(member) ?? newMemberName,
                                  userRecordName: member.userRecordName, colorSeed: member.colorSeed,
                                  colorKey: member.colorKey, avatar: member.avatar,
                                  isOwner: false, permission: .unknown, status: .departed,
                                  isCurrentUser: false))
        }
        return sorted(rows)
    }

    public static func suggestedName(from participants: [ParticipantSnapshot]) -> String? {
        guard let components = participants.first(where: \.isCurrentUser)?.nameComponents else { return nil }
        if let given = components.givenName?.trimmingCharacters(in: .whitespaces), !given.isEmpty { return given }
        let full = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return full.isEmpty ? nil : full
    }

    private static func sorted(_ rows: [MemberRow]) -> [MemberRow] {
        func rank(_ row: MemberRow) -> Int {
            switch row.status {
            case .departed: return 4
            case .invited: return 3
            case .active: return row.isOwner ? 0 : (row.isCurrentUser ? 1 : 2)
            }
        }
        return rows.sorted {
            let (l, r) = (rank($0), rank($1))
            if l != r { return l < r }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
