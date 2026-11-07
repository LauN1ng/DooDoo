import SwiftUI
import SwiftData

/// 应用入口。
///
/// M0 只做三件事：能启动、三个 tab 切得动、SwiftData 容器能建起来。
/// **不要在这里加业务逻辑**——记账、余额、分期分别属于 M1/M2/M3。
@main
struct DooDooApp: App {
    /// 数据容器：纯本地、无 CloudKit、无账号（PRD 第六节）。
    /// schema 随里程碑推进再挂新模型，M0 只有 `AppSettings`。
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: AppSettings.self)
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
