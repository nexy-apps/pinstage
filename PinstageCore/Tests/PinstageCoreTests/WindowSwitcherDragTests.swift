import Foundation
import Testing
@testable import PinstageCore

@Suite("ウインドウスイッチャーのドラッグ")
struct WindowSwitcherDragTests {
    /// いまのデスクトップの a・b・c と、すべてのデスクトップの all。x はほかのデスクトップ
    private let rules = WindowSwitcherDragRules(currentDesktop: ["a", "b", "c", "all"])

    @Test("いまのデスクトップのウインドウはつかめる。ほかのデスクトップのものはつかめない（印と同じ）")
    func canCarry() {
        #expect(rules.canCarry("a"))
        #expect(rules.canCarry("all"))
        #expect(!rules.canCarry("x"))
        #expect(rules.carried(grabbing: "x", marked: []).isEmpty)
        #expect(rules.carried(grabbing: "x", marked: ["x", "a"]).isEmpty)
    }

    @Test("印のないウインドウをつかんだら、それだけを運ぶ")
    func unmarked() {
        #expect(rules.carried(grabbing: "a", marked: []) == ["a"])
        #expect(rules.carried(grabbing: "c", marked: ["a", "b"]) == ["c"])
    }

    @Test("印の付いたウインドウをつかんだら、印の付いたものを、付けた順にまとめて運ぶ")
    func marked() {
        #expect(rules.carried(grabbing: "a", marked: ["b", "c", "a"]) == ["b", "c", "a"])
        #expect(rules.carried(grabbing: "c", marked: ["b", "c", "a"]) == ["b", "c", "a"])
        // いまのデスクトップのものでなくなった印（デスクトップを移したなど）は運ばない
        #expect(rules.carried(grabbing: "a", marked: ["x", "a"]) == ["a"])
    }

    @Test("すべてのデスクトップのウインドウは、どの欄からつかんでも同じ 1 つ。2 つの欄で印を付けても 1 つと数える")
    func allDesktopsOnce() {
        // 欄ではなくウインドウで見分けるので、2 つの欄の項目は同じ "all"
        #expect(rules.carried(grabbing: "all", marked: []) == ["all"])
        #expect(rules.carried(grabbing: "all", marked: ["all", "a", "all"]) == ["all", "a"])
    }

    @Test("落とせる先: ステージとグループ。何もない所・ほかのデスクトップの欄は落とせない")
    func accepts() {
        let signature = WindowSignature(bundleID: "com.apple.Safari", title: "資料")
        let group = WindowSwitcherDropTarget.group(UUID())
        #expect(WindowSwitcherDrop.accepts(.stage, carried: [signature]))
        #expect(WindowSwitcherDrop.accepts(group, carried: [signature, nil]))
        #expect(!WindowSwitcherDrop.accepts(nil, carried: [signature]))
        // 運んでいるものがない・グループに入れられるものがない
        #expect(!WindowSwitcherDrop.accepts(.stage, carried: []))
        #expect(WindowSwitcherDrop.accepts(.stage, carried: [nil]))
        #expect(!WindowSwitcherDrop.accepts(group, carried: [nil]))
    }

    @Test("グループに足す: もう入っているもの・重なったものは足さない（運んだ順）")
    func addToGroup() {
        let safari = WindowSignature(bundleID: "com.apple.Safari", title: "資料")
        let notes = WindowSignature(bundleID: "com.apple.Notes", title: "メモ")
        let code = WindowSignature(bundleID: "com.example.editor", title: "app")
        var library = StageLibrary(groups: [StageGroup(name: "作業", members: [safari], layout: .builtIn(.auto), displayID: nil)])
        let id = library.groups[0].id
        let added = library.addMembers([notes, safari], toGroup: id)
        #expect(added == 1)
        #expect(library.groups[0].members == [safari, notes])
        let again = library.addMembers([safari, notes], toGroup: id)
        #expect(again == 0)
        #expect(library.groups[0].members == [safari, notes])
        let deduped = library.addMembers([code, notes, code], toGroup: id)
        #expect(deduped == 1)
        #expect(library.groups[0].members == [safari, notes, code])
        let unknown = library.addMembers([code], toGroup: UUID())
        #expect(unknown == 0)
    }

    @Test("下の帯（落とす先）を出すときは、その分だけ高くする")
    func dropBarHeight() {
        typealias Layout = WindowSwitcherLayout
        let plain = Layout.overviewHeight(for: .list, sectionCounts: [6], titledSections: false, columns: 1, maximumHeight: 900)
        let withBar = Layout.overviewHeight(for: .list, sectionCounts: [6], titledSections: false, columns: 1, maximumHeight: 900, showsDropBar: true)
        #expect(withBar == plain + Layout.blockSpacing + Layout.dropBarHeight)
    }
}
