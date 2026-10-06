import Foundation
import Testing
@testable import LarariCore

struct MemberDirectoryTests {
    let me = "_me"
    let newMember = "New member"

    func participant(_ name: String?, role: ParticipantSnapshot.Role = .member,
                     permission: ParticipantSnapshot.Permission = .readWrite,
                     acceptance: ParticipantSnapshot.Acceptance = .accepted,
                     components: PersonNameComponents? = nil) -> ParticipantSnapshot {
        ParticipantSnapshot(id: name ?? "invite-\(components?.givenName ?? "x")", userRecordName: name,
                            nameComponents: components, role: role, permission: permission,
                            acceptance: acceptance, isCurrentUser: name == me)
    }

    func member(_ record: String, _ name: String) -> MemberSnapshot {
        MemberSnapshot(userRecordName: record, displayName: name, colorSeed: record, avatar: nil)
    }

    @Test func acceptedParticipantUsesMemberRecord() {
        let rows = MemberDirectory.rows(participants: [participant("_anna")], members: [member("_anna", "Anna")],
                                        currentUserRecordName: me, newMemberName: newMember)
        #expect(rows.count == 1)
        #expect(rows[0].displayName == "Anna")
        #expect(rows[0].colorSeed == "_anna")
        #expect(rows[0].status == .active)
        #expect(rows[0].permission == .readWrite)
    }

    @Test func acceptedParticipantWithoutRecordIsNewMember() {
        let rows = MemberDirectory.rows(participants: [participant("_anna")], members: [member("_anna", "  ")],
                                        currentUserRecordName: me, newMemberName: newMember)
        #expect(rows[0].displayName == newMember)
        #expect(rows[0].colorSeed == "_anna")
    }

    @Test func pendingInviteUsesLookupNameWhenKnown() {
        var components = PersonNameComponents()
        components.givenName = "Béla"
        let rows = MemberDirectory.rows(participants: [participant(nil, acceptance: .pending, components: components)],
                                        members: [], currentUserRecordName: me, newMemberName: newMember)
        #expect(rows[0].displayName == "Béla")
        #expect(rows[0].status == .invited)
        #expect(rows[0].colorSeed == nil)
    }

    @Test func removedParticipantWithRecordBecomesFormerMember() {
        let rows = MemberDirectory.rows(participants: [participant("_anna", acceptance: .removed), participant("_zoli", acceptance: .removed)],
                                        members: [member("_anna", "Anna")],
                                        currentUserRecordName: me, newMemberName: newMember)
        #expect(rows.map(\.displayName) == ["Anna"])
        #expect(rows[0].status == .departed)
    }

    @Test func memberRecordWithoutParticipantIsFormerMemberWhenShared() {
        let rows = MemberDirectory.rows(participants: [participant(me, role: .owner)],
                                        members: [member(me, "Béla"), member("_gone", "Gábor")],
                                        currentUserRecordName: me, newMemberName: newMember)
        #expect(rows.map(\.displayName) == ["Béla", "Gábor"])
        #expect(rows.map(\.status) == [.active, .departed])
    }

    @Test func unsharedSpaceListsMemberRecordsAsActive() {
        let rows = MemberDirectory.rows(participants: [], members: [member(me, "Béla"), member("_x", "Xénia")],
                                        currentUserRecordName: me, newMemberName: newMember)
        #expect(rows.allSatisfy { $0.status == .active })
        #expect(rows.first?.isCurrentUser == true)
    }

    @Test func ordersOwnerThenYouThenActiveByNameThenInvitedThenDeparted() {
        let rows = MemberDirectory.rows(
            participants: [
                participant("_zoli"), participant(me), participant("_anna", role: .owner),
                participant("_bea"), participant(nil, acceptance: .pending)
            ],
            members: [member("_zoli", "Zoli"), member(me, "Me"), member("_anna", "Anna"), member("_bea", "Bea"), member("_old", "Old")],
            currentUserRecordName: me, newMemberName: newMember)
        #expect(rows.map(\.displayName) == ["Anna", "Me", "Bea", "Zoli", newMember, "Old"])
        #expect(rows[0].isOwner)
        #expect(rows[1].isCurrentUser)
    }

    @Test func suggestedNameComesFromCurrentUserComponents() {
        var components = PersonNameComponents()
        components.givenName = "Anna"
        components.familyName = "Kovács"
        let snapshot = ParticipantSnapshot(id: me, userRecordName: me, nameComponents: components,
                                           role: .member, permission: .readWrite, acceptance: .accepted, isCurrentUser: true)
        #expect(MemberDirectory.suggestedName(from: [snapshot]) == "Anna")
        #expect(MemberDirectory.suggestedName(from: [participant("_other")]) == nil)
    }
}
