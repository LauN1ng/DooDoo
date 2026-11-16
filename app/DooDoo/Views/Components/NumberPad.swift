import SwiftUI
import UIKit

/// 自绘数字键盘（M4 真机反馈第 5 条「系统键盘割裂，自设计键盘」）。
///
/// 为什么不用系统 `.decimalPad`：
/// 1. 系统数字键盘第一行要留位置给 ABC / 地球键，在一块**只有数字**的界面里
///    等于白扔 44pt；而这 44pt 正好够多放一行表单。
/// 2. 材质、键高、间距全由系统决定，与「`#F6F6F6` 页底 + 白卡」这套关系对不上，
///    真机上读起来就是「一块灰板贴在界面下方」——这正是用户说的「割裂」。
/// 3. `EntryView` 的主按钮必须紧贴键盘正上方（一屏内可见），系统键盘的高度
///    我们控制不了，`safeAreaInset` 里的页脚位置只能跟着它漂。
///
/// 结构：3 列 × 4 行（1–9，然后 `.` `0` `⌫`），键高 52、间距 6、圆角 12。
/// 行为：长按删除连续删；**不提供「完成」键**——主按钮本来就在键盘正上方，
/// 多一个完成键等于让用户每次多点一下（「记账不打断」是三条底线之一）。
///
/// 组件只认一个 `Binding<String>`，不碰任何 ViewModel：金额、到账、手续费、
/// 期数、剩余应还共用它，输入规则（前导 0、两位小数、整数位上限）也只写在这里一份。
struct NumberPad: View {
    /// 正在编辑的字段文本。空串 = 没输入，由调用方决定占位显示什么。
    @Binding var text: String
    /// 主色：按下态底色与光标。选中态语言与分类 / 账户统一（浅底 + 描边）。
    var accent: Color
    /// 主色 12% 浅底。
    var accentWash: Color
    /// 整数字段（剩余期数 / 总共几期）关掉小数点。那一格留空，保持网格对齐。
    var allowsDecimal: Bool = true
    /// 整数位上限。7 位够记到 9,999,999，再多就不是记账场景了。
    var maxIntegerDigits: Int = 7
    /// 小数位上限。金额一律两位（AGENTS 7.1）。
    var maxFractionDigits: Int = 2

    /// 键高 / 键间距。整块 = 4×52 + 3×6 = 226，加内距约 242。
    private let keyHeight: CGFloat = 52
    private let gap: CGFloat = 6

    @State private var deletePressed = false
    /// 连删用的任务句柄。显式写 `= nil`：没有初值的存储属性会进合成初始化器的
    /// 参数表，`NumberPad` 是跨文件构造的，少一个默认值就多一个必填参数。
    @State private var repeatTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: gap) {
            ForEach(Self.layout, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(row, id: \.self) { key in
                        keyView(key)
                    }
                }
            }
        }
        .onDisappear { repeatTask?.cancel() }
    }

    /// 键位表。3×3 数字 + 底部 `. / 0 / ⌫`。
    private static let layout: [[PadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.dot, .digit(0), .delete]
    ]

    // MARK: - 按键

    @ViewBuilder
    private func keyView(_ key: PadKey) -> some View {
        switch key {
        case .digit(let digit):
            numberKey("\(digit)") { append("\(digit)") }
        case .dot:
            if allowsDecimal {
                numberKey(".") { appendDot() }
            } else {
                // 留空白格而不是把 0 挪过去：网格一变，手指的肌肉记忆就废了。
                Color.clear.frame(height: keyHeight)
            }
        case .delete:
            deleteKey
        }
    }

    private func numberKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
        }
        .buttonStyle(PadKeyStyle(fill: Palette.card, pressed: accentWash))
        .accessibilityLabel(title == "." ? "小数点" : title)
    }

    /// 删除键。用 `DragGesture(minimumDistance: 0)` 而不是 `Button`:
    /// 需要「按下即删、按住连删、松手停」，`Button` 拿不到松手时机。
    private var deleteKey: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(deletePressed ? accentWash : Palette.slot)
            )
            .scaleEffect(deletePressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: deletePressed)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginDelete() }
                    .onEnded { _ in endDelete() }
            )
            .accessibilityElement()
            .accessibilityLabel("删除")
            .accessibilityAddTraits(.isButton)
            // 旁白 / 辅助控制只给「激活一次」的动作，连删手势它们触发不了。
            .accessibilityAction { backspace() }
    }

    /// 轻按只删一位，按住 0.35 秒后每 70ms 删一位。
    private func beginDelete() {
        guard !deletePressed else { return }
        deletePressed = true
        backspace()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            while !Task.isCancelled {
                backspace()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }

    private func endDelete() {
        deletePressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }

    // MARK: - 输入规则

    /// 追加一位数字。
    ///
    /// 三条规则都来自系统的实际行为，不是自创：
    /// 1. 前导 0 不堆叠——`0` 后面敲 `5` 得到 `5`，不是 `05`。
    /// 2. 整数位不超过 `maxIntegerDigits`。
    /// 3. 小数位不超过 `maxFractionDigits`。**例外**：整数部分已经写死两位小数
    ///    （转账联动算出的 `120.00`）时，敲数字先把凑数的零去掉再续，
    ///    否则「点进到账框想改个数，敲什么都没反应」。
    private func append(_ digit: String) {
        var next = text
        if next == "0" { next = "" }

        if let dot = next.firstIndex(of: ".") {
            var fraction = String(next[next.index(after: dot)...])
            if fraction.count >= maxFractionDigits,
               fraction.allSatisfy({ $0 == "0" }) {
                // `120.00` → `120.`，随后照常追加
                next = String(next[..<dot]) + "."
                fraction = ""
            }
            guard fraction.count < maxFractionDigits else { return }
        } else if next.count >= maxIntegerDigits {
            return
        }

        text = next + digit
    }

    /// 小数点。空框先补 `0`（得到 `0.`），已经有点了就不响应。
    private func appendDot() {
        guard allowsDecimal, !text.contains(".") else { return }
        text = text.isEmpty ? "0." : text + "."
    }

    private func backspace() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    // MARK: - 键位

    private enum PadKey: Hashable {
        case digit(Int)
        case dot
        case delete
    }
}

/// 数字键的按下态：浅主色底 + 缩到 0.97，120ms。
///
/// 不用系统默认的高亮（整块变灰），那套材质是为系统键盘准备的，
/// 放在白卡键上会连带把投影一起吃掉，看着像键被抠掉了。
private struct PadKeyStyle: ButtonStyle {
    var fill: Color
    var pressed: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? pressed : fill)
                    .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.05),
                            radius: 1.5, x: 0, y: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 数值字段的**显示态**（取代 `TextField`）。
///
/// 换成自绘键盘后输入框不能再是 `TextField`：只要它还是系统控件，
/// 点一下系统键盘就会弹出来，跟自绘键盘叠在一起。所以显示与输入彻底拆开——
/// 这里只负责把值画出来，输入交给 `NumberPad`，靠 `active` 说明「现在在改我」。
///
/// 光标用 `overlay` 挂而不是塞进 `HStack`：塞进去会让整行的 baseline 偏移，
/// `¥` 和金额就对不齐了。
struct NumberValueText: View {
    var text: String
    var placeholder: String
    var size: CGFloat
    var weight: Font.Weight = .semibold
    /// 当前正在编辑这个字段（显示光标）。
    var active: Bool
    var accent: Color

    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .foregroundStyle(text.isEmpty ? Palette.faint : Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.trailing, 8)
            .overlay(alignment: .trailing) {
                if active {
                    PadCaret(height: size * 0.82, color: accent)
                        .offset(x: 7)
                }
            }
    }
}

/// 编辑光标。常亮会跟背景糊在一起，所以做成 0.55s 呼吸。
private struct PadCaret: View {
    var height: CGFloat
    var color: Color

    @State private var lit = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: height)
            .opacity(lit ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    lit = false
                }
            }
    }
}
