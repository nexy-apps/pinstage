import Foundation

// ウインドウスイッチャーのドラッグ＆ドロップの決まり（ステージへ入れる・グループに足す）
//
// ほかのアプリのウインドウは、いまのデスクトップへ連れてこられないので、運べるのはいまのデスクトップのウインドウだけ
// （スペースの印と同じ）。別のデスクトップの欄へ落としてウインドウを移す操作は作らない。

/// スイッチャーで、ウインドウを落とせる先
public enum WindowSwitcherDropTarget: Hashable, Sendable {
    /// ステージ（開いたディスプレイのステージに入れて、スイッチャーを閉じる）
    case stage
    /// 保存したグループ（足す。スイッチャーは閉じない）
    case group(UUID)
}

/// どのウインドウをつかめるか・運ぶウインドウの組み合わせ
///
/// 「すべてのデスクトップ」に割り当てたウインドウは、デスクトップ別の表示ではすべての欄に出るが、ウインドウは 1 つなので、
/// どの欄からつかんでも同じウインドウとして扱う（欄ではなくウインドウで見分ける。印を 2 つの欄で付けても 1 つと数える）。
public struct WindowSwitcherDragRules<Window: Hashable> {
    /// いまのデスクトップのウインドウ（すべてのデスクトップに割り当てたもの・しまってあるものも入る。どのディスプレイの、いまのデスクトップでもよい）
    public let currentDesktop: Set<Window>

    public init(currentDesktop: Set<Window>) {
        self.currentDesktop = currentDesktop
    }

    /// ドラッグを始められるか・スペースで印を付けられるか（ほかのデスクトップのウインドウはできない）
    public func canCarry(_ window: Window) -> Bool {
        currentDesktop.contains(window)
    }

    /// つかんだときに運ぶウインドウ（運ぶ順。つかめないときは空）
    ///
    /// - 印の付いたウインドウをつかんだ: 印の付いたものをまとめて運ぶ（印を付けた順。Finder と同じ）
    /// - 印のないウインドウをつかんだ: それだけを運ぶ
    /// - Parameters:
    ///   - grabbing: つかんだウインドウ
    ///   - marked: スペースで印を付けたウインドウ（付けた順）
    public func carried(grabbing: Window, marked: [Window]) -> [Window] {
        guard canCarry(grabbing) else { return [] }
        guard marked.contains(grabbing) else { return [grabbing] }
        var seen = Set<Window>()
        return marked.filter { canCarry($0) && seen.insert($0).inserted }
    }
}

/// 落としたときの決まり
public enum WindowSwitcherDrop {
    /// 落とせる先か（光らせるか）
    ///
    /// - ステージ: 運んでいるものがあれば落とせる
    /// - グループ: グループに入れられるもの（アプリの識別名が分かるもの）があれば落とせる（もう入っていても光らせる。足すものがなければ何も変わらない）
    /// - 何もない所・ほかのデスクトップの欄（落とす先が nil）: 落とせない
    /// - Parameters:
    ///   - target: ポインタの下の落とす先
    ///   - carried: 運んでいるウインドウの手がかり（グループに入れられないものは nil）
    public static func accepts(_ target: WindowSwitcherDropTarget?, carried: [WindowSignature?]) -> Bool {
        switch target {
        case .stage: !carried.isEmpty
        case .group: carried.contains { $0 != nil }
        case nil: false
        }
    }
}
