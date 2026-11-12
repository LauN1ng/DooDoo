import SwiftUI
import SwiftData

/// 整屏磨砂明细浮层（规格 4.x / 6.1）。
///
/// **不是 sheet**：无圆角、无把手、不从底部位移，只淡入；底下的资产页不重建、不位移。
struct GroupOverlay: View {
    let title: String
    let accounts: [Account]
    let isLiability: Bool
    /// 账户 → 逾期天数。有值的那个把「较上月」换成「逾期 N 天」——
    /// 「较上月」现在是写死的 `—`（环比还没做），拿它换真数据比多塞一列干净。
    var overdueDays: [PersistentIdentifier: Int] = [:]
    /// 账户 → 欠多少（正数）。与资产页组头合计、顶部「我欠」同一个口径（`CardDebt`）。
    /// **不能直接显示 `currentBalance`**：那是流水派生的，信用卡没记消费流水时永远是 0，
    /// 而账单一期期都在那儿——同一个屏上两个数会互相打脸。
    var oweByAccount: [PersistentIdentifier: Decimal] = [:]
    let onClose: () -> Void
    let onSelect: (Account) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // material 必须挂在 Color.clear 的 background 上，才能糊到身后的兄弟视图
            Color.clear
                .background(.ultraThinMaterial)
                .overlay(Color(hex: 0xF7F5F1).opacity(0.42))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Color.clear.frame(height: 92)
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(accounts) { account in
                            row(account)
                        }
                        Text("点任一账户进入详情")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.sub)
                            .padding(.top, 18)
                            .padding(.bottom, 34)
                    }
                    .padding(.horizontal, 16)
                }
                // 底部渐隐：最后一行不要被屏幕圆角切一刀
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            closeButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 53)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)账户列表，共 \(accounts.count) 个")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink2)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.ink.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }

    /// 浮层里显示的「欠款」。负债卡走 `CardDebt` 派生值，取负号与 `currentBalance`
    /// 的正负约定保持一致（欠款显示为 −x,xxx.xx）。
    ///
    /// 派生值为 0 时退回余额——那种情况说明这张卡既没账单也没分期，
    /// 余额是多少就该显示多少（可能为正，多还了钱）。
    private func displayedBalance(of account: Account) -> Decimal {
        guard isLiability else { return account.currentBalance }
        let owed = oweByAccount[account.persistentModelID] ?? 0
        return owed > 0 ? -owed : account.currentBalance
    }

    private func row(_ account: Account) -> some View {
        let overdue = overdueDays[account.persistentModelID]

        return Button {
            onSelect(account)
        } label: {
            HStack(spacing: 13) {
                CardFace(account: account, large: true)

                HStack(spacing: 8) {
                    field(
                        title: isLiability ? "欠款" : "余额",
                        value: MoneyMath.money(displayedBalance(of: account)),
                        tone: isLiability ? Palette.expense : Palette.ink
                    )
                    if let overdue {
                        field(
                            title: "逾期",
                            value: "\(overdue) 天",
                            tone: Palette.expense
                        )
                    } else {
                        field(
                            title: "较上月",
                            value: "—",
                            tone: Palette.sub
                        )
                    }
                }
            }
            .frame(height: 116)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func field(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8.5))
                .tracking(0.6)
                .foregroundStyle(Palette.faint)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
