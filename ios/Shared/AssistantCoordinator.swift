import Foundation

@MainActor
final class AssistantCoordinator {
    typealias Analyze = (ChatContext, ServiceSettings) async throws -> Suggestion
    typealias StreamAnalyze = (ChatContext, ServiceSettings, @escaping @MainActor (IntimacyAssessment) -> Void) async throws -> Suggestion
    private(set) var captureRequest: CaptureRequest?
    private(set) var capturedContext: ChatContext?
    private var activeRequestID: String?
    private var sessionID: String?
    private var task: Task<Void, Never>?
    private let analyze: StreamAnalyze
    var onPhase: (AssistantPhase) -> Void = { _ in }
    var onAssessment: (IntimacyAssessment) -> Void = { _ in }

    init(streamAnalyze: @escaping StreamAnalyze = { context, settings, onAssessment in
        guard let endpoint = settings.endpointURL else { throw AssistantError.unconfigured }
        return try await AssistantClient().analyze(context, endpoint: endpoint, token: settings.accessToken, onAssessment: onAssessment)
    }) { self.analyze = streamAnalyze }

    convenience init(analyze: @escaping Analyze) {
        self.init(streamAnalyze: { context, settings, _ in try await analyze(context, settings) })
    }

    func invalidate(_ phase: AssistantPhase = .waiting) {
        capturedContext = nil
        captureRequest = nil
        activeRequestID = nil
        sessionID = nil
        task?.cancel(); task = nil
        onPhase(phase)
    }

    /// Only the Sparkle action can create a capture request. Repeated taps while busy are ignored.
    @discardableResult
    func begin(sessionID: String, settings: ServiceSettings, now: Date = Date()) -> CaptureRequest? {
        guard captureRequest == nil, task == nil else { return nil }
        if let issue = settings.configurationIssue { invalidate(.unavailable(issue)); return nil }
        let request = CaptureRequest(requestedAt: now)
        capturedContext = nil
        self.sessionID = sessionID
        activeRequestID = request.id
        captureRequest = request
        onPhase(.recognizing)
        return request
    }

    func receive(_ snapshot: CaptureSnapshot?, sessionID: String, settings: ServiceSettings, now: Date = Date()) {
        // Polling, old captures, or new frames cannot start or restart model work without a click.
        guard let request = captureRequest else { return }
        guard self.sessionID == sessionID else { invalidate(); return }
        if let issue = settings.configurationIssue { invalidate(.unavailable(issue)); return }
        guard request.isFresh(at: now) else {
            let message = snapshot?.isFresh(at: now) == true
                ? "未识别到稳定的单聊内容，请停留在聊天画面后重试"
                : "请先启动系统屏幕广播，再点星光按钮"
            invalidate(.unavailable(message)); return
        }
        guard let snapshot, snapshot.isFresh(at: now), snapshot.requestID == request.id,
              snapshot.updatedAt >= request.requestedAt else { return }
        switch snapshot.status {
        case .ready:
            guard let context = snapshot.context, context.sessionID == sessionID,
                  context.captureID == request.id, context.capturedAt >= request.requestedAt else { return }
            captureRequest = nil
            capturedContext = context
            onPhase(.analyzing)
            task = Task { [weak self, analyze] in
                do {
                    let result = try await analyze(context, settings) { [weak self] assessment in
                        guard !Task.isCancelled, let self, self.activeRequestID == request.id,
                              assessment.sessionID == context.sessionID, assessment.revision == context.revision,
                              assessment.isValid else { return }
                        self.onAssessment(assessment)
                    }
                    guard !Task.isCancelled, let self, self.activeRequestID == request.id else { return }
                    guard result.sessionID == context.sessionID, result.revision == context.revision else {
                        throw AssistantError.staleResponse
                    }
                    self.task = nil
                    self.onPhase(.ready(result))
                } catch {
                    guard !Task.isCancelled, let self, self.activeRequestID == request.id else { return }
                    self.task = nil
                    self.onPhase(.unavailable((error as? LocalizedError)?.errorDescription ?? "分析暂不可用，请重试"))
                }
            }
        case .paused, .stopped, .unavailable:
            invalidate(.unavailable(snapshot.message))
        case .starting, .waiting, .recognizing:
            break
        }
    }
}

/// Versioned, cancellable draft analysis. Only settled, committed text reaches Jev.
@MainActor
final class DraftImpactCoordinator {
    typealias Analyze = (String, String, ChatContext, ServiceSettings) async throws -> DraftImpact
    private struct Input: Equatable {
        let draft: String?
        let composing: Bool
        let context: ChatContext?
        let settings: ServiceSettings
        let enabled: Bool
    }
    private var lastInput: Input?
    private var requestID: String?
    private var task: Task<Void, Never>?
    private let analyze: Analyze
    private let debounce: TimeInterval
    private let minimumInterval: TimeInterval
    private var lastStarted = Date.distantPast
    var onPhase: (DraftImpactPhase) -> Void = { _ in }

    init(debounce: TimeInterval = 0.9, minimumInterval: TimeInterval = 2.5,
         analyze: @escaping Analyze = { draft, id, context, settings in
             guard let endpoint = settings.endpointURL else { throw AssistantError.unconfigured }
             return try await AssistantClient().analyzeDraft(draft, id: id, context: context,
                 endpoint: endpoint, token: settings.accessToken)
         }) {
        self.debounce = debounce
        self.minimumInterval = minimumInterval
        self.analyze = analyze
    }

    func invalidate() {
        task?.cancel(); task = nil
        requestID = nil
        lastInput = nil
        onPhase(.idle)
    }

    func update(draft: String?, composing: Bool, context: ChatContext?, settings: ServiceSettings, enabled: Bool = true) {
        let text = draft?.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = Input(draft: text, composing: composing, context: context, settings: settings, enabled: enabled)
        guard lastInput != input else { return }
        lastInput = input
        task?.cancel(); task = nil
        requestID = nil
        guard enabled else { onPhase(.idle); return }
        if composing { onPhase(.composing); return }
        guard let text else { onPhase(.unavailable("暂时读不到草稿，请继续输入")); return }
        guard !text.isEmpty else { onPhase(.idle); return }
        if let issue = settings.configurationIssue { onPhase(.unavailable(issue)); return }
        guard text.utf16.count <= 2_000 else { onPhase(.unavailable("草稿较长，请缩短后再预估")); return }
        guard let context else { onPhase(.unavailable("点星光识别聊天，即可预估这句话")); return }
        let id = UUID().uuidString
        requestID = id
        onPhase(.waiting) // Clear the previous score synchronously, before the debounce.
        let delay = max(debounce, minimumInterval - Date().timeIntervalSince(lastStarted))
        task = Task { [weak self, analyze] in
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.lastStarted = Date()
                self.onPhase(.analyzing)
                let result = try await analyze(text, id, context, settings)
                guard !Task.isCancelled, self.requestID == id else { return }
                guard result.sessionID == context.sessionID, result.revision == context.revision,
                      result.draftID == id, result.isValid else { throw AssistantError.invalidResponse }
                self.task = nil
                self.onPhase(.ready(result))
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.task = nil
                self.onPhase(.unavailable("预估暂不可用，编辑草稿或点星光重试"))
            }
        }
    }
}
