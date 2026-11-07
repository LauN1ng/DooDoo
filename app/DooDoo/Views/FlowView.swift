import SwiftUI

/// 流水（首页）。
///
/// M0：空状态占位。M1 才做「今天一张日卡 + 按天左滑回看 + 记账行」，
/// 视觉依据 `docs/design/spec/首页规格冻结-v1.0.md`。
struct FlowView: View {
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Text("还没有记账")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("M1 会在这里出现今天那张日卡，\n卡片最后一行就是「记一笔」。")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FlowView()
}
