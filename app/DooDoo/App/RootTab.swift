import Foundation

/// 顶部三段 tab（PRD v2.2 第七节）。
///
/// 只有三个：流水 / 资产 / 设置。**没有「还款」**——本月要还与逾期挂在资产页信用组里。
enum RootTab: String, CaseIterable, Identifiable {
    case flow
    case assets
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flow: "流水"
        case .assets: "资产"
        case .settings: "设置"
        }
    }

    /// SF Symbols，17pt 线性。与 `首页规格冻结-v1.0.md` 2.2 的图标语义对应：
    /// 列表三横 / 钱包 / 齿轮。
    var icon: String {
        switch self {
        case .flow: "list.bullet"
        case .assets: "creditcard"
        case .settings: "gearshape"
        }
    }
}
