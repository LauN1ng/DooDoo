import Testing
import SwiftData
import Foundation
@testable import DooDoo

/// M0 冒烟测试：只证明「工程能编、模型能存、tab 定义没跑偏」。
/// **金额与分期的真实用例从 M2 起才有**，且必须取自 PRD 附录的真实账单。
@MainActor
struct SmokeTests {
    @Test("RootTab 只有三段，顺序固定")
    func rootTabs() {
        #expect(RootTab.allCases.map(\.title) == ["流水", "资产", "设置"])
    }

    @Test("AppSettings 默认值")
    func settingsDefaults() {
        let s = AppSettings()
        #expect(s.incomeGreenExpenseRed == true)
        #expect(s.overdueBannerEnabled == true)
    }

    @Test("内存容器能写入并读回 AppSettings")
    func inMemoryStore() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: config)
        let context = ModelContext(container)

        context.insert(AppSettings(overdueBannerEnabled: false))
        try context.save()

        let all = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(all.count == 1)
        #expect(all.first?.overdueBannerEnabled == false)
    }
}
