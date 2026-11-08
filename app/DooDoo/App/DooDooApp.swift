import SwiftUI
import SwiftData

/// 应用入口。
///
/// M0 建了空壳；M1 起接上真实模型（账户 / 分类 / 流水 / 设置）。
@main
struct DooDooApp: App {
    /// 数据容器：纯本地、无 CloudKit、无账号（PRD 第六节）。
    /// 新增模型时必须同步加进这里的 schema，否则那张表不会建。
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Account.self,
                Category.self,
                Transaction.self,
                AppSettings.self
            )
        } catch {
            // 容器建不起来说明 schema/迁移写错了，此时继续跑只会静默丢数据
            fatalError("SwiftData 容器创建失败：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
