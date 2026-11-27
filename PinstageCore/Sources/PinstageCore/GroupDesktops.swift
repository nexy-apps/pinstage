import Foundation

// グループを出すデスクトップを、メンバーのいるデスクトップに合わせる決まり
//
// ほかのアプリのウインドウは、いまのデスクトップへ連れてこられないので、グループが使えるのは実際にはメンバーのいるデスクトップだけ。
// そこで、メンバーを別のデスクトップへ移したら、グループもついていくようにする。

/// グループのメンバー（に当てはまったウインドウ）のいる所
public enum MemberDesktop: Hashable, Sendable {
    /// そのデスクトップ（デスクトップの UUID）
    case desktop(String)
    /// すべてのデスクトップに割り当てたウインドウ（どこにでもいるので、行き先の数には入れない）
    case allDesktops
    /// ウインドウが開いていない・いる所が分からない（数えない）
    case unknown

    /// ウインドウのあるデスクトップから決める
    /// - Parameters:
    ///   - spaces: ウインドウのあるデスクトップの番号（分からなければ nil）
    ///   - desktopUUIDs: グループを出せるデスクトップの番号ごとの UUID（フルスクリーンのアプリのデスクトップは入れない）
    public init(spaces: Set<UInt64>?, desktopUUIDs: [UInt64: String]) {
        guard let spaces, !spaces.isEmpty else {
            self = .unknown
            return
        }
        if WindowSpaces.isOnAllDesktops(spaces) {
            self = .allDesktops
        } else if let uuid = spaces.first.flatMap({ desktopUUIDs[$0] }) {
            self = .desktop(uuid)
        } else {
            self = .unknown
        }
    }

    /// いるデスクトップの UUID（すべて・分からないときは nil）
    public var desktopID: String? {
        if case .desktop(let id) = self { id } else { nil }
    }
}

/// グループのメンバーが、グループを出すデスクトップにどれだけいるか（分かれたときの印・外すメンバー）
public struct GroupDesktopStatus: Equatable, Sendable {
    /// グループを出すデスクトップ（nil なら、すべてのデスクトップ）
    public let desktopID: String?
    /// メンバーごとのいる所（グループの並び順）
    public let members: [MemberDesktop]

    public init(desktopID: String?, members: [MemberDesktop]) {
        self.desktopID = desktopID
        self.members = members
    }

    /// 出すデスクトップと別のデスクトップにいるメンバーの番号（すべてのデスクトップに出すグループでは、いつも空）
    public var strayIndices: [Int] {
        guard let desktopID else { return [] }
        return members.indices.filter { index in
            guard let id = members[index].desktopID else { return false }
            return id != desktopID
        }
    }

    /// 数えたメンバーの数（閉じている・いる所が分からないものは入れない）
    public var countedCount: Int {
        members.filter { $0 != .unknown }.count
    }

    /// 出すデスクトップにいるメンバーの数（すべてのデスクトップに割り当てたものも「いる」に入れる）
    public var presentCount: Int {
        countedCount - strayIndices.count
    }

    /// 分かれているか（出すデスクトップにいないメンバーがいる）
    public var isSplit: Bool {
        !strayIndices.isEmpty
    }

    /// グループの行に出す印（「1/2」。分かれていなければ nil）
    public var badge: String? {
        isSplit ? "\(presentCount)/\(countedCount)" : nil
    }
}

/// グループを出すデスクトップの決まり
public enum GroupDesktopRule {
    /// メンバーのいる所から、グループを出すデスクトップを決める
    ///
    /// - すべてのデスクトップに出すグループ（current が nil）: いつもすべて（合わせない）
    /// - メンバーが 1 つのデスクトップに集まっている: そのデスクトップ
    /// - 複数のデスクトップに分かれた: いちばん多くいるデスクトップ。同じ数なら、いま覚えているデスクトップのまま
    ///   （その中になければ、先に並んだメンバーのいる所）
    /// - 1 つも開いていない・いる所が分からない: いま覚えているデスクトップのまま
    /// - すべてのデスクトップに割り当てたウインドウは、どこにでもいるので数に入れない
    /// - Parameters:
    ///   - current: いま覚えているデスクトップ
    ///   - members: メンバーごとのいる所
    public static func destination(current: String?, members: [MemberDesktop]) -> String? {
        guard let current else { return nil }
        let desktops = members.compactMap(\.desktopID)
        var counts: [String: Int] = [:]
        for id in desktops { counts[id, default: 0] += 1 }
        guard let most = counts.values.max() else { return current }
        if counts[current] == most { return current }
        // 先に並んだメンバーのいる所から選ぶ
        return desktops.first { counts[$0] == most } ?? current
    }
}

/// 行き先が落ち着いてから、グループを出すデスクトップを合わせる
///
/// ほかのデスクトップのウインドウは少し遅れて見つかる（起動した直後・デスクトップを切り替えた直後）。
/// 途中の一覧で決めて保存すると行ったり来たりするので、同じ行き先が決まった回数・決まった時間続いたときに初めて合わせる。
public struct DesktopFollowStabilizer<Key: Hashable & Sendable>: Sendable {
    /// 同じ行き先が続く読み直しの回数
    public let requiredReadings: Int
    /// 同じ行き先が続く時間（秒）。読み直しが立て続けに起きたとき（ほかのデスクトップのウインドウを見つけた直後など）に、すぐ決めないように
    public let minimumDuration: TimeInterval

    private struct Pending: Sendable {
        var destination: String
        var readings: Int
        var since: TimeInterval
    }

    private var pending: [Key: Pending] = [:]

    public init(requiredReadings: Int = 3, minimumDuration: TimeInterval = 2) {
        self.requiredReadings = requiredReadings
        self.minimumDuration = minimumDuration
    }

    /// 読み直すたびに、グループごとに渡す。合わせてよい行き先を返す（まだ合わせないなら nil）
    /// - Parameters:
    ///   - key: グループ
    ///   - current: いま覚えているデスクトップ
    ///   - destination: この読み直しで決めた行き先（GroupDesktopRule.destination）
    ///   - now: いまの時刻（秒）
    public mutating func observe(_ key: Key, current: String?, destination: String?, now: TimeInterval) -> String? {
        guard let destination, destination != current else {
            // 行き先がいまのままなら、数え直す
            pending[key] = nil
            return nil
        }
        var next = Pending(destination: destination, readings: 1, since: now)
        if let previous = pending[key], previous.destination == destination {
            next = previous
            next.readings += 1
        }
        guard next.readings >= requiredReadings, now - next.since >= minimumDuration else {
            pending[key] = next
            return nil
        }
        pending[key] = nil
        return destination
    }

    /// 数えている途中のものを、すべて数え直す（デスクトップを切り替えた直後など、一覧が揃うまで待つとき）
    public mutating func reset() {
        pending.removeAll()
    }

    /// なくなったグループの数えている途中のものを捨てる
    public mutating func prune(keeping keys: Set<Key>) {
        pending = pending.filter { keys.contains($0.key) }
    }
}

extension StageLibrary {
    /// グループを、メンバーのいるデスクトップへ移す（ついていく）。移したら true
    ///
    /// 行き先のデスクトップが別のディスプレイのものなら、出すディスプレイも合わせる
    /// （ディスプレイを決めていないグループは、どのディスプレイにも並ぶので、そのまま）。
    /// - Parameters:
    ///   - desktopID: 行き先のデスクトップ
    ///   - displayID: 行き先のデスクトップのあるディスプレイ（分からなければ nil で、ディスプレイは変えない）
    @discardableResult
    public mutating func followDesktop(_ desktopID: String, display displayID: String?, ofGroup id: UUID) -> Bool {
        guard let index = groupIndex(id: id), groups[index].desktopID != nil else { return false }
        var group = groups[index]
        group.desktopID = desktopID
        if let displayID, group.displayID != nil {
            group.displayID = displayID
        }
        guard group != groups[index] else { return false }
        groups[index] = group
        return true
    }

    /// グループから、いくつかのメンバーをまとめて外す（番号は外す前のもの。ない番号は飛ばす）。外した数を返す
    @discardableResult
    public mutating func removeMembers(at memberIndices: [Int], fromGroup id: UUID) -> Int {
        guard let index = groupIndex(id: id) else { return 0 }
        let valid = Set(memberIndices).filter { groups[index].members.indices.contains($0) }
        for memberIndex in valid.sorted(by: >) {
            groups[index].members.remove(at: memberIndex)
        }
        return valid.count
    }
}
