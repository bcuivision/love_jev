import SwiftUI

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var phase: AssistantPhase = .waiting {
        didSet {
            if phase != oldValue {
                dismissExplanations()
                recommendationImpactPhase = .idle
            }
            if case .ready(let suggestion) = phase {
                acceptAssessment(IntimacyAssessment(sessionID: suggestion.sessionID, revision: suggestion.revision,
                    intimacy: suggestion.intimacy, isDemo: suggestion.isDemo))
            } else if phase != oldValue { intimacyNeedsRefresh = intimacyAssessment != nil }
        }
    }
    @Published private(set) var intimacyAssessment: IntimacyAssessment?
    @Published private(set) var intimacyNeedsRefresh = false
    @Published var recommendationImpactPhase: DraftImpactPhase = .idle
    @Published private(set) var composition = ""
    @Published private(set) var candidateMatches: [PinyinCandidate] = []
    @Published var chinese = true
    @Published var uppercase = false
    @Published var capsLock = false
    @Published var layout: Layout = .letters
    @Published var feedback: String?
    @Published var showsExplanation = false
    @Published var showsRecommendationReason = false
    @Published var isPreview = false
    @Published var inputEnabled = true
    @Published var draftImpactPhase: DraftImpactPhase = .idle {
        didSet { if draftImpactPhase != oldValue { dismissExplanations() } }
    }

    enum Layout { case letters, numbers, symbols }
    var insert: (String) -> Void = { _ in }
    // The host owns the marked range. Never emulate it by deleting draft text.
    var markText: (String, NSRange) -> Void = { _, _ in }
    var unmarkText: () -> Void = {}
    var delete: () -> Void = {}
    var nextKeyboard: () -> Void = {}
    var requestAnalysis: () -> Void = {}
    var inputDidChange: () -> Void = {}
    private var lastShiftTap = Date.distantPast
    private var feedbackTask: Task<Void, Never>?

    var candidates: [String] { candidateMatches.map(\.text) }
    var isAnalyzing: Bool { phase == .recognizing || phase == .analyzing }
    var suggestion: Suggestion? {
        if case .ready(let value) = phase { return value }
        return nil
    }
    var draftImpact: DraftImpact? {
        if case .ready(let value) = draftImpactPhase { return value }
        return nil
    }
    var showsDraftImpact: Bool { draftImpactPhase != .idle }
    var currentIntimacy: Int? { intimacyAssessment?.intimacy }
    var visibleImpact: DraftImpact? {
        if showsDraftImpact { return draftImpact }
        if case .ready(let value) = recommendationImpactPhase, suggestion != nil { return value }
        return nil
    }
    var projectedIntimacy: Int? {
        guard let currentIntimacy, let delta = visibleImpact?.delta else { return nil }
        return min(100, max(0, currentIntimacy + delta))
    }
    var visibleDelta: Int? {
        guard let currentIntimacy, let projectedIntimacy else { return nil }
        return projectedIntimacy - currentIntimacy
    }
    var signedImpact: String { visibleDelta.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—" }

    func acceptAssessment(_ value: IntimacyAssessment) {
        guard value.isValid else { return }
        intimacyAssessment = value
        intimacyNeedsRefresh = false
    }

    /// A new input document must never display the previous chat's score.
    func resetIntimacy() {
        intimacyAssessment = nil
        intimacyNeedsRefresh = false
        recommendationImpactPhase = .idle
    }

    func toggleRecommendationReason() {
        guard suggestion != nil, !showsDraftImpact else { return }
        showsExplanation = false
        showsRecommendationReason.toggle()
    }

    private func dismissExplanations() {
        showsExplanation = false
        showsRecommendationReason = false
    }

    func type(_ text: String) {
        guard inputEnabled else { return }
        defer { inputDidChange() }
        feedback = nil
        let letter = text.lowercased()
        if chinese, layout == .letters,
           letter.range(of: "^[a-zü]$", options: .regularExpression) != nil || (letter == "'" && !composition.isEmpty) {
            guard composition.count < 60 else { return }
            updateComposition(composition + letter)
        } else {
            commitComposition()
            insert(uppercase ? text.uppercased() : text)
            if !capsLock { uppercase = false }
        }
    }

    func backspace() {
        guard inputEnabled else { return }
        defer { inputDidChange() }
        if composition.isEmpty { delete() } else { updateComposition(String(composition.dropLast())) }
    }

    func commitComposition(_ candidate: String? = nil) {
        guard inputEnabled, !composition.isEmpty else { return }
        if let candidate, let match = candidateMatches.first(where: { $0.text == candidate }) {
            selectCandidate(match)
            return
        }
        // Actions that leave composition mode must consume the whole input.
        // An undecodable suffix stays literal instead of being silently dropped.
        let text = candidateMatches.first(where: { $0.inputCount == composition.count })?.text ?? composition
        markText(text, NSRange(location: text.utf16.count, length: 0))
        unmarkText()
        composition = ""
        candidateMatches = []
        inputDidChange()
    }

    func selectCandidate(_ candidate: PinyinCandidate) {
        guard inputEnabled, candidateMatches.contains(candidate), !composition.isEmpty else { return }
        let remainder = String(composition.dropFirst(candidate.inputCount)).drop(while: { $0 == "'" })
        markText(candidate.text, NSRange(location: candidate.text.utf16.count, length: 0))
        unmarkText()
        composition = ""
        candidateMatches = []
        if !remainder.isEmpty { updateComposition(String(remainder)) }
        inputDidChange()
    }

    private func updateComposition(_ text: String) {
        composition = text
        candidateMatches = PinyinEngine.matches(for: text)
        markText(text, NSRange(location: text.utf16.count, length: 0))
        if text.isEmpty { unmarkText() }
    }

    /// Keep literal input on dismissal/cursor movement, without choosing a word for the user.
    func finishComposition() {
        guard !composition.isEmpty else { return }
        unmarkText()
        composition = ""
        candidateMatches = []
        inputDidChange()
    }

    /// The proxy now belongs to a different field; do not edit that field's text.
    func resetComposition() { composition = ""; candidateMatches = [] }

    func switchKeyboard() {
        finishComposition()
        nextKeyboard()
    }

    func space() {
        guard inputEnabled else { return }
        defer { inputDidChange() }
        if composition.isEmpty { insert(" ") }
        else if let candidate = candidateMatches.first { selectCandidate(candidate) }
        else { commitComposition() }
    }

    func returnKey() {
        guard inputEnabled else { return }
        defer { inputDidChange() }
        if composition.isEmpty { insert("\n") }
        else if let candidate = candidateMatches.first { selectCandidate(candidate) }
        else { commitComposition() }
    }

    func switchLanguage() {
        commitComposition()
        chinese.toggle()
    }

    func shift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
            capsLock = true
            uppercase = true
        } else {
            uppercase.toggle()
            capsLock = false
        }
        lastShiftTap = now
    }

    func useSuggestion() {
        guard let suggestion, inputEnabled else { return }
        dismissExplanations()
        // Never replace existing draft text or invoke the host app's Send action.
        commitComposition()
        insert(suggestion.text)
        inputDidChange()
        feedback = "已填入，可编辑后发送"
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }
}
