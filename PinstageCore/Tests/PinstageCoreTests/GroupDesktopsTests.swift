import Foundation
import Testing
@testable import PinstageCore

@Suite("グループを出すデスクトップを、メンバーのいる所に合わせる")
struct GroupDesktopRuleTests {
    @Test("1 つのデスクトップに集まっていれば、そのデスクトップ（移せば、ついていく）")
    func gathered() {
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("A"), .desktop("A")]) == "A")
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("B"), .desktop("B")]) == "B")
    }

    @Test("分かれたら、いちばん多くいるデスクトップ")
    func most() {
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("A"), .desktop("B"), .desktop("B")]) == "B")
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("B"), .desktop("A"), .desktop("A")]) == "A")
    }

    @Test("同じ数なら、いま覚えているデスクトップのまま。その中になければ、先に並んだメンバーのいる所")
    func tie() {
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("B"), .desktop("A")]) == "A")
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("C"), .desktop("B")]) == "C")
        #expect(GroupDesktopRule.destination(current: "A", members: [.desktop("B"), .desktop("C"), .desktop("C"), .desktop("B")]) == "B")
    }

    @Test("1 つも開いていない・いる所が分からないときは、いま覚えているデスクトップのまま")
    func unknown() {
        #expect(GroupDesktopRule.destination(current: "A", members: []) == "A")
        #expect(GroupDesktopRule.destination(current: "A", members: [.unknown, .unknown]) == "A")
    }

    @Test("すべてのデスクトップに割り当てたウインドウは数に入れない")
    func allDesktopsMember() {
        #expect(GroupDesktopRule.destination(current: "A", members: [.allDesktops, .allDesktops]) == "A")
        #expect(GroupDesktopRule.destination(current: "A", members: [.allDesktops, .allDesktops, .desktop("B")]) == "B")
    }

    @Test("すべてのデスクトップに出すグループは合わせない")
    func allDesktopsGroup() {
        #expect(GroupDesktopRule.destination(current: nil, members: [.desktop("B"), .desktop("B")]) == nil)
    }

    @Test("ウインドウのあるデスクトップから、メンバーのいる所を決める")
    func memberDesktop() {
        let uuids: [UInt64: String] = [1: "A", 2: "B"]
        #expect(MemberDesktop(spaces: [2], desktopUUIDs: uuids) == .desktop("B"))
        #expect(MemberDesktop(spaces: [1, 2], desktopUUIDs: uuids) == .allDesktops)
        #expect(MemberDesktop(spaces: [], desktopUUIDs: uuids) == .unknown)
        #expect(MemberDesktop(spaces: nil, desktopUUIDs: uuids) == .unknown)
        // UUID が分からない（フルスクリーンのアプリのデスクトップなど）
        #expect(MemberDesktop(spaces: [9], desktopUUIDs: uuids) == .unknown)
    }
}

@Suite("分かれているときの印と、外すメンバー")
struct GroupDesktopStatusTests {
    @Test("出すデスクトップにいる数 / 数えた数。すべてのデスクトップのメンバーは「いる」、閉じている・分からないものは数えない")
    func badge() {
        let status = GroupDesktopStatus(desktopID: "A", members: [.desktop("A"), .desktop("B"), .allDesktops, .unknown])
        #expect(status.isSplit)
        #expect(status.presentCount == 2)
        #expect(status.countedCount == 3)
        #expect(status.badge == "2/3")
        #expect(status.strayIndices == [1])
    }

    @Test("1 つだけ移したら「1/2」")
    func oneMoved() {
        let status = GroupDesktopStatus(desktopID: "A", members: [.desktop("B"), .desktop("A")])
        #expect(status.badge == "1/2")
        #expect(status.strayIndices == [0])
    }

    @Test("分かれていなければ印を出さない")
    func notSplit() {
        let status = GroupDesktopStatus(desktopID: "A", members: [.desktop("A"), .allDesktops, .unknown])
        #expect(!status.isSplit)
        #expect(status.badge == nil)
        #expect(status.strayIndices.isEmpty)
    }

    @Test("すべてのデスクトップに出すグループは、分かれていても印を出さない")
    func allDesktopsGroup() {
        let status = GroupDesktopStatus(desktopID: nil, members: [.desktop("A"), .desktop("B")])
        #expect(!status.isSplit)
        #expect(status.badge == nil)
    }

    @Test("ほかのデスクトップにいるメンバーを、番号でまとめて外す（大きい番号から外すので、番号がずれない）")
    func removeStrays() {
        let members = (0..<4).map { WindowSignature(bundleID: "app\($0)", title: "") }
        var library = StageLibrary(groups: [StageGroup(name: "作業", members: members, layout: .builtIn(.auto), displayID: nil, desktopID: "A")])
        let id = library.groups[0].id
        let removed = library.removeMembers(at: [0, 2, 9, 2], fromGroup: id)
        #expect(removed == 2)
        #expect(library.groups[0].members == [members[1], members[3]])
        let none = library.removeMembers(at: [0], fromGroup: UUID())
        #expect(none == 0)
    }
}

@Suite("グループがデスクトップについていく")
struct GroupFollowDesktopTests {
    private func library(displayID: String?, desktopID: String?) -> StageLibrary {
        StageLibrary(groups: [StageGroup(name: "作業", members: [], layout: .builtIn(.auto), displayID: displayID, desktopID: desktopID)])
    }

    @Test("行き先のデスクトップに移す。別のディスプレイなら、出すディスプレイも合わせる")
    func follow() {
        var library = library(displayID: "D1", desktopID: "A")
        let id = library.groups[0].id
        let moved = library.followDesktop("B", display: "D2", ofGroup: id)
        #expect(moved)
        #expect(library.groups[0].desktopID == "B")
        #expect(library.groups[0].displayID == "D2")
        // 同じなら変えない
        let same = library.followDesktop("B", display: "D2", ofGroup: id)
        #expect(!same)
        // ディスプレイが分からなければ、ディスプレイは変えない
        let withoutDisplay = library.followDesktop("C", display: nil, ofGroup: id)
        #expect(withoutDisplay)
        #expect(library.groups[0].displayID == "D2")
    }

    @Test("ディスプレイを決めていないグループは、ディスプレイを決めない。すべてのデスクトップのグループは動かさない")
    func keepsUnassigned() {
        var library = library(displayID: nil, desktopID: "A")
        let id = library.groups[0].id
        library.followDesktop("B", display: "D2", ofGroup: id)
        #expect(library.groups[0].displayID == nil)
        var all = self.library(displayID: nil, desktopID: nil)
        let followed = all.followDesktop("B", display: nil, ofGroup: all.groups[0].id)
        #expect(!followed)
        #expect(all.groups[0].desktopID == nil)
    }
}

@Suite("行ったり来たりを抑える")
struct DesktopFollowStabilizerTests {
    /// #expect の中では書き換える関数を呼べないので、包む
    private func observe(_ stabilizer: inout DesktopFollowStabilizer<Int>, _ key: Int, current: String?, destination: String?, now: TimeInterval) -> String? {
        stabilizer.observe(key, current: current, destination: destination, now: now)
    }

    @Test("同じ行き先が 3 回・2 秒続いたら合わせる")
    func settles() {
        var stabilizer = DesktopFollowStabilizer<Int>(requiredReadings: 3, minimumDuration: 2)
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 0) == nil)
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 1.5) == nil)
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 3) == "B")
        // 合わせたら、数え直す（まだ合わせていない扱いの読み直しでも、また 3 回待つ）
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 10) == nil)
    }

    @Test("立て続けの読み直しでは、回数が揃っても時間が経つまで合わせない")
    func waitsForDuration() {
        var stabilizer = DesktopFollowStabilizer<Int>(requiredReadings: 3, minimumDuration: 2)
        for time in [0, 0.3, 0.6, 0.9] {
            #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: time) == nil)
        }
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 2.1) == "B")
    }

    @Test("途中で行き先が変わったら、数え直す")
    func restartsOnChange() {
        var stabilizer = DesktopFollowStabilizer<Int>(requiredReadings: 3, minimumDuration: 0)
        _ = stabilizer.observe(1, current: "A", destination: "B", now: 0)
        _ = stabilizer.observe(1, current: "A", destination: "B", now: 1)
        // ほかのデスクトップのウインドウが見つかって、行き先が変わった
        #expect(observe(&stabilizer, 1, current: "A", destination: "C", now: 2) == nil)
        #expect(observe(&stabilizer, 1, current: "A", destination: "C", now: 3) == nil)
        #expect(observe(&stabilizer, 1, current: "A", destination: "C", now: 4) == "C")
    }

    @Test("行き先がいまのままに戻ったら、数え直す")
    func restartsOnReturn() {
        var stabilizer = DesktopFollowStabilizer<Int>(requiredReadings: 3, minimumDuration: 0)
        _ = stabilizer.observe(1, current: "A", destination: "B", now: 0)
        _ = stabilizer.observe(1, current: "A", destination: "B", now: 1)
        #expect(observe(&stabilizer, 1, current: "A", destination: "A", now: 2) == nil)
        // 前の 2 回は数えないので、ここから 3 回要る
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 3) == nil)
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 4) == nil)
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 5) == "B")
        // すべてのデスクトップのグループ（行き先なし）は合わせない
        #expect(observe(&stabilizer, 2, current: nil, destination: nil, now: 0) == nil)
    }

    @Test("数え直し（デスクトップを切り替えた直後）・なくなったグループを捨てる。グループごとに別々に数える")
    func resetAndPrune() {
        var stabilizer = DesktopFollowStabilizer<Int>(requiredReadings: 2, minimumDuration: 0)
        _ = stabilizer.observe(1, current: "A", destination: "B", now: 0)
        _ = stabilizer.observe(2, current: "A", destination: "C", now: 0)
        stabilizer.reset()
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 1) == nil)
        _ = stabilizer.observe(2, current: "A", destination: "C", now: 1)
        stabilizer.prune(keeping: [1])
        #expect(observe(&stabilizer, 1, current: "A", destination: "B", now: 2) == "B")
        // 捨てたグループは数え直す（2 回目でなく 1 回目になる）
        #expect(observe(&stabilizer, 2, current: "A", destination: "C", now: 2) == nil)
    }
}

@Suite("メンバーが 1 つ以下になったら解消する")
struct GroupDissolutionTests {
    private let a = WindowSignature(bundleID: "a", title: "")
    private let b = WindowSignature(bundleID: "b", title: "")
    private let c = WindowSignature(bundleID: "c", title: "")

    private func group(_ name: String, _ members: [WindowSignature]) -> StageGroup {
        StageGroup(name: name, members: members, layout: .builtIn(.auto), displayID: nil, desktopID: "A")
    }

    @Test("外して 1 つになったら解消する。2 つ以上残れば解消しない")
    func single() {
        let before = StageLibrary(groups: [group("作業", [a, b]), group("調べもの", [a, b, c])])
        var edited = before
        edited.removeMember(at: 0, fromGroup: before.groups[0].id)
        let edit = GroupMemberEdit(before: before, edited: edited)
        #expect(edit.needsConfirmation)
        #expect(edit.dissolving.map(\.name) == ["作業"])
        #expect(edit.resolved.groups.map(\.name) == ["調べもの"])

        var kept = before
        kept.removeMember(at: 0, fromGroup: before.groups[1].id)
        let keepEdit = GroupMemberEdit(before: before, edited: kept)
        #expect(!keepEdit.needsConfirmation)
        #expect(keepEdit.resolved == kept)
    }

    @Test("最後の 1 つを外す・移して空になるときも解消する。1 つだけで保存したグループは、減らなければ解消しない")
    func lastMember() {
        let before = StageLibrary(groups: [group("1 つ", [a]), group("行き先", [b, c])])
        var moved = before
        moved.moveMember(at: 0, from: before.groups[0].id, to: before.groups[1].id)
        let edit = GroupMemberEdit(before: before, edited: moved)
        #expect(edit.dissolving.map(\.name) == ["1 つ"])
        // 移す先は増えるだけ（解消後も残る）
        #expect(edit.resolved.groups.map(\.name) == ["行き先"])
        #expect(edit.resolved.groups[0].members == [b, c, a])

        var reordered = before
        reordered.renameGroup(before.groups[0].id, to: "名前だけ")
        #expect(!GroupMemberEdit(before: before, edited: reordered).needsConfirmation)
    }

    @Test("ほかのグループへ移して、元のグループが 1 つになったら解消する")
    func moveLeavesOne() {
        let before = StageLibrary(groups: [group("元", [a, b]), group("先", [c, a])])
        var moved = before
        moved.moveMember(at: 1, from: before.groups[0].id, to: before.groups[1].id)
        let edit = GroupMemberEdit(before: before, edited: moved)
        #expect(edit.dissolving.map(\.name) == ["元"])
        #expect(edit.resolved.groups.map(\.name) == ["先"])
        #expect(edit.resolved.groups[0].members == [c, a, b])
    }

    @Test("1 回の操作で複数のグループが 1 つ以下になるときは、まとめて解消する。減るだけのグループも一緒に変える")
    func several() {
        let before = StageLibrary(groups: [group("作業", [a, b]), group("調べもの", [a, c]), group("全部", [a, b, c])])
        // 同じウインドウ（a）を、すべてのグループから外す
        var edited = before
        for group in before.groups {
            if let index = group.members.firstIndex(of: a) { edited.removeMember(at: index, fromGroup: group.id) }
        }
        let edit = GroupMemberEdit(before: before, edited: edited)
        #expect(edit.dissolving.map(\.name) == ["作業", "調べもの"])
        #expect(edit.resolved.groups.map(\.name) == ["全部"])
        #expect(edit.resolved.groups[0].members == [b, c])
    }

    @Test("この操作で足した・消したグループは解消しない")
    func addedOrRemoved() {
        let before = StageLibrary(groups: [group("作業", [a, b])])
        var edited = before
        edited.removeGroup(before.groups[0].id)
        edited.addGroup(name: "新しい", content: StageGroup.Content(members: [a], layout: .builtIn(.auto), displayID: nil))
        #expect(!GroupMemberEdit(before: before, edited: edited).needsConfirmation)
    }

    @Test("確かめの文（1 つ・複数。名前は 5 つまで、残りは「ほか n つ」）")
    func text() {
        let one = [group("作業", [])]
        #expect(GroupDissolutionText.title(for: one) == "グループ「作業」を解消しますか？")
        #expect(GroupDissolutionText.message(for: one) == "外すと、グループのウインドウが 1 つ以下になるので、グループを解消します。ウインドウは閉じません。")

        let three = ["作業", "調べもの", "メール"].map { group($0, []) }
        #expect(GroupDissolutionText.title(for: three) == "3 つのグループを解消しますか？")
        #expect(GroupDissolutionText.message(for: three).hasSuffix("\n\n「作業」「調べもの」「メール」"))

        let seven = (1...7).map { group("G\($0)", []) }
        #expect(GroupDissolutionText.names(seven) == "「G1」「G2」「G3」「G4」「G5」ほか 2 つ")
        #expect(GroupDissolutionText.names(Array(seven.prefix(5))) == "「G1」「G2」「G3」「G4」「G5」")
    }

    @Test("解消する前に確かめるか（既定はオン。保存して読み戻せる）")
    func setting() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(GroupDissolutionSetting.confirms(in: defaults))
        GroupDissolutionSetting.save(false, to: defaults)
        #expect(!GroupDissolutionSetting.confirms(in: defaults))
        GroupDissolutionSetting.save(true, to: defaults)
        #expect(GroupDissolutionSetting.confirms(in: defaults))
    }
}
