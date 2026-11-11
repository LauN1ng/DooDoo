import Foundation

/// 首页列表的**显示行**：转账本体 + 它的手续费合成一行（2026-11-11 用户定）。
///
/// 数据层仍然是两条流水——`LedgerService.insert` 把转账按等额记（转出 = 到账），
/// 手续费另生成一条 `.expense`，两者共用一个 `groupID`。余额必须这么算：
/// 到账额 + 手续费 = 用户填的转出总额，少记一条，付款账户就会永久多出那点钱。
///
/// 但**列表上手续费不该单独占一行**：它是转账的附属信息，不是一次独立消费。
/// 于是多了这一层「行」的抽象——模型不动、余额不动、合计口径不动，
/// 只是把两条渲染成一行（金额列显示转出总额，手续费收成标题下的一枚小标签）。
///
/// 为什么放在 `Math/` 而不是视图里：合并规则要能被单测钉住。
/// 「手续费被重复渲染」「孤儿手续费被吞掉」一旦发生，
/// 用户拿列表核对余额时就会永远差一点钱（真机反馈 #13 的老症状）。
///
/// 为什么外层是**不带泛型**的 `enum`、行类型是嵌套的 `Row<Item>`：
/// 泛型类型上的静态方法必须在调用点显式写出泛型参数（`TxRollup<Item>.rows(...)`），
/// 而 `extension` 里不带参数的 `TxRollup` 又会解析成 `Self`（即 `TxRollup<Item>`）。
/// 两处坑都踩过一遍——CI run `42972534278` 与 `42973243155` 各炸一次。
/// 让命名空间本身不带泛型、只有「行」带，这两个坑就不存在了。
enum TxRollup {
    /// 一行显示数据：主行 + 挂在它上面的手续费。
    struct Row<Item> {
        /// 主行。通常是一笔转账；没有手续费时也可能是任意一笔流水。
        let primary: Item

        /// 挂在这一行上的手续费流水（同 `groupID` 的 `.expense`）。无手续费时为空。
        let fees: [Item]

        init(primary: Item, fees: [Item] = []) {
            self.primary = primary
            self.fees = fees
        }
    }

    /// 把一批流水压成显示行，顺序跟随 `items` 里**主行**的位置（调用方已按时间倒序）。
    ///
    /// 规则：
    /// - `.transfer` 作主行，同 `groupID` 的 `.expense` 挂上去，不再单独出行；
    /// - 找不到对应转账的手续费流水（跨窗口边界、历史脏数据）**原样保留成一行**——
    ///   宁可多一行，也不能把一笔真实扣款藏起来；
    /// - 其余流水一行一条，`fees` 为空。
    ///
    /// 边界：空数组返回空数组；`groupOf` 为 `nil` 的流水不参与合并。
    static func rows<T>(
        _ items: [T],
        kindOf: (T) -> TransactionKind,
        groupOf: (T) -> String?
    ) -> [Row<T>] {
        // 先认清哪些 groupID 里真有转账：只有这些组里的 `.expense` 才算「手续费」。
        var transferGroups: Set<String> = []
        for item in items where kindOf(item) == .transfer {
            if let group = groupOf(item) { transferGroups.insert(group) }
        }
        guard !transferGroups.isEmpty else {
            return items.map { Row<T>(primary: $0) }
        }

        // 再按 groupID 收手续费，最后走一遍正文——这样主行顺序不会被打乱。
        var feesByGroup: [String: [T]] = [:]
        for item in items where kindOf(item) == .expense {
            guard let group = groupOf(item), transferGroups.contains(group) else { continue }
            feesByGroup[group, default: []].append(item)
        }

        var rows: [Row<T>] = []
        rows.reserveCapacity(items.count)
        for item in items {
            let group = groupOf(item)
            switch kindOf(item) {
            case .expense:
                // 已挂到同组转账那一行，不再单独出行。
                if let group, transferGroups.contains(group) { continue }
                rows.append(Row<T>(primary: item))
            case .transfer:
                rows.append(Row<T>(primary: item, fees: group.flatMap { feesByGroup[$0] } ?? []))
            case .income, .repayment, .adjustment:
                rows.append(Row<T>(primary: item))
            }
        }
        return rows
    }
}
