import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardSurface>?
    private var heightConstraint: NSLayoutConstraint?
    private var lastLayout: (compact: Bool, globe: Bool)?
    private var updatingMarkedText = false
    private var documentID: UUID?
    private let store = SharedStore()
    private let assistant = AssistantCoordinator()
    private let draftAssistant = DraftImpactCoordinator()
    private let recommendationAssistant = DraftImpactCoordinator(debounce: 0, minimumInterval: 0)
    private var hadDraft = false
    private var sessionID = UUID().uuidString
    private var tickTask: Task<Void, Never>?
    private var isVisible = false
    private var lastSettings: ServiceSettings?

    override func loadView() {
        // Let UIKit supply the current OS's keyboard blur and tint.
        let keyboard = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        keyboard.allowsSelfSizing = true
        if #available(iOS 26.0, *) {
            keyboard.layer.cornerRadius = 28
            keyboard.layer.cornerCurve = .continuous
            keyboard.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            keyboard.clipsToBounds = true
        }
        view = keyboard
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryLanguage = "zh-Hans"
        model.insert = { [weak self] in self?.textDocumentProxy.insertText($0) }
        model.delete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        model.markText = { [weak self] text, range in
            guard let self else { return }
            self.updatingMarkedText = true
            defer { self.updatingMarkedText = false }
            self.textDocumentProxy.setMarkedText(text, selectedRange: range)
        }
        model.unmarkText = { [weak self] in
            guard let self else { return }
            self.updatingMarkedText = true
            defer { self.updatingMarkedText = false }
            self.textDocumentProxy.unmarkText()
        }
        model.nextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        model.requestAnalysis = { [weak self] in self?.requestAnalysis() }
        model.inputDidChange = { [weak self] in self?.updateDraft() }
        draftAssistant.onPhase = { [weak self] phase in
            self?.model.showsExplanation = false
            self?.model.draftImpactPhase = phase
        }
        recommendationAssistant.onPhase = { [weak self] in self?.model.recommendationImpactPhase = $0 }
        assistant.onAssessment = { [weak self] in self?.model.acceptAssessment($0) }
        assistant.onPhase = { [weak self] phase in
            self?.model.feedback = nil
            self?.model.showsExplanation = false
            self?.model.phase = phase
            if case .ready(let suggestion) = phase, let self {
                self.recommendationAssistant.update(draft: suggestion.text, composing: false,
                    context: self.assistant.capturedContext, settings: self.store.settings(),
                    enabled: self.isVisible && self.hasFullAccess && !suggestion.isDemo)
            } else { self?.recommendationAssistant.invalidate() }
            self?.updateDraft()
        }
        let root = KeyboardSurface(model: model, usesSystemBackground: true)
        let host = UIHostingController(rootView: root)
        self.host = host
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        let height = view.heightAnchor.constraint(equalToConstant: 342)
        height.priority = .required
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if documentID != textDocumentProxy.documentIdentifier { model.resetIntimacy() }
        documentID = textDocumentProxy.documentIdentifier
        sessionID = UUID().uuidString
        hadDraft = false
        draftAssistant.invalidate()
        assistant.invalidate()
        isVisible = true
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
        updateAppearance()
        updateHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        if documentID == textDocumentProxy.documentIdentifier { model.finishComposition() }
        else { model.resetComposition() }
        draftAssistant.invalidate()
        tickTask?.cancel(); tickTask = nil
        assistant.invalidate()
        publishPresence()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // A changed input document must not inherit another conversation's suggestion.
        if documentID != textDocumentProxy.documentIdentifier {
            documentID = textDocumentProxy.documentIdentifier
            sessionID = UUID().uuidString
            model.resetIntimacy()
            model.resetComposition()
            hadDraft = false
            draftAssistant.invalidate()
            assistant.invalidate()
            tick()
        }
        updateAppearance()
        updateDraft()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if !updatingMarkedText { updateDraft() }
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        guard !updatingMarkedText else { return }
        if documentID == textDocumentProxy.documentIdentifier { model.finishComposition() }
        else { model.resetComposition() }
    }

    private func updateAppearance() {
        let appearance: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance {
        case .dark: appearance = .dark
        case .light: appearance = .light
        default: appearance = view.window?.traitCollection.userInterfaceStyle ?? traitCollection.userInterfaceStyle
        }
        // The extension's hosted SwiftUI controller doesn't always receive the
        // remote host's appearance change at the same time as UIInputView.
        if host?.overrideUserInterfaceStyle != appearance { host?.overrideUserInterfaceStyle = appearance }
    }

    @discardableResult
    private func publishPresence() -> Bool {
        guard hasFullAccess, store.isAvailable else { return false }
        let screenHeight = view.window?.screen.bounds.height ?? UIScreen.main.bounds.height
        do {
            try store.write(KeyboardPresence(sessionID: sessionID, isVisible: isVisible,
                screenHeight: Double(screenHeight), keyboardHeight: Double(view.bounds.height), updatedAt: Date(),
                captureRequest: assistant.captureRequest), to: "keyboard.json")
            return true
        } catch { return false }
    }

    private func requestAnalysis() {
        guard isVisible else { return }
        guard hasFullAccess, store.isAvailable else { tick(); return }
        let settings = store.settings()
        if settings != lastSettings { model.resetIntimacy(); assistant.invalidate(); lastSettings = settings }
        guard assistant.begin(sessionID: sessionID, settings: settings) != nil else { return }
        if !publishPresence() { assistant.invalidate(.unavailable("无法请求识别，请重试")) }
    }

    private func tick() {
        guard isVisible else { return }
        updateAppearance()
        defer { updateDraft() }
        guard hasFullAccess else {
            model.resetIntimacy()
            assistant.invalidate(.unavailable("请在系统设置中允许键盘完全访问")); return
        }
        guard store.isAvailable else {
            model.resetIntimacy()
            assistant.invalidate(.unavailable("共享数据不可用，请检查 App Group 签名")); return
        }
        let settings = store.settings()
        if settings != lastSettings { model.resetIntimacy(); assistant.invalidate(); lastSettings = settings }
        publishPresence()
        let snapshot = store.read("capture.json", as: CaptureSnapshot.self)
        if let context = assistant.capturedContext,
           !((snapshot?.isFresh() ?? false)) || Date().timeIntervalSince(context.capturedAt) > 120
            || [.paused, .stopped, .unavailable].contains(snapshot?.status ?? .stopped) {
            assistant.invalidate(.unavailable("聊天上下文已过期，请点星光更新"))
        }
        guard assistant.captureRequest != nil else { return }
        assistant.receive(snapshot, sessionID: sessionID, settings: settings)
    }

    private func updateDraft() {
        guard isVisible else { return }
        let proxy = textDocumentProxy
        if documentID != proxy.documentIdentifier {
            documentID = proxy.documentIdentifier
            sessionID = UUID().uuidString
            model.resetIntimacy()
            hadDraft = false
            model.resetComposition()
            draftAssistant.invalidate()
            assistant.invalidate()
        }
        let hasDraft = proxy.hasText
        let cleared = hadDraft && !hasDraft && model.composition.isEmpty
        hadDraft = hasDraft
        if cleared { assistant.invalidate() } // Sending/clearing must not reuse the old conversation snapshot.
        let before = proxy.documentContextBeforeInput
        let after = proxy.documentContextAfterInput
        let selected = proxy.selectedText
        let text: String? = !hasDraft ? "" : before == nil && after == nil && selected == nil ? nil
            : (before ?? "") + (selected ?? "") + (after ?? "")
        let settings = store.settings()
        draftAssistant.update(draft: text, composing: !model.composition.isEmpty,
            context: settings == lastSettings ? assistant.capturedContext : nil,
            settings: settings, enabled: hasFullAccess && store.isAvailable)
    }

    private func updateHeight() {
        // An extension's window can be only keyboard-height even in portrait.
        // This iPhone-only target uses available width to select landscape key sizing.
        let compact = view.bounds.width > 600
        let globe = needsInputModeSwitchKey
        let height = KeyboardSurface.height(compact: compact, showsGlobe: globe)
        if heightConstraint?.constant != height { heightConstraint?.constant = height }
        if lastLayout?.compact != compact || lastLayout?.globe != globe {
            lastLayout = (compact, globe)
            host?.rootView = KeyboardSurface(model: model, showsGlobe: globe, compact: compact, usesSystemBackground: true)
        }
    }
}
