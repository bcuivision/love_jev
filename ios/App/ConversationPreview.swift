import SwiftUI

struct ConversationPreview: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = KeyboardModel()
    @State private var draft = ""
    @State private var sent: [String] = []
    @State private var showingSetup = false
    @State private var editor = UITextView()
    @State private var analysisTask: Task<Void, Never>?
    @State private var impactTask: Task<Void, Never>?
    let initiallyReady: Bool
    var holdLoading = false

    private let messages: [(String, Bool)] = [
        ("你说的那家咖啡店，后来去了吗？", true),
        ("还没呢，最近一直加班。", false),
        ("那等你忙完，有空去坐坐。", true),
        ("好呀，忙完再说～", false),
        ("终于忙完了，想出去走走。", false)
    ]
    private var chatBackground: Color { Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.93, alpha: 1) }) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(messages.indices, id: \.self) { index in
                                bubble(messages[index].0, outgoing: messages[index].1)
                                    .id("message-\(index)")
                            }
                            ForEach(sent.indices, id: \.self) { index in
                                bubble(sent[index], outgoing: true).id("sent-\(index)")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .onAppear { proxy.scrollTo("message-\(messages.count - 1)", anchor: .bottom) }
                    .onChange(of: sent.count) { _, count in
                        withAnimation { proxy.scrollTo("sent-\(count - 1)", anchor: .bottom) }
                    }
                }
                composer
                KeyboardSurface(model: model, compact: geometry.size.width > geometry.size.height)
            }
            .background(chatBackground)
        }
        .background(chatBackground.ignoresSafeArea())
        .sheet(isPresented: $showingSetup) { SetupView() }
        .task {
            model.isPreview = true
            model.insert = { editor.insertText($0); draft = editor.text }
            model.delete = { editor.deleteBackward(); draft = editor.text }
            model.markText = { text, range in
                editor.setMarkedText(text, selectedRange: range)
                draft = editor.text
            }
            model.unmarkText = { editor.unmarkText(); draft = editor.text }
            model.nextKeyboard = { model.feedback = "系统键盘切换请在设置页的测试输入框验证" }
            model.requestAnalysis = { runPreviewAnalysis() }
            model.inputDidChange = { updatePreviewImpact() }
            model.phase = initiallyReady ? .ready(.preview) : (holdLoading ? .analyzing : .waiting)
            // The preview conversation has a known fixture score even before a reply is generated.
            model.acceptAssessment(IntimacyAssessment(sessionID: "preview", revision: 1, intimacy: 72, isDemo: true))
            if initiallyReady { setPreviewRecommendationImpact() }
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--preview-warm") { setPreviewDraft(Suggestion.preview.text) }
            if args.contains("--preview-cold") { setPreviewDraft("随便你，别烦我。") }
            if args.contains("--preview-neutral") { setPreviewDraft("好的，知道了。") }
        }
        .onChange(of: draft) { _, _ in updatePreviewImpact() }
        .onChange(of: model.composition) { _, _ in updatePreviewImpact() }
        .onDisappear { analysisTask?.cancel(); impactTask?.cancel() }
    }

    private func setPreviewRecommendationImpact() {
        model.recommendationImpactPhase = .ready(DraftImpact(sessionID: "preview", revision: 1,
            draftID: "recommendation", before: 72, after: 80, delta: 8,
            explanation: "顺着对方的意愿，提出轻松的邀请。", isDemo: true))
    }

    private func setPreviewDraft(_ text: String) {
        model.finishComposition()
        editor.text = text
        draft = text
        updatePreviewImpact()
    }

    private func updatePreviewImpact() {
        impactTask?.cancel()
        guard model.composition.isEmpty else { model.draftImpactPhase = .composing; return }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.draftImpactPhase = .idle; return
        }
        // Fixed, visibly labelled interaction fixtures; arbitrary text is never fake-scored.
        let examples = [Suggestion.preview.text: (8, "顺着对方的意愿，提出轻松的邀请。"),
                        "随便你，别烦我。": (-8, "语气生硬，可能让对方感到被推开。"),
                        "好的，知道了。": (0, "这句话偏中性，互动信号变化不大。")]
        guard let example = examples[draft] else {
            model.draftImpactPhase = .unavailable("预览选项可体验升温、降温和平稳示例")
            return
        }
        model.draftImpactPhase = .waiting
        impactTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            model.draftImpactPhase = .ready(DraftImpact(sessionID: "preview", revision: 1,
                draftID: "example", before: 72, after: 72 + example.0, delta: example.0,
                explanation: example.1, isDemo: true))
        }
    }

    private func runPreviewAnalysis() {
        guard !model.isAnalyzing else { return }
        model.feedback = nil
        model.showsExplanation = false
        model.phase = .recognizing
        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.phase = .analyzing
            model.acceptAssessment(IntimacyAssessment(sessionID: "preview", revision: 1, intimacy: 72, isDemo: true))
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            model.phase = .ready(.preview)
            setPreviewRecommendationImpact()
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss(); showingSetup = true } label: {
                Image(systemName: "chevron.left").font(.system(size: 24, weight: .regular))
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("返回设置")
            Spacer()
            VStack(spacing: 2) {
                Text("小雨").font(.system(size: 19, weight: .medium))
                Text("键盘预览").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("体验升温 +8 分") { setPreviewDraft(Suggestion.preview.text) }
                Button("体验降温 −8 分") { setPreviewDraft("随便你，别烦我。") }
                Button("体验平稳 0 分") { setPreviewDraft("好的，知道了。") }
                Divider()
                Button("重新分析当前聊天", action: runPreviewAnalysis)
                    .disabled(model.isAnalyzing)
                Button("清空演示草稿") {
                    model.finishComposition()
                    editor.text = ""
                    draft = ""
                    sent = []
                }
                Button("打开设置") { showingSetup = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 23, weight: .semibold))
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("预览选项")
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 54)
        .background(chatBackground)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    private func bubble(_ message: String, outgoing: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if outgoing { Spacer(minLength: 28) }
            if !outgoing { avatar(outgoing: false) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
                if !outgoing { Text("小雨").font(.system(size: 11)).foregroundStyle(.secondary) }
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(outgoing ? Color.black : Color.primary)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(outgoing ? Color(red: 0.65, green: 0.9, blue: 0.47) : Color(UIColor.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if outgoing { avatar(outgoing: true) }
            if !outgoing { Spacer(minLength: 28) }
        }
    }

    private func avatar(outgoing: Bool) -> some View {
        Circle().fill(outgoing ? Color(red: 0.83, green: 0.63, blue: 0.32) : Color(red: 0.72, green: 0.65, blue: 0.83))
            .frame(width: 33, height: 33)
            .accessibilityHidden(true)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle").font(.system(size: 27)).accessibilityHidden(true)
            PreviewDraftEditor(text: $draft, editor: editor)
                .frame(maxWidth: .infinity)
                .frame(height: draft.count > 14 || draft.contains("\n") ? 68 : 40)
                .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("previewDraft")
                .accessibilityLabel("草稿")
                .accessibilityValue(draft)
            Image(systemName: "face.smiling").font(.system(size: 25)).accessibilityHidden(true)
            if draft.isEmpty {
                Image(systemName: "plus.circle").font(.system(size: 28)).accessibilityHidden(true)
            } else {
                Button("发送") {
                    model.commitComposition()
                    sent.append(draft)
                    editor.text = ""
                    draft = ""
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(Color(red: 0.02, green: 0.67, blue: 0.35), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityIdentifier("sendPreview")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.5))
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }
}

private struct PreviewDraftEditor: UIViewRepresentable {
    @Binding var text: String
    let editor: UITextView
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> UITextView {
        editor.delegate = context.coordinator
        editor.font = .systemFont(ofSize: 16)
        editor.backgroundColor = .clear
        editor.textContainerInset = UIEdgeInsets(top: 9, left: 7, bottom: 8, right: 7)
        editor.inputView = UIView(frame: .zero)
        editor.inputAssistantItem.leadingBarButtonGroups = []
        editor.inputAssistantItem.trailingBarButtonGroups = []
        editor.accessibilityIdentifier = "previewDraft"
        editor.accessibilityLabel = "草稿"
        return editor
    }
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}
