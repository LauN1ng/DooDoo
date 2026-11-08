import Foundation

/// 一张卡面的品牌样式。
///
/// 数据来自 `assets/brands/brands.json`（16 个品牌），**不在数据库里存颜色**——
/// 换色只改这一处，账户只记 `brandId`。
struct BrandStyle: Sendable, Equatable {
    let id: String
    let name: String
    let short: String
    let c1: UInt32
    let c2: UInt32
    let ink: UInt32
    let texture: String
    let network: String

    /// 相对亮度，只用来决定后层卡该压暗还是提亮（深色卡再压暗会和投影糊成一条）。
    var luminance: Double {
        let r = Double((c1 >> 16) & 0xFF) / 255
        let g = Double((c1 >> 8) & 0xFF) / 255
        let b = Double(c1 & 0xFF) / 255
        return r * 0.299 + g * 0.587 + b * 0.114
    }
}

enum BrandPalette {
    static let all: [String: BrandStyle] = {
        let list: [BrandStyle] = [
            .init(id: "cmb", name: "招商银行", short: "招行", c1: 0xE03A45, c2: 0x8B0009, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY"),
            .init(id: "ccb", name: "建设银行", short: "建行", c1: 0x2E8FD8, c2: 0x004A86, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY"),
            .init(id: "bosc", name: "上海银行", short: "上行", c1: 0x1A6FB5, c2: 0x00355F, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY"),
            .init(id: "cmcc", name: "中移金科", short: "中移金科", c1: 0x2FA6E0, c2: 0x005C88, ink: 0xFFFFFF, texture: "matte", network: "INSTALLMENT"),
            .init(id: "alipay", name: "支付宝", short: "支付宝", c1: 0x4B9BFF, c2: 0x0A4FB5, ink: 0xFFFFFF, texture: "matte", network: "WALLET"),
            .init(id: "yuebao", name: "余额宝", short: "余额宝", c1: 0x3FC8E0, c2: 0x0A6FA8, ink: 0xFFFFFF, texture: "matte", network: "WALLET"),
            .init(id: "huabei", name: "花呗", short: "花呗", c1: 0x6B7BFF, c2: 0x2233A8, ink: 0xFFFFFF, texture: "matte", network: "CREDIT"),
            .init(id: "wechat", name: "微信支付", short: "微信", c1: 0x34D57E, c2: 0x04733B, ink: 0xFFFFFF, texture: "matte", network: "WALLET"),
            .init(id: "jd", name: "京东", short: "京东", c1: 0xFF5147, c2: 0x9E0D06, ink: 0xFFFFFF, texture: "matte", network: "WALLET"),
            .init(id: "baitiao", name: "京东白条", short: "白条", c1: 0xFF6A5E, c2: 0xA81208, ink: 0xFFFFFF, texture: "matte", network: "CREDIT"),
            .init(id: "jdgold", name: "京东小金库", short: "小金库", c1: 0xE8A93D, c2: 0x8F5A07, ink: 0xFFFFFF, texture: "metal", network: "WALLET"),
            .init(id: "douyin", name: "抖音", short: "抖音", c1: 0x3A3F52, c2: 0x0A0C14, ink: 0xFFFFFF, texture: "matte", network: "CREDIT"),
            .init(id: "douyinloan", name: "抖音放心借", short: "放心借", c1: 0xFF3D63, c2: 0x8C0A22, ink: 0xFFFFFF, texture: "metal", network: "INSTALLMENT"),
            .init(id: "ezhaodai", name: "招行 e招贷", short: "e招贷", c1: 0xE5565E, c2: 0x7E0006, ink: 0xFFFFFF, texture: "metal", network: "INSTALLMENT"),
            .init(id: "loan-personal", name: "个人借款", short: "借款", c1: 0xA8846A, c2: 0x4E3627, ink: 0xFFF6EC, texture: "matte", network: "NONE"),
            .init(id: "cash", name: "现金", short: "现金", c1: 0x9AA88F, c2: 0x3E4A38, ink: 0xFFFFFF, texture: "matte", network: "NONE"),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    /// 找不到就用现金那套，绝不返回 nil。
    static func style(_ id: String) -> BrandStyle {
        all[id] ?? all["cash"]!
    }

    /// 供 Picker 用的稳定顺序：按名字，现金放最后。
    static let sortedIds: [String] = all.keys.sorted { lhs, rhs in
        if lhs == "cash" { return false }
        if rhs == "cash" { return true }
        let l = all[lhs]?.name ?? ""
        let r = all[rhs]?.name ?? ""
        return l < r
    }

    /// 新建某类账户时的默认品牌。
    static func defaultId(for kind: AccountKind) -> String {
        switch kind {
        case .savings: "ccb"
        case .cash: "cash"
        case .credit: "cmb"
        case .loan: "loan-personal"
        }
    }
}
