import SwiftUI
import UIKit

private enum KeyboardPalette {
    static let key = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.tertiaryLabel : UIColor.secondarySystemGroupedBackground })
    static let modifier = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.tertiarySystemFill : UIColor.quaternaryLabel })
}

struct KeyboardSurface: View {
    @ObservedObject var model: KeyboardModel
    var showsGlobe = true
    var compact = false
    var usesSystemBackground = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var keyHeight: CGFloat { compact ? 34 : 44 }
    private var keyAreaHeight: CGFloat { 4 * keyHeight + 3 * (compact ? 5 : 10) + 14 }

    static func height(compact: Bool, showsGlobe: Bool) -> CGFloat {
        32 + (compact ? 72 + 4 * 34 + 3 * 5 : 108 + 4 * 44 + 3 * 10) + 14
            + (showsGlobe ? 44 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                intimacyMeter
                Group {
                    if model.composition.isEmpty {
                        assistant
                    } else {
                        VStack(spacing: 0) {
                            composingAssistant
                            candidates
                        }
                    }
                }.frame(height: compact ? 72 : 108)
            }
                .background { impactBackground }
                .overlay(alignment: .bottom) { Divider() }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.visibleDelta)
            Group {
                if model.showsRecommendationReason, let suggestion = model.suggestion, !model.showsDraftImpact {
                    recommendationReason(suggestion)
                } else {
                    VStack(spacing: compact ? 5 : 10) {
                        if model.layout == .letters { letters } else { symbols }
                        bottomRow
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
            }
            .frame(height: keyAreaHeight)
            if showsGlobe {
                HStack {
                    Button(action: model.switchKeyboard) {
                        Image(systemName: "globe")
                            .font(.system(size: 23))
                            .frame(width: 48, height: 44)
                    }
                    .accessibilityLabel("切换输入法")
                    .accessibilityIdentifier("nextKeyboard")
                    Spacer()
                    if model.isPreview {
                        Text("交互预览 · 示例数据")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Color.clear.frame(width: 48, height: 44)
                }
                .padding(.horizontal, 10)
            }
        }
        .foregroundStyle(Color.primary)
        .background {
            if !usesSystemBackground { KeyboardBackdrop() }
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .popover(isPresented: $model.showsExplanation, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.showsDraftImpact ? "发送前预估" : model.suggestion?.intimacy == nil ? "推荐说明" : "亲密度依据").font(.headline)
                Text(model.showsDraftImpact ? (model.draftImpact?.explanation ?? "草稿更新后会重新预估。")
                     : model.suggestion?.explanation ?? "当前聊天依据不足，暂不评分。")
                    .font(.body)
                if model.showsDraftImpact {
                    Text("依据本次识别的聊天和键盘可读取的草稿估算；长草稿可能只读到部分内容。分数是互动游戏值，不代表对方的真实反应或关系变化。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("知道了") { model.showsExplanation = false }
            }
            .padding(20)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var intimacyMeter: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill").foregroundStyle(.pink)
            Text("亲密度").fontWeight(.medium)
            Text(model.currentIntimacy.map(String.init) ?? "—")
                .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.10))
                    .overlay(alignment: .leading) {
                        if let score = model.currentIntimacy {
                            Capsule().fill(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geometry.size.width * CGFloat(score) / 100)
                        }
                    }
            }.frame(height: 5)
                .accessibilityHidden(true)
            Text(model.currentIntimacy == nil ? "待评估" : model.intimacyNeedsRefresh ? "上次评分" : "当前评分")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.currentIntimacy.map { "亲密度 \($0) 分，满分 100，\(model.intimacyNeedsRefresh ? "上次评分" : "当前评分")" } ?? "亲密度待评估")
        .accessibilityIdentifier("intimacyMeter")
    }

    private func recommendationReason(_ suggestion: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("为什么这样说").font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.showsRecommendationReason = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityLabel("关闭推荐原因，返回键盘")
                .accessibilityIdentifier("closeRecommendationReason")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reason = suggestion.reason {
                        reasonSection("当前判断", text: reason.relationshipStage + "\n" + reason.observation)
                        reasonSection("建议行动", text: reason.action)
                        reasonSection("期望效果", text: reason.expectedResult)
                    }
                    Text(suggestion.explanation)
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if suggestion.isDemo {
                        Text("示例说明 · 未分析真实聊天")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recommendationReasonPanel")
    }

    private func reasonSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Text(text).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Candidates share the existing toolbar; there is no separate Latin-input row.
    private var composingAssistant: some View {
        HStack(spacing: 8) {
            analysisButton
            Text("选好词后，JEV 预估这句话的影响")
                .lineLimit(1).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 13)
        .frame(height: 44)
    }

    private var assistant: some View {
        HStack(spacing: 10) {
            analysisButton
            Group {
                if model.showsDraftImpact { draftImpactContent }
                else { assistantContent }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    private var impactTint: Color {
        guard let delta = model.visibleDelta, delta != 0 else { return .secondary }
        if delta > 0 {
            return colorScheme == .dark ? Color(red: 1, green: 0.77, blue: 0.5)
                : Color(red: 0.58, green: 0.16, blue: 0.04)
        }
        return colorScheme == .dark ? Color(red: 0.6, green: 0.84, blue: 1)
            : Color(red: 0.06, green: 0.28, blue: 0.58)
    }

    @ViewBuilder private var impactBackground: some View {
        if let delta = model.visibleDelta, delta != 0 {
            let strength = Double(abs(delta)) / 12
            let opacity = (colorScheme == .dark ? 0.23 : 0.12) + strength * 0.22
            LinearGradient(colors: delta > 0
                ? [Color.orange.opacity(opacity), Color.red.opacity(opacity + 0.08), Color.orange.opacity(opacity)]
                : [Color.cyan.opacity(opacity), Color.blue.opacity(opacity + 0.06), Color.cyan.opacity(opacity)],
                startPoint: .leading, endPoint: .trailing)
                .background(Color(UIColor.systemBackground))
        }
    }

    @ViewBuilder private var draftImpactContent: some View {
        if case .ready(let impact) = model.draftImpactPhase, let delta = model.visibleDelta,
           let before = model.currentIntimacy, let after = model.projectedIntimacy {
            Button { model.showsExplanation = true } label: {
                VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: delta > 0 ? "flame.fill" : delta < 0 ? "snowflake" : "equal.circle.fill")
                            .font(.system(size: 23, weight: .medium)).foregroundStyle(impactTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(delta > 0 ? "这句话，预计升温" : delta < 0 ? "这句话，可能降温" : "这句话，平稳交流")
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            Text(model.isPreview ? "示例预估 · 未调用模型" : "JEV · 发送后预估")
                                .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(contrast == .increased ? 1 : 0.8))
                        }
                        Spacer(minLength: 2)
                        Text("\(model.signedImpact) 分")
                            .font(.system(size: compact ? 23 : 28, weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(impactTint)
                            .minimumScaleFactor(0.8)
                    }
                    HStack(spacing: 7) {
                        Text("发送后预计 \(after) 分")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Text(impact.explanation).font(.system(size: 11))
                            .lineLimit(1).foregroundStyle(Color.primary.opacity(contrast == .increased ? 1 : 0.8))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.isPreview ? "示例" : "JEV") 发送后预估，亲密度\(delta > 0 ? "增加" : delta < 0 ? "减少" : "变化")\(abs(delta))分，从\(before)到\(after)。\(impact.explanation)")
            .accessibilityHint("轻点查看预估说明")
            .accessibilityIdentifier("draftImpact")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if model.draftImpactPhase == .analyzing { ProgressView().controlSize(.small) }
                    Text(draftStatus).font(.system(size: 14, weight: .medium)).lineLimit(2)
                }
                Text("发送前预估 · 编辑后自动更新")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.accessibilityIdentifier("draftImpactStatus")
        }
    }

    private var draftStatus: String {
        switch model.draftImpactPhase {
        case .idle: return "输入一句话，看看会升温还是降温"
        case .composing: return "选好词后预估"
        case .waiting: return "停笔片刻，看看这句话的影响"
        case .analyzing: return "JEV 正在预估这句话…"
        case .unavailable(let message): return model.isAnalyzing ? "正在识别聊天，稍后预估…" : message
        case .ready(let impact): return impact.explanation
        }
    }

    private var analysisButton: some View {
        Button(action: model.requestAnalysis) {
            Image(systemName: "sparkles")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(model.isAnalyzing ? Color.secondary : Color.blue)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyboardPressStyle())
        .disabled(model.isAnalyzing)
        .accessibilityLabel("识别聊天并分析")
        .accessibilityHint("识别当前可见聊天，分析互动评分并推荐下一句话")
        .accessibilityIdentifier("analyzeChat")
    }

    @ViewBuilder private var assistantContent: some View {
        switch model.phase {
        case .ready(let suggestion):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text("推荐回复").foregroundStyle(.secondary)
                    Spacer()
                    Text(recommendationImpactLabel)
                        .foregroundStyle(impactTint)
                        .fontWeight(.semibold).monospacedDigit()
                        .accessibilityLabel("这条推荐回复，\(recommendationImpactLabel)")
                        .accessibilityIdentifier("recommendationImpact")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(height: compact ? 16 : 20)
                HStack(alignment: .center, spacing: 2) {
                    Text(suggestion.text)
                        .font(.system(size: compact ? 14 : 16))
                        .lineLimit(compact ? 2 : 3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("recommendation")
                    Button(action: model.toggleRecommendationReason) {
                        Image(systemName: model.showsRecommendationReason ? "questionmark.circle.fill" : "questionmark.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(model.showsRecommendationReason ? Color.blue : Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyboardPressStyle())
                    .accessibilityLabel("为什么推荐这句话")
                    .accessibilityValue(model.showsRecommendationReason ? "已展开" : "已收起")
                    .accessibilityHint("查看当前判断、建议行动和期望效果")
                    .accessibilityIdentifier("recommendationReason")
                    Button(action: model.useSuggestion) {
                        Text("填入")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 50, height: 36)
                    }
                    .buttonStyle(KeyboardInsertStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("insertSuggestion")
                }
                .frame(maxHeight: .infinity)
                Text(model.feedback ?? (suggestion.isDemo ? "示例推荐 · 未调用模型" : "本次分析 · 点星光更新"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: compact ? 12 : 24)
            }
        case .recognizing, .analyzing:
            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(.blue)
                Text(model.phase == .recognizing ? "正在识别当前聊天…" : "正在理解关系，准备建议…")
                    .font(.system(size: 14))
                    .accessibilityIdentifier(model.phase == .recognizing ? "recognizing" : "analyzing")
            }
        case .waiting:
            VStack(alignment: .leading, spacing: 5) {
                Text("点星光，帮你接下一句")
                    .font(.system(size: 15, weight: .medium))
                Text("识别聊天 · 互动评分 · 回复推荐")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.system(size: 13)).lineLimit(2)
                Text("准备好后，点星光重试")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var recommendationImpactLabel: String {
        if let delta = model.visibleDelta {
            return delta == 0 ? "预计 0 分" : "预计 \(model.signedImpact) 分"
        }
        switch model.recommendationImpactPhase {
        case .ready: return "暂不预估"
        case .unavailable: return "预估暂不可用"
        default: return model.suggestion?.isDemo == true ? "示例预估" : "影响预估中…"
        }
    }

    private var candidates: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.candidateMatches) { candidate in
                    Button { model.selectCandidate(candidate) } label: {
                        Text(candidate.text)
                            .font(.system(size: 21))
                            .padding(.horizontal, 16)
                            .frame(minWidth: 44, minHeight: compact ? 36 : 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("candidate-\(candidate.text)")
                }
            }
        }
        .id(model.composition)
        .padding(.horizontal, 4)
        .frame(height: compact ? 36 : 44)
        .accessibilityIdentifier("pinyinCandidates")
    }

    private var letters: some View {
        Group {
            letterRow("qwertyuiop")
            letterRow("asdfghjkl").padding(.horizontal, 17)
            HStack(spacing: 6) {
                key(icon: model.capsLock ? "capslock.fill" : (model.uppercase ? "shift.fill" : "shift"),
                    modifier: true, width: 43, action: model.shift)
                    .accessibilityLabel("切换大小写")
                ForEach(Array("zxcvbnm"), id: \.self) { letter in
                    key(model.uppercase ? String(letter).uppercased() : String(letter)) { model.type(String(letter)) }
                }
                deleteKey
            }
        }
    }

    private func letterRow(_ letters: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(letters), id: \.self) { letter in
                key(model.uppercase ? String(letter).uppercased() : String(letter)) { model.type(String(letter)) }
            }
        }
    }

    private var symbols: some View {
        Group {
            textRow(model.layout == .numbers ? ["1","2","3","4","5","6","7","8","9","0"] : ["[","]","{","}","#","%","^","*","+","="])
            textRow(model.layout == .numbers ? ["-","/",":",";","(",")","¥","&","@","\""] : ["_","\\","|","~","<",">","€","£","$","·"])
            HStack(spacing: 6) {
                key(model.layout == .numbers ? "#+=" : "123", modifier: true, width: 48) {
                    model.layout = model.layout == .numbers ? .symbols : .numbers
                }
                ForEach(["。","，","？","！","'"], id: \.self) { value in key(value) { model.type(value) } }
                deleteKey
            }
        }
    }

    private func textRow(_ values: [String]) -> some View {
        HStack(spacing: 6) { ForEach(values, id: \.self) { value in key(value) { model.type(value) } } }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            key(model.layout == .letters ? "123" : "ABC", modifier: true, width: 43) {
                model.commitComposition()
                model.layout = model.layout == .letters ? .numbers : .letters
            }
            key("中/英", modifier: true, width: 48, action: model.switchLanguage)
                .accessibilityLabel(model.chinese ? "当前中文，切换英文" : "当前英文，切换中文")
            key(model.chinese ? "空格" : "space", action: model.space)
            key(icon: "return", modifier: true, width: 76, action: model.returnKey)
                .accessibilityLabel("换行")
        }
    }

    private var deleteKey: some View {
        key(icon: "delete.left", modifier: true, width: 44, action: model.backspace)
            .accessibilityLabel("删除")
            .accessibilityIdentifier("backspace")
    }

    private func key(_ title: String = "", icon: String? = nil, modifier: Bool = false,
                     width: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 21)) }
                else { Text(title).font(.system(size: title.count > 1 ? 16 : 25)) }
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(keyFill(modifier: modifier),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .buttonStyle(KeyboardPressStyle())
        .frame(width: width)
        .accessibilityIdentifier(icon ?? "key-\(title)")
    }

    private func keyFill(modifier: Bool) -> Color {
        if #available(iOS 26.0, *) { return KeyboardPalette.key }
        return modifier ? KeyboardPalette.modifier : KeyboardPalette.key
    }
}

private struct KeyboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.16))
                }
            }
    }
}

/// Only the in-app preview needs a backdrop. The extension uses UIInputView's keyboard material.
private struct KeyboardBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            Color(UIColor.systemGroupedBackground)
        } else if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular,
                in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}

private struct KeyboardInsertStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            configuration.label
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(.blue).interactive(), in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
        } else {
            configuration.label
                .foregroundStyle(.white)
                .background(.blue, in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}
