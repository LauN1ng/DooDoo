import Foundation

/// 一张卡面的品牌样式。
///
/// 数据来自 `assets/brands/brands.json`（**v1.3，21 个品牌**），**不在数据库里存颜色**——
/// 换色只改这一处，账户只记 `brandId` + `variant`。
///
/// 与 M2a 那版的差别（2026-11-09 换资源）：
/// - 色值从「近似取色」换成各行官网 CSS + logo 像素实测色（招行 `#A30030`、建行 `#0066B3`…）。
/// - 补齐 5 家大行（工行 / 农行 / 中行 / 交行 / 邮储）。
/// - 新增 `chip` / `logo`：决定卡面底图里画不画金属芯片、用哪枚白色单色行徽。
///
/// `c2` 一律是 `c1` 同色系压暗，不是独立取色；`variant` 的色阶偏移固化在资源文件里
/// （`_build/gen-card-faces.js` 生成 21×3 张底图），运行时不再算颜色。
struct BrandStyle: Sendable, Equatable {
    let id: String
    let name: String
    let short: String
    /// 卡面左下角的大字（`CMB` / `ALIPAY`），设计稿里比中文名更显眼。
    let en: String
    let c1: UInt32
    let c2: UInt32
    let ink: UInt32
    let texture: String
    let network: String
    /// 只有实体银行卡为 true（芯片左上 + 行徽右上）；钱包 / 虚拟信用 / 分期贷 / 现金为 false。
    let chip: Bool
    /// 白色单色行徽的 id，对应 `assets/brands/logos/logo-<logo>.svg`；无行徽降级为文字标。
    let logo: String?

    /// 相对亮度，只用来决定后层卡该压暗还是提亮（深色卡再压暗会和投影糊成一条）。
    var luminance: Double {
        let r = Double((c1 >> 16) & 0xFF) / 255
        let g = Double((c1 >> 8) & 0xFF) / 255
        let b = Double(c1 & 0xFF) / 255
        return r * 0.299 + g * 0.587 + b * 0.114
    }

    /// 卡面底图在 Asset Catalog 里的名字，如 `CardCmbV1`。
    ///
    /// `variant` 只认 0/1/2（原色 / 压暗 / 提亮），超出范围回落到原色——
    /// 资源是 21×3 张，不能为脏数据再补图。
    func cardAsset(variant: Int) -> String {
        let v = (0...2).contains(variant) ? variant : 0
        let stem = id
            .split(separator: "-")
            // `prefix(1)` 返回 Substring，不能直接和 String 相加
            .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
            .joined()
        return "Card" + stem + "V" + String(v)
    }
}

enum BrandPalette {
    /// 与 `assets/brands/brands.json` 逐条对应，改色必须两边一起改（`verify-assets.js` 会校验）。
    static let all: [String: BrandStyle] = {
        let list: [BrandStyle] = [
            // 六大行 + 股份行：全部实体卡，有芯片 + 行徽右上
            .init(id: "icbc", name: "中国工商银行", short: "工行", en: "ICBC",
                  c1: 0xC7000A, c2: 0x6E0006, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "icbc"),
            .init(id: "abc", name: "中国农业银行", short: "农行", en: "ABC",
                  c1: 0x319C8B, c2: 0x18564D, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "abc"),
            .init(id: "boc", name: "中国银行", short: "中行", en: "BOC",
                  c1: 0xA71E32, c2: 0x5A101B, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "boc"),
            .init(id: "ccb", name: "中国建设银行", short: "建行", en: "CCB",
                  c1: 0x0066B3, c2: 0x003563, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "ccb"),
            .init(id: "bocom", name: "交通银行", short: "交行", en: "BOCOM",
                  c1: 0x00377A, c2: 0x001B3D, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "bocom"),
            .init(id: "psbc", name: "中国邮政储蓄银行", short: "邮储", en: "PSBC",
                  c1: 0x18AE66, c2: 0x054A33, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "psbc"),
            .init(id: "cmb", name: "招商银行", short: "招行", en: "CMB",
                  c1: 0xA30030, c2: 0x560019, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "cmb"),
            .init(id: "bosc", name: "上海银行", short: "上行", en: "BOSC",
                  c1: 0x0F499E, c2: 0x082654, ink: 0xFFFFFF, texture: "matte", network: "UNIONPAY",
                  chip: true, logo: "bosc"),

            // 钱包 / 虚拟信用 / 分期：无芯片，行徽放大到左上
            .init(id: "alipay", name: "支付宝", short: "支付宝", en: "ALIPAY",
                  c1: 0x1677FF, c2: 0x0B3F91, ink: 0xFFFFFF, texture: "matte", network: "WALLET",
                  chip: false, logo: "alipay"),
            .init(id: "yuebao", name: "余额宝", short: "余额宝", en: "YU'E BAO",
                  c1: 0xF7500E, c2: 0x8A2B07, ink: 0xFFFFFF, texture: "matte", network: "WALLET",
                  chip: false, logo: "yuebao"),
            .init(id: "huabei", name: "花呗", short: "花呗", en: "HUABEI",
                  c1: 0x4781F0, c2: 0x24417F, ink: 0xFFFFFF, texture: "matte", network: "CREDIT",
                  chip: false, logo: "huabei"),
            .init(id: "wechat", name: "微信支付", short: "微信", en: "WECHAT",
                  c1: 0x07C160, c2: 0x046237, ink: 0xFFFFFF, texture: "matte", network: "WALLET",
                  chip: false, logo: "wechat"),
            .init(id: "jd", name: "京东", short: "京东", en: "JD",
                  c1: 0xE21C19, c2: 0x7A0E0C, ink: 0xFFFFFF, texture: "matte", network: "WALLET",
                  chip: false, logo: "jd"),
            .init(id: "baitiao", name: "京东白条", short: "白条", en: "BAITIAO",
                  c1: 0xE21C19, c2: 0x7A0E0C, ink: 0xFFFFFF, texture: "matte", network: "CREDIT",
                  chip: false, logo: "jd"),
            .init(id: "jdgold", name: "京东小金库", short: "小金库", en: "JD GOLD",
                  c1: 0xE8A93D, c2: 0x8F5A07, ink: 0xFFFFFF, texture: "metal", network: "WALLET",
                  chip: false, logo: "jd"),
            .init(id: "douyin", name: "抖音", short: "抖音", en: "DOUYIN",
                  c1: 0x3A3F52, c2: 0x0A0C14, ink: 0xFFFFFF, texture: "matte", network: "CREDIT",
                  chip: false, logo: "douyin"),
            .init(id: "douyinloan", name: "抖音放心借", short: "放心借", en: "DOUYIN LOAN",
                  c1: 0xFF3D63, c2: 0x8C0A22, ink: 0xFFFFFF, texture: "metal", network: "INSTALLMENT",
                  chip: false, logo: "douyin"),
            .init(id: "ezhaodai", name: "招行 e招贷", short: "e招贷", en: "E-ZHAODAI",
                  c1: 0xA30030, c2: 0x560019, ink: 0xFFFFFF, texture: "metal", network: "INSTALLMENT",
                  chip: false, logo: "cmb"),
            .init(id: "cmcc", name: "中移金科", short: "中移金科", en: "CMCC",
                  c1: 0x0085D0, c2: 0x00456E, ink: 0xFFFFFF, texture: "matte", network: "INSTALLMENT",
                  chip: false, logo: "cmcc"),

            // 无行徽：降级为文字标（左下大字 + 中文名）
            .init(id: "loan-personal", name: "个人借款", short: "借款", en: "PERSONAL",
                  c1: 0xA8846A, c2: 0x4E3627, ink: 0xFFF6EC, texture: "matte", network: "NONE",
                  chip: false, logo: nil),
            .init(id: "cash", name: "现金", short: "现金", en: "CASH",
                  c1: 0x9AA88F, c2: 0x3E4A38, ink: 0xFFFFFF, texture: "matte", network: "NONE",
                  chip: false, logo: nil),
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
