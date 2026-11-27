import Foundation

/// グループのメンバーを書き換えたとき、1 つ以下になるグループを解消する決まり
///
/// グループは 2 つ以上のウインドウを並べるためのものなので、メンバーを外して 1 つ以下になったら、グループを解消する
/// （ウインドウには何もしない）。外し方は問わない（見本のアイコンをドラッグで外す・ほかのグループへ移す・
/// 別のデスクトップのメンバーを外す・編集画面で外す）。
///
/// グループはウインドウを抱え込まないので、同じウインドウが複数のグループに入っていることがある。
/// 1 回の操作で複数のグループが 1 つ以下になるときも、確かめるのは 1 回だけで、まとめて解消するか、どれも変えないかのどちらか。
public struct GroupMemberEdit: Sendable {
    /// 解消するグループ（書き換えたあとの中身。並び順は全体のまま）
    public let dissolving: [StageGroup]
    /// 「解消する」を選んだときに保存する中身（解消するグループを除く。メンバーが減るだけのグループは、減ったまま）。
    /// 「キャンセル」なら、呼ぶ側は何も保存しない
    public let resolved: StageLibrary

    /// - Parameters:
    ///   - before: 書き換える前
    ///   - edited: 1 回の操作で書き換えたあと（解消するかどうかは、ここで決める）
    public init(before: StageLibrary, edited: StageLibrary) {
        dissolving = Self.dissolvingGroups(before: before, after: edited)
        let ids = Set(dissolving.map(\.id))
        var library = edited
        library.groups.removeAll { ids.contains($0.id) }
        resolved = library
    }

    /// 確かめてから保存するか（解消するグループがあるか）
    public var needsConfirmation: Bool {
        !dissolving.isEmpty
    }

    /// メンバーが減って 1 つ以下になったグループ
    ///
    /// もともと 1 つ以下のグループでも、減ったら解消する（最後の 1 つを外したとき）。
    /// 減っていないグループ（並べ替え・並べ方だけを変えた・1 つだけで保存したもの）や、この操作で足した・消したグループは解消しない。
    static func dissolvingGroups(before: StageLibrary, after: StageLibrary) -> [StageGroup] {
        let previousCounts = Dictionary(before.groups.map { ($0.id, $0.members.count) }, uniquingKeysWith: { first, _ in first })
        return after.groups.filter { group in
            guard let previous = previousCounts[group.id] else { return false }
            return group.members.count <= 1 && group.members.count < previous
        }
    }
}

/// グループを解消する前の確かめの文
public enum GroupDissolutionText {
    /// 名前を並べる数の上限（多いときは、残りを「ほか 2 つ」にする）
    public static let nameLimit = 5

    /// 題名（1 つ:「グループ「作業」を解消しますか？」。2 つ以上:「3 つのグループを解消しますか？」）
    public static func title(for groups: [StageGroup]) -> String {
        if groups.count == 1 {
            return "グループ「\(groups[0].name)」を解消しますか？"
        }
        return "\(groups.count) つのグループを解消しますか？"
    }

    /// 説明（2 つ以上のときは、解消するグループの名前を並べる）
    public static func message(for groups: [StageGroup]) -> String {
        if groups.count <= 1 {
            return "外すと、グループのウインドウが 1 つ以下になるので、グループを解消します。ウインドウは閉じません。"
        }
        return "外すと、次のグループのウインドウが 1 つ以下になるので、グループを解消します。ウインドウは閉じません。\n\n" + names(groups)
    }

    /// グループの名前の並び（「「作業」「調べもの」ほか 2 つ」）
    public static func names(_ groups: [StageGroup]) -> String {
        let shown = groups.prefix(nameLimit).map { "「\($0.name)」" }.joined()
        let rest = groups.count - nameLimit
        return rest > 0 ? "\(shown)ほか \(rest) つ" : shown
    }

    /// 確かめのダイアログのボタン
    public static let action = "解消する"
    /// 「次回からこの確認を出さない」のチェック
    public static let suppression = "次回からこの確認を出さない"
}

/// グループを解消する前に確かめるか（設定。既定はオン）
public enum GroupDissolutionSetting {
    static let key = "groups.confirmsDissolution"

    public static func confirms(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public static func save(_ confirms: Bool, to defaults: UserDefaults) {
        defaults.set(confirms, forKey: key)
    }
}
