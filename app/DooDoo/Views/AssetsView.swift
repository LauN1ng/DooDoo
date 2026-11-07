import SwiftUI
import SwiftData

/// 资产。
///
/// M0：只验证「能读到 SwiftData」。M2 才做顶部总览、信用/储蓄两组卡堆与明细浮层，
/// 视觉依据 `docs/design/spec/资产页规格冻结-v1.0.md`。
struct AssetsView: View {
    @Query private var settings: [AppSettings]

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("资产")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("M2 才建账户与卡堆。\n当前 SwiftData 记录数：\(settings.count)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AssetsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}
