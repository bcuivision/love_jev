import XCTest
@testable import LianAiCore

final class DraftImpactTests: XCTestCase {
    private let settings = ServiceSettings(endpoint: "https://example.test", accessToken: "test-token", analysisConsent: true)
    private let context = ChatContext(sessionID: "one", revision: 3, text: "我：你好\n对方：今天好吗", source: "test", capturedAt: Date())

    private func result(_ id: String, _ context: ChatContext, delta: Int = 8) -> DraftImpact {
        DraftImpact(sessionID: context.sessionID, revision: context.revision, draftID: id,
                    before: 64, after: 64 + delta, delta: delta, explanation: "依据", isDemo: false)
    }

    @MainActor func testTypingCoalescesAndUnchangedDraftDoesNotReissue() async throws {
        let ready = expectation(description: "latest draft")
        var calls: [String] = []
        let coordinator = DraftImpactCoordinator(debounce: 0.03, minimumInterval: 0) { text, id, context, _ in
            calls.append(text); return self.result(id, context)
        }
        coordinator.onPhase = { if case .ready = $0 { ready.fulfill() } }
        for draft in ["你好", "你好呀", "你好呀，今天好吗"] {
            coordinator.update(draft: draft, composing: false, context: context, settings: settings)
        }
        await fulfillment(of: [ready], timeout: 2)
        coordinator.update(draft: calls.last, composing: false, context: context, settings: settings)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(calls, ["你好呀，今天好吗"])
    }

    @MainActor func testNoRequestsForUncommittedEmptyMissingContextOrRevokedConsent() async throws {
        var calls = 0
        var phase = DraftImpactPhase.idle
        let coordinator = DraftImpactCoordinator(debounce: 0, minimumInterval: 0) { _, id, context, _ in
            calls += 1; return self.result(id, context)
        }
        coordinator.onPhase = { phase = $0 }
        coordinator.update(draft: "nihao", composing: true, context: context, settings: settings)
        XCTAssertEqual(phase, .composing)
        coordinator.update(draft: "  ", composing: false, context: context, settings: settings)
        XCTAssertEqual(phase, .idle)
        coordinator.update(draft: "你好", composing: false, context: nil, settings: settings)
        coordinator.update(draft: nil, composing: false, context: context, settings: settings)
        var revoked = settings; revoked.analysisConsent = false
        coordinator.update(draft: "你好", composing: false, context: context, settings: revoked)
        coordinator.update(draft: "你好", composing: false, context: context, settings: settings, enabled: false)
        coordinator.update(draft: String(repeating: "🙂", count: 1001), composing: false, context: context, settings: settings)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testEditedDraftAndNewChatRejectLateResponses() async throws {
        var pending: [String: CheckedContinuation<DraftImpact, Error>] = [:]
        var ids: [String: String] = [:]
        var visible: [DraftImpact] = []
        let firstStarted = expectation(description: "first")
        let secondStarted = expectation(description: "second")
        let ready = expectation(description: "new result")
        let coordinator = DraftImpactCoordinator(debounce: 0, minimumInterval: 0) { text, id, _, _ in
            ids[text] = id
            return try await withCheckedThrowingContinuation {
                pending[text] = $0
                (text == "旧草稿" ? firstStarted : secondStarted).fulfill()
            }
        }
        var phase = DraftImpactPhase.idle
        coordinator.onPhase = {
            phase = $0
            if case .ready(let value) = $0 { visible.append(value); ready.fulfill() }
        }
        coordinator.update(draft: "旧草稿", composing: false, context: context, settings: settings)
        await fulfillment(of: [firstStarted], timeout: 2)
        var next = context; next.sessionID = "two"; next.captureID = "new-capture"
        coordinator.update(draft: "新草稿", composing: false, context: next, settings: settings)
        XCTAssertEqual(phase, .waiting)
        await fulfillment(of: [secondStarted], timeout: 2)
        pending["旧草稿"]?.resume(returning: result(ids["旧草稿"]!, context))
        pending["新草稿"]?.resume(returning: result(ids["新草稿"]!, next, delta: -8))
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(visible.map(\.sessionID), ["two"])
        coordinator.update(draft: "", composing: false, context: next, settings: settings)
        XCTAssertEqual(phase, .idle)
    }

    @MainActor func testClearingAndHidingCancelPendingAnalysis() async throws {
        for clear in [true, false] {
            let started = expectation(description: "started")
            var continuation: CheckedContinuation<DraftImpact, Error>?
            var id = ""
            var phase = DraftImpactPhase.idle
            let coordinator = DraftImpactCoordinator(debounce: 0, minimumInterval: 0) { _, requestID, _, _ in
                id = requestID
                return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
            }
            coordinator.onPhase = { phase = $0 }
            coordinator.update(draft: "你好", composing: false, context: context, settings: settings)
            await fulfillment(of: [started], timeout: 2)
            if clear { coordinator.update(draft: "", composing: false, context: context, settings: settings) }
            else { coordinator.invalidate() }
            continuation?.resume(returning: result(id, context))
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(phase, .idle)
        }
    }

    @MainActor func testMismatchedResponseFailsWithoutAutoRetry() async throws {
        let failed = expectation(description: "rejected")
        var calls = 0
        let coordinator = DraftImpactCoordinator(debounce: 0, minimumInterval: 0) { _, _, context, _ in
            calls += 1; return self.result("wrong-draft", context)
        }
        coordinator.onPhase = { if case .unavailable = $0 { failed.fulfill() } }
        coordinator.update(draft: "你好", composing: false, context: context, settings: settings)
        await fulfillment(of: [failed], timeout: 2)
        coordinator.update(draft: "你好", composing: false, context: context, settings: settings)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(calls, 1)
    }

    func testScoreContractRejectsMixedNullsBoundsInconsistentAndFakeScores() {
        func impact(_ before: Int?, _ after: Int?, _ delta: Int?, demo: Bool = false) -> DraftImpact {
            DraftImpact(sessionID: "one", revision: 1, draftID: "id", before: before, after: after,
                        delta: delta, explanation: "依据", isDemo: demo)
        }
        XCTAssertTrue(impact(64, 72, 8).isValid)
        XCTAssertTrue(impact(64, 56, -8).isValid)
        XCTAssertTrue(impact(100, 100, 0).isValid)
        XCTAssertTrue(impact(nil, nil, nil).isValid)
        XCTAssertFalse(impact(64, nil, nil).isValid)
        XCTAssertFalse(impact(64, 72, -8).isValid)
        XCTAssertFalse(impact(100, 108, 8).isValid)
        XCTAssertFalse(impact(20, 40, 20).isValid)
        XCTAssertFalse(impact(64, 72, 8, demo: true).isValid)
    }
}
