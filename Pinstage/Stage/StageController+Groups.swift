import AppKit
import PinstageCore

/// グループの保存と編集
///
/// グループの中身（StageGroup.Content）は、いまのステージから作るか、見えている画面を記録して作る。
/// 新しいグループにするのも、前からあるグループを上書きするのも、作った中身を入れるだけ。
extension StageController {
    // MARK: - グループの中身を作る

    /// そのディスプレイのいまのステージから、グループの中身を作る（ステージが空なら nil）
    private func stageContent(on screen: NSScreen) -> StageGroup.Content? {
        let stage = self.stage(on: screen)
        let members = stageItems(on: screen).compactMap(\.signature)
        guard !members.isEmpty else { return nil }
        return StageGroup.Content(members: members, layout: stage.layout, displayID: screen.displayUUID, desktopID: currentDesktopID(on: screen))
    }

    /// そのディスプレイで、いま表に出ているデスクトップの UUID（保存したグループは、このデスクトップのウインドウバーに出す。分からなければ nil で、すべてのデスクトップ）
    private func currentDesktopID(on screen: NSScreen) -> String? {
        guard SkyLight.isAvailable, let displays = SkyLight.displays(),
              let display = SkyLight.display(forKey: Self.displayKey(screen), in: displays)
        else { return nil }
        return display.spaces.first { $0.id == display.current }?.uuid
    }

    /// デスクトップの番号から、その UUID（グループを出すデスクトップとして覚える値。分からなければ nil）
    private func desktopID(of space: UInt64?) -> String? {
        space.flatMap { desktopUUIDs[$0] }
    }

    /// 見えている画面から、グループの中身を作る（位置・大きさ・重なりの順番ごと記録する）。ステージも、その組み合わせにする
    private func recordedContent(on screen: NSScreen) -> StageGroup.Content? {
        let arrangement = visibleArrangement(on: screen).filter { $0.item.signature != nil }
        guard !arrangement.isEmpty else { return nil }
        let layout = LayoutChoice.recording(arrangement.map(\.frame), in: stageArea(on: screen))
        updateStage(on: screen, apply: false) { stage in
            stage.selection.replace(with: arrangement.map(\.item.id))
            stage.layout = layout
        }
        return StageGroup.Content(
            members: arrangement.compactMap(\.item.signature),
            layout: layout,
            displayID: screen.displayUUID,
            desktopID: currentDesktopID(on: screen)
        )
    }

    /// そのディスプレイに見えているウインドウと、その枠（後ろから前の順。いまのデスクトップの、最小化していないもの）
    func visibleArrangement(on screen: NSScreen) -> [(item: WindowItem, frame: CGRect)] {
        let frames = AXWindow.frames(of: windows)
        let locator = DisplayLocator()
        let key = Self.displayKey(screen)
        return CurrentSpace.frontToBack(among: windows, frames: frames)
            .compactMap { item -> (item: WindowItem, frame: CGRect)? in
                guard let frame = frames[item.id], locator.key(for: frame) == key else { return nil }
                return (item, frame)
            }
            .reversed()
    }

    // MARK: - 保存する・上書きする

    /// そのディスプレイのステージをグループとして保存する（名前がなければ仮の名前）。保存したグループを返す
    @discardableResult
    func saveStageAsGroup(on screen: NSScreen, name: String? = nil) -> StageGroup? {
        guard let content = stageContent(on: screen) else { return nil }
        return editLibrary { $0.addGroup(name: name, content: content) }
    }

    /// 見えている画面を、位置・大きさ・重なりの順番ごとグループとして記録する（ステージも、その組み合わせにする）
    func recordScreenAsGroup(on screen: NSScreen) {
        guard let content = recordedContent(on: screen) else { return }
        editLibrary { $0.addGroup(name: nil, content: content) }
    }

    /// そのディスプレイのいまのステージで、グループの中身・並べ方・ディスプレイを上書きする（名前と並び順はそのまま）
    func overwriteGroup(_ id: UUID, on screen: NSScreen) {
        guard let content = stageContent(on: screen) else { return }
        editLibrary { $0.setContent(content, ofGroup: id) }
    }

    /// 見えている画面で、グループを記録し直す（名前と並び順はそのまま）
    func rerecordGroup(_ id: UUID, on screen: NSScreen) {
        guard library.group(id: id) != nil, let content = recordedContent(on: screen) else { return }
        editLibrary { $0.setContent(content, ofGroup: id) }
    }

    // MARK: - 編集する

    /// グループの編集画面で直したグループを保存する（同じ ID のグループを置き換える）。
    /// 外してメンバーが 1 つ以下になるときは、解消するか確かめる。保存した（解消した）ら true、キャンセルしたら false
    @discardableResult
    func updateGroup(_ group: StageGroup) -> Bool {
        editMembers { $0.updateGroup(group) }
    }

    /// グループの並べ方を変える（右クリックの「並べ方」）。選んだらすぐ、ステージに映す
    /// - そのグループを呼び出したまま、ステージの中身を変えていなければ、その場で並び直す
    /// - そうでなければ、そのグループを、選んだ並べ方で呼び出す
    /// - Parameter fallback: グループにディスプレイを決めていないときに出すディスプレイ（右クリックしたウインドウバーのディスプレイ）
    func setLayout(_ choice: LayoutChoice, ofGroup id: UUID, fallback: NSScreen?) {
        guard var group = library.group(id: id) else { return }
        if group.layout != choice {
            group.layout = choice
            updateGroup(group)
        }
        if lastRecalledGroupID == id, let shown = lastRecalledStage,
           let screen = Self.screen(forKey: shown.screenKey),
           Set(stage(on: screen).selection.members) == shown.windows {
            setLayout(choice, on: screen)
        } else {
            let updated = group
            Task { await recall(updated, fallback: fallback) }
        }
    }

    func renameGroup(_ id: UUID, to name: String) {
        editLibrary { $0.renameGroup(id, to: name) }
    }

    func deleteGroup(_ id: UUID) {
        editLibrary { $0.removeGroup(id) }
    }

    // MARK: - 中身をドラッグで直す（ストリップから）

    /// ウインドウをグループに足す（ウインドウの行をグループの行の上で離した）
    func addWindow(_ item: WindowItem, toGroup id: UUID) {
        guard let signature = item.signature else { return }
        editLibrary { $0.addMember(signature, toGroup: id) }
    }

    /// グループから中身を外す（見本のアイコンを、グループの行の外で離した）。1 つ以下になるなら、解消するか確かめる
    func removeMember(at index: Int, fromGroup id: UUID) {
        editMembers { $0.removeMember(at: index, fromGroup: id) }
    }

    /// 中身をほかのグループへ移す（見本のアイコンを、ほかのグループの行の上で離した）。元のグループが 1 つ以下になるなら、解消するか確かめる
    func moveMember(at index: Int, from source: UUID, to destination: UUID) {
        editMembers { $0.moveMember(at: index, from: source, to: destination) }
    }

    /// 別のデスクトップにいるメンバーを外す（グループの右クリック・分かれた印のメニュー）。1 つ以下になるなら、解消するか確かめる
    func removeStrayMembers(ofGroup id: UUID) {
        guard let group = library.group(id: id) else { return }
        let strays = desktopStatus(of: group).strayIndices
        guard !strays.isEmpty else { return }
        editMembers { $0.removeMembers(at: strays, fromGroup: id) }
    }

    // MARK: - メンバーが 1 つ以下になったら解消する

    /// グループのメンバーを書き換える（外す・移す・編集画面で直す）。メンバーが減って 1 つ以下になるグループがあれば、
    /// 解消するか 1 回だけ確かめる（決まりは PinstageCore の GroupMemberEdit）。
    /// 「解消する」なら、書き換えと解消をまとめて保存する。「キャンセル」なら、どのグループも変えない（一部だけ外す・一部だけ解消する、はしない）
    /// - Returns: 保存した（変わらなかったときも含む）なら true、キャンセルしたら false
    @discardableResult
    func editMembers(_ change: (inout StageLibrary) -> Void) -> Bool {
        var edited = library
        change(&edited)
        let edit = GroupMemberEdit(before: library, edited: edited)
        if edit.needsConfirmation, !confirmDissolution(of: edit.dissolving) { return false }
        editLibrary { $0 = edit.resolved }
        return true
    }

    /// グループを解消してよいか確かめる（設定で確かめないことにしていれば、聞かずに解消する）
    private func confirmDissolution(of groups: [StageGroup]) -> Bool {
        guard confirmsGroupDissolution else { return true }
        let answer = Confirmation.ask(
            title: GroupDissolutionText.title(for: groups),
            message: GroupDissolutionText.message(for: groups),
            action: GroupDissolutionText.action,
            suppression: GroupDissolutionText.suppression
        )
        // チェックを付けて「解消する」を押したら、次からは聞かない（設定の「一般」で戻せる）
        if answer.confirmed, answer.suppressed { confirmsGroupDissolution = false }
        return answer.confirmed
    }

    // MARK: - メンバーのいるデスクトップ

    /// グループを出せるデスクトップの番号ごとの UUID（フルスクリーンのアプリのデスクトップは除く。グループがフルスクリーンへついていかないように）
    private var assignableDesktopUUIDs: [UInt64: String] {
        guard let displays = desktopDisplays else { return desktopUUIDs }
        let fullScreen = Set(displays.flatMap(\.spaces).filter(\.isFullScreen).map(\.id))
        return desktopUUIDs.filter { !fullScreen.contains($0.key) }
    }

    /// 出すデスクトップが決まっているグループごとに、メンバーのいる所を求め直す（読み直したとき・グループを書き換えたとき）
    ///
    /// 当てはめは呼び出しと同じ WindowMatcher（動いているアプリは、見つからなかったメンバーの種類を分けるだけなので渡さない）。
    /// 閉じたものと、× で閉じて隠しただけのものは「分からない」
    func updateGroupDesktopStatuses() {
        let groups = library.groups.filter { $0.desktopID != nil }
        var next: [UUID: GroupDesktopStatus] = [:]
        if !groups.isEmpty {
            // 候補とデスクトップの UUID は、どのグループでも同じなので 1 回だけ作る
            let candidates = windowsWithSignature()
            let signatures = candidates.map(\.signature)
            let uuids = assignableDesktopUUIDs
            for group in groups {
                let members: [MemberDesktop] = WindowMatcher.match(group.members, candidates: signatures, runningBundleIDs: []).map { match in
                    guard let spaces = windowSpaces, let index = match.windowIndex else { return .unknown }
                    let item = candidates[index].item
                    guard !hiddenWindowIDs.contains(item.id) else { return .unknown }
                    return MemberDesktop(spaces: spaces[item.id], desktopUUIDs: uuids)
                }
                next[group.id] = GroupDesktopStatus(desktopID: group.desktopID, members: members)
            }
        }
        if next != groupDesktopStatuses { groupDesktopStatuses = next }
    }

    /// グループのメンバーが、グループを出すデスクトップにどれだけいるか（分かれた印・別のデスクトップのメンバーを外す）。
    /// すべてのデスクトップに出すグループは、いつも分かれていない
    func desktopStatus(of group: StageGroup) -> GroupDesktopStatus {
        groupDesktopStatuses[group.id] ?? GroupDesktopStatus(desktopID: nil, members: [])
    }

    /// デスクトップの UUID から、その名前（「デスクトップ 2」。分からなければ nil）
    func desktopName(forDesktopID desktopID: String) -> String? {
        desktopUUIDs.first { $0.value == desktopID }.flatMap { desktopNames[$0.key]?.title }
    }

    /// グループを出すデスクトップを、メンバーのいる所に合わせる（読み直すたびに呼ぶ）
    ///
    /// 行き先の決まりは PinstageCore の GroupDesktopRule。ほかのデスクトップのウインドウは遅れて見つかるので、
    /// 同じ行き先が続いたときに初めて合わせる（DesktopFollowStabilizer）。合わせた結果は保存する（アプリを閉じても、移した先に残るように）
    func followMemberDesktops() {
        updateGroupDesktopStatuses()
        guard windowSpaces != nil, !desktopUUIDs.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var moves: [(id: UUID, desktopID: String)] = []
        for (id, status) in groupDesktopStatuses {
            let destination = GroupDesktopRule.destination(current: status.desktopID, members: status.members)
            if let next = desktopFollower.observe(id, current: status.desktopID, destination: destination, now: now) {
                moves.append((id, next))
            }
        }
        desktopFollower.prune(keeping: Set(library.groups.map(\.id)))
        guard !moves.isEmpty else { return }
        editLibrary { library in
            for move in moves {
                library.followDesktop(move.desktopID, display: displayID(ofDesktop: move.desktopID), ofGroup: move.id)
            }
        }
    }

    /// そのデスクトップのあるディスプレイの UUID（つながっているディスプレイのものだけ。分からなければ nil）
    private func displayID(ofDesktop desktopID: String) -> String? {
        guard let display = desktopDisplays?.first(where: { $0.spaces.contains { $0.uuid == desktopID } }),
              NSScreen.screen(withDisplayUUID: display.identifier) != nil
        else { return nil }
        return display.identifier
    }

    /// グループの中身の並び順を変える（見本のアイコンを、同じグループのほかのアイコンの上で離した）
    func reorderMember(inGroup id: UUID, from: Int, to: Int, swap: Bool) {
        editLibrary { $0.reorderMember(inGroup: id, from: from, to: to, swap: swap) }
    }

    /// グループを出すデスクトップを変える（右クリックの「出すデスクトップ」）
    /// - Parameter space: 出すデスクトップの番号（nil なら、すべてのデスクトップ）
    func setDesktop(_ space: UInt64?, ofGroup id: UUID) {
        let desktopID = desktopID(of: space)
        // 番号を渡したのに UUID が分からないときは、変えない（すべてのデスクトップになってしまわないように）
        guard space == nil || desktopID != nil else { return }
        editLibrary { $0.setDesktop(desktopID, ofGroup: id) }
    }

    /// そのデスクトップに、グループを出すデスクトップとして決められるか（UUID が分かるか）
    func canAssignGroups(toDesktop space: UInt64?) -> Bool {
        desktopID(of: space) != nil
    }

    /// グループを、そのデスクトップだけに出しているか
    func isGroup(_ group: StageGroup, onlyOnDesktop space: UInt64?) -> Bool {
        guard let desktopID = group.desktopID else { return false }
        return self.desktopID(of: space) == desktopID
    }

    // MARK: - ストリップに並べる

    /// そのディスプレイ・デスクトップのウインドウバーに並べるグループ（ウインドウバーが 1 つのときは、ディスプレイでは分けない）
    /// - Parameter space: ウインドウバーのあるデスクトップの番号（分からなければ nil で、デスクトップでは分けない）
    func groups(on screen: NSScreen, desktop space: UInt64?) -> [StageGroup] {
        let byDisplay: [StageGroup]
        if separatesDisplays {
            let connected = Set(NSScreen.screens.compactMap(\.displayUUID))
            byDisplay = library.groups(forDisplay: screen.displayUUID, connected: connected, isPrimary: screen == NSScreen.primary)
        } else {
            byDisplay = library.groups
        }
        // デスクトップごとに分ける（決まりは PinstageCore の StageGroup.isShown）
        let desktop = desktopID(of: space)
        let known = Set(desktopUUIDs.values)
        return byDisplay.filter { $0.isShown(onDesktop: desktop, knownDesktops: known) }
    }

    /// グループをドラッグで並べ替える（ショートカットの番号も変わる）
    /// index・dropIndex は、そのウインドウバーに並べているグループの番号。
    /// ほかのディスプレイ・デスクトップのグループの並びは崩さない（並び順はショートカットの番号でもある）
    func moveGroup(from index: Int, dropIndex: Int, on screen: NSScreen, desktop space: UInt64?) {
        let visible = groups(on: screen, desktop: space).map(\.id)
        editLibrary { $0.moveGroup(visible: visible, from: index, dropIndex: dropIndex) }
    }

    /// グループを出すディスプレイの名前（ディスプレイが 1 つだけなら出さない）
    func displayName(for group: StageGroup) -> String? {
        guard let id = group.displayID, NSScreen.screens.count > 1 else { return nil }
        return NSScreen.displayName(forDisplayUUID: id)
    }
}
