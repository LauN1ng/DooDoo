import SwiftUI

/// 账户详情页三种形态（信用 / 借款 / 储蓄）共用的四块。
///
/// **为什么抽出来**：2026-11-16 用户反馈三条——
/// ① 储蓄账户点进去直接弹的是编辑表单，「详情页还没做」；
/// ② 亲友借款详情页还在显示往期账单、分期、流水，「这是不需要的」；
/// ③ 详情页顶部卡片右边那串「招商 / 信用卡」要去掉，卡片居中。
///
/// 根因是 `AccountDetailView` 只有一套信用卡区块，对所有 `AccountKind` 都渲染同一份。
/// 现在按类型分发内容，但**卡面 / 大字金额 / 走势 / 流水**这四块三种页面都要，
/// 必须一份实现——复制三遍，以后改一次要改三处，三处必然走偏。

// MARK: - 顶部卡面（居中独占一行）

/// 详情页顶部的卡面 hero。
///
/// **不写账户名、不写类型**：卡面自己已经画了「招商银行 / 信用卡」。
/// 原先右边那一栏是本文件的删除对象（用户 2026-11-16 第 3 条）。
///
/// `cardSpace` 是浮层明细行卡面与这块卡面共用的命名空间：点行时同一个 id 从
/// 144×96 长到 240×151（用户原话「卡片逐渐放大」），中间不换视图、不闪。
struct DetailHeroCard<Accessory: View>: View {
    let account: Account
    let cardSpace: Namespace.ID
    let accessory: Accessory

    /// 没有附带内容（逾期提示只在真有逾期时才出现）。
    init(account: Account, cardSpace: Namespace.ID) where Accessory == EmptyView {
        self.account = account
        self.cardSpace = cardSpace
        self.accessory = EmptyView()
    }

    init(account: Account, cardSpace: Namespace.ID, @ViewBuilder accessory: () -> Accessory) {
        self.account = account
        self.cardSpace = cardSpace
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 9) {
            CardFace(account: account, size: .hero)
                .matchedGeometryEffect(id: account.persistentModelID, in: cardSpace)
                // 卡面自带一层 3.5pt 近影；240pt 宽的卡浮在 #F6F6F6 上还需要一层远影托底，
                // 否则看起来像贴纸贴在页面上。
                .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 8)

            accessory
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

/// 逾期提示（规格第四节：只在详情页顶部红字出现，不做横幅、不做通知）。
struct DetailOverdueBadge: View {
    let days: Int

    var body: some View {
        Text("逾期 \(days) 天")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Palette.overdraft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(Palette.overdraftBed))
    }
}

// MARK: - 大字金额

/// 借款页的「欠款」、储蓄页的「余额」——一个账户只有一个主角数字时用它。
///
/// 信用页**不用**这个：那张页的金额已经拆进三列（欠款 / 本期消费 / 本月分期），
/// 再立一个大数就变成第四个数字。
struct DetailHeroAmount: View {
    let caption: String
    let amount: Decimal
    var note: String?
    var tone: Color = Palette.ink

    var body: some View {
        VStack(spacing: 5) {
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.sub)

            Text(MoneyMath.money(amount))
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

// MARK: - 走势

/// 走势区块（规格第四节）。**信用页画欠款，储蓄页画余额，借款页也画欠款**。
///
/// 区间切换的 `range` 由调用方持有：切换后要按新区间重算 `points`，
/// 状态藏在组件里会让外面拿不到新数据。
struct DetailTrendBlock: View {
    let title: String
    /// 图注。**必须解释曲线和顶部数字为什么可能不等**，否则用户会以为是算错了。
    let caption: String
    let points: [DebtTrendPoint]
    @Binding var range: NetWorthRange
    /// 曲线主色：储蓄绿 / 信用与借款红（2026-11-18 D 方案）。
    var tone: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Spacer(minLength: 8)

                rangePicker
            }

            if points.isEmpty {
                DetailEmptyRow(text: "流水还不够画出一条线")
            } else {
                DebtTrendChart(points: points, tone: tone)
            }

            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(NetWorthRange.allCases) { item in
                Button {
                    range = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(range == item ? Palette.ink : Palette.sub)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(range == item ? Palette.pillOn : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.tabBed))
    }
}

// MARK: - 流水

enum FlowScope: String, CaseIterable, Identifiable {
    case month = "本月"
    case all = "全部"
    var id: String { rawValue }
}

/// 流水区块（规格第七节）。
struct DetailFlowBlock: View {
    /// 该账户视角的全部流水（含转入），由调用方合并两个关系后传入。
    let transactions: [Transaction]
    let footnote: String
    let emptyMonthText: String
    let emptyAllText: String

    @State private var scope: FlowScope = .month

    private var shown: [Transaction] {
        let sorted = transactions
            .filter { $0.deletedAt == nil }
            .sorted { $0.date > $1.date }
        guard scope == .month else { return sorted }
        let calendar = Calendar.current
        return sorted.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    /// 汇总行只是列表摘要，不参与任何账务计算。
    /// 「支出」只数 `.expense`——转账、还款、借款入账都不是花掉的钱，
    /// 把它们算进支出会让同一个月的消费看起来比首页日卡多一截。
    private var summary: String {
        let list = shown
        guard scope == .month else { return "共 \(list.count) 笔" }
        let spend = list
            .filter { $0.kind == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return "\(list.count) 笔 · 支出 \(MoneyMath.money(spend))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("流水")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Text(summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.sub)

                Spacer(minLength: 8)

                scopePicker
            }

            if shown.isEmpty {
                DetailEmptyRow(text: scope == .month ? emptyMonthText : emptyAllText)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { tx in
                        TxRowView(transaction: tx)
                        if tx.id != shown.last?.id {
                            Divider().overlay(Palette.line)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.card)
                )
            }

            Text(footnote)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.faint)
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 2) {
            ForEach(FlowScope.allCases) { item in
                Button {
                    scope = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(scope == item ? Palette.ink : Palette.sub)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(scope == item ? Palette.pillOn : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.tabBed))
    }
}

// MARK: - 空态

/// 区块空态的统一卡片。原先 `AccountDetailView` 里有一份私有 `emptyRow`，
/// 抽出后三个页面共用一张。
struct DetailEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Palette.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.card)
            )
    }
}
