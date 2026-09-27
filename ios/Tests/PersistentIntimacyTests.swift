import XCTest
@testable import LianAiCore

final class PersistentIntimacyTests: XCTestCase {
    @MainActor func testCurrentScoreSurvivesTypingRefreshFailureAndClearing() {
        let model = KeyboardModel()
        model.phase = .ready(.preview)
        XCTAssertEqual(model.currentIntimacy, 72)
        for phase in [AssistantPhase.recognizing, .analyzing, .unavailable("服务暂不可用"), .waiting] {
            model.phase = phase
            for draftPhase in [DraftImpactPhase.composing, .waiting, .analyzing, .unavailable("失败"), .idle] {
                model.draftImpactPhase = draftPhase
                XCTAssertEqual(model.currentIntimacy, 72)
            }
        }
        XCTAssertTrue(model.intimacyNeedsRefresh)
        model.resetIntimacy()
        XCTAssertNil(model.currentIntimacy)
    }

    @MainActor func testPredictionsDoNotMutateCurrentScoreAndSwitchWithVisibleText() {
        let model = KeyboardModel()
        model.phase = .ready(.preview)
        model.recommendationImpactPhase = .ready(impact(8))
        XCTAssertEqual(model.visibleDelta, 8)
        XCTAssertEqual(model.projectedIntimacy, 80)
        XCTAssertEqual(model.currentIntimacy, 72)
        model.draftImpactPhase = .waiting
        XCTAssertNil(model.visibleDelta, "Never show a recommendation's impact against an edited draft")
        model.draftImpactPhase = .ready(impact(-9))
        XCTAssertEqual(model.visibleDelta, -9)
        XCTAssertEqual(model.projectedIntimacy, 63)
        XCTAssertEqual(model.currentIntimacy, 72)
        model.draftImpactPhase = .idle
        XCTAssertEqual(model.visibleDelta, 8)
        model.phase = .recognizing
        XCTAssertNil(model.visibleDelta, "A new recommendation must not inherit the previous delta")
        XCTAssertEqual(model.currentIntimacy, 72)
    }

    @MainActor func testUnknownAndBoundaryScoresRemainHonest() {
        let model = KeyboardModel()
        model.draftImpactPhase = .ready(impact(8))
        XCTAssertNil(model.currentIntimacy)
        XCTAssertNil(model.visibleDelta)
        model.acceptAssessment(IntimacyAssessment(sessionID: "one", revision: 1, intimacy: 98, isDemo: false))
        XCTAssertEqual(model.visibleDelta, 2)
        XCTAssertEqual(model.projectedIntimacy, 100)
        XCTAssertEqual(model.currentIntimacy, 98)
        model.acceptAssessment(IntimacyAssessment(sessionID: "one", revision: 2, intimacy: nil, isDemo: false))
        XCTAssertNil(model.currentIntimacy, "Insufficient fresh evidence must not retain an old score as current")
        XCTAssertNil(model.visibleDelta)
    }

    @MainActor func testScoreArrivesBeforeReplyAndSurvivesReplyFailure() async throws {
        let settings = ServiceSettings(endpoint: "https://example.test", accessToken: "test-token", analysisConsent: true)
        let model = KeyboardModel()
        let assessed = expectation(description: "score visible before reply")
        let failed = expectation(description: "reply failed")
        var finish: CheckedContinuation<Suggestion, Error>?
        let coordinator = AssistantCoordinator(streamAnalyze: { context, _, onAssessment in
            onAssessment(IntimacyAssessment(sessionID: context.sessionID, revision: context.revision, intimacy: 61, isDemo: false))
            return try await withCheckedThrowingContinuation { finish = $0; assessed.fulfill() }
        })
        coordinator.onAssessment = { model.acceptAssessment($0) }
        coordinator.onPhase = {
            model.phase = $0
            if case .unavailable = $0 { failed.fulfill() }
        }
        let request = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: settings))
        let context = ChatContext(sessionID: "one", revision: 1, text: "我：你好\n对方：你好", source: "test",
                                  capturedAt: Date(), captureID: request.id)
        coordinator.receive(CaptureSnapshot(status: .ready, message: "", context: context, requestID: request.id),
                            sessionID: "one", settings: settings)
        await fulfillment(of: [assessed], timeout: 2)
        XCTAssertEqual(model.phase, .analyzing)
        XCTAssertEqual(model.currentIntimacy, 61)
        XCTAssertNil(model.suggestion)
        finish?.resume(throwing: AssistantError.server(502))
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(model.currentIntimacy, 61)
    }

    @MainActor func testLateStreamedScoreCannotLeakIntoNewChat() async throws {
        let started = expectation(description: "request started")
        let settings = ServiceSettings(endpoint: "https://example.test", accessToken: "test-token", analysisConsent: true)
        var callback: (@MainActor (IntimacyAssessment) -> Void)?
        var finish: CheckedContinuation<Suggestion, Error>?
        var scores: [IntimacyAssessment] = []
        let coordinator = AssistantCoordinator(streamAnalyze: { _, _, onAssessment in
            callback = onAssessment
            return try await withCheckedThrowingContinuation { finish = $0; started.fulfill() }
        })
        coordinator.onAssessment = { scores.append($0) }
        let request = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: settings))
        let context = ChatContext(sessionID: "one", revision: 1, text: "我：你好\n对方：你好", source: "test",
                                  capturedAt: Date(), captureID: request.id)
        coordinator.receive(CaptureSnapshot(status: .ready, message: "", context: context, requestID: request.id),
                            sessionID: "one", settings: settings)
        await fulfillment(of: [started], timeout: 2)
        coordinator.invalidate()
        callback?(IntimacyAssessment(sessionID: "one", revision: 1, intimacy: 88, isDemo: false))
        finish?.resume(throwing: CancellationError())
        await Task.yield()
        XCTAssertTrue(scores.isEmpty)
    }

    private func impact(_ delta: Int) -> DraftImpact {
        DraftImpact(sessionID: "preview", revision: 1, draftID: "test", before: 64, after: 64 + delta,
                    delta: delta, explanation: "测试影响", isDemo: false)
    }
}
