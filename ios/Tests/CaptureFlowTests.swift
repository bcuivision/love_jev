import XCTest
@testable import LianAiCore

final class CaptureFlowTests: XCTestCase {
    private let readySettings = ServiceSettings(endpoint: "https://example.test", accessToken: "local-test-token", analysisConsent: true)

    func testSceneFilteringRejectsGroupsAndNonChatPages() {
        func line(_ text: String, _ x: Double, _ y: Double, _ side: RecognizedChatLine.Side = .none) -> RecognizedChatLine {
            RecognizedChatLine(text: text, minX: x, maxX: x + 0.15, top: y, bottom: y + 0.025, side: side)
        }
        let messages = [line("你好", 0.7, 0.2, .me), line("今天怎么样", 0.15, 0.3, .other),
                        line("草稿不应被识别", 0.15, 0.59, .other)]
        XCTAssertEqual(ChatSceneParser.parse([line("小雨", 0.4, 0.075)] + messages, captureBottom: 0.65)?.messages,
                       ["我：你好", "对方：今天怎么样"])
        for title in ["微信", "朋友群(12)", "朋友群（12）", "群聊"] {
            XCTAssertNil(ChatSceneParser.parse([line(title, 0.4, 0.075)] + messages, captureBottom: 0.65))
        }
        XCTAssertNil(ChatSceneParser.parse([line("小雨", 0.4, 0.075)] + messages, captureBottom: 0.65, targetContact: "另一个人"))
    }

    func testStableFramesMergeOverlapButNeverMixConversations() {
        var accumulator = ChatAccumulator()
        let first = VisibleChat(title: "小雨", messages: ["我：你好", "对方：你好"])
        XCTAssertNil(accumulator.ingest(first, sessionID: "one"))
        let initial = accumulator.ingest(first, sessionID: "one")!
        XCTAssertEqual(accumulator.ingest(first, sessionID: "one")?.revision, initial.revision)
        let second = VisibleChat(title: "小雨", messages: ["对方：你好", "我：今天好吗"])
        let merged = accumulator.ingest(second, sessionID: "one")!
        XCTAssertEqual(merged.text, "我：你好\n对方：你好\n我：今天好吗")
        XCTAssertGreaterThan(merged.revision, initial.revision)
        let other = VisibleChat(title: "小明", messages: ["对方：再见", "我：拜拜"])
        XCTAssertNil(accumulator.ingest(other, sessionID: "one"))
        XCTAssertEqual(accumulator.ingest(other, sessionID: "one")?.text, other.text)
        XCTAssertNil(accumulator.ingest(first, sessionID: "two"))
        let reset = accumulator.ingest(first, sessionID: "two")!
        XCTAssertNotEqual(reset.captureID, initial.captureID)
        XCTAssertEqual(reset.sessionID, "two")
    }

    func testDiscontinuousScrollDoesNotInventChronology() {
        var accumulator = ChatAccumulator()
        let a = VisibleChat(title: "小雨", messages: ["我：你好", "对方：嗯"])
        _ = accumulator.ingest(a, sessionID: "one")
        _ = accumulator.ingest(a, sessionID: "one")
        let b = VisibleChat(title: "小雨", messages: ["我：周五呢", "对方：好呀"])
        XCTAssertEqual(accumulator.ingest(b, sessionID: "one")?.text, b.text)
    }

    func testSettingsAndStoreRoundtripWithoutInsecureRemoteEndpoint() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SharedStore(root: folder)
        try store.write(readySettings, to: "settings.json")
        XCTAssertEqual(store.settings(), readySettings)
        #if DEBUG
        XCTAssertNotNil(ServiceSettings(endpoint: "http://192.168.1.2:8787").endpointURL)
        XCTAssertNotNil(ServiceSettings(endpoint: "http://demo.local:8787").endpointURL)
        XCTAssertNotNil(ServiceSettings(endpoint: "http://172.16.1.2:8787").endpointURL)
        #else
        XCTAssertNil(ServiceSettings(endpoint: "http://192.168.1.2:8787").endpointURL)
        #endif
        XCTAssertNil(ServiceSettings(endpoint: "http://172.32.1.2:8787").endpointURL)
        XCTAssertNil(ServiceSettings(endpoint: "http://192.168.999.1:8787").endpointURL)
        XCTAssertNil(ServiceSettings(endpoint: "http://example.test:8787").endpointURL)
        XCTAssertNil(ServiceSettings(endpoint: "http://192.168.1.2.example.test:8787").endpointURL)
        XCTAssertNil(ServiceSettings(endpoint: "https://user:pass@example.test").endpointURL)
        XCTAssertNotNil(ServiceSettings(endpoint: "http://localhost:8787").endpointURL)
        XCTAssertFalse(ServiceSettings(endpoint: "https://example.test", accessToken: "token").isReady)
        XCTAssertFalse(ServiceSettings(endpoint: "https://example.test", accessToken: "   ", analysisConsent: true).isReady)
    }

    private func snapshot(_ request: CaptureRequest, sessionID: String = "one", at now: Date = Date()) -> CaptureSnapshot {
        CaptureSnapshot(status: .ready, message: "", context: ChatContext(sessionID: sessionID, revision: 1,
            text: "我：你好\n对方：今天怎么样", source: "test", capturedAt: now, captureID: request.id),
            updatedAt: now, requestID: request.id)
    }

    func testCaptureGateRequiresClickAndStopsAfterOneStableCapture() {
        let now = Date()
        var gate = ManualCaptureGate()
        var presence = KeyboardPresence(sessionID: "one", isVisible: true,
            screenHeight: 900, keyboardHeight: 340, updatedAt: now)
        for _ in 0..<100 { XCTAssertNil(gate.beginFrame(presence, now: now)) }
        let request = CaptureRequest(requestedAt: now)
        presence.captureRequest = request
        XCTAssertEqual(gate.beginFrame(presence, now: now), request)
        let chat = VisibleChat(title: "小雨", messages: ["我：你好", "对方：今天怎么样"])
        XCTAssertNil(gate.recognize(chat, now: now))
        // One unstable / unsupported frame requires two matching frames again.
        XCTAssertNil(gate.recognize(nil, now: now))
        XCTAssertNil(gate.recognize(chat, now: now))
        let context = gate.recognize(chat, now: now)
        XCTAssertEqual(context?.text, chat.text)
        XCTAssertEqual(context?.captureID, request.id)
        gate.finish()
        for _ in 0..<100 { XCTAssertNil(gate.beginFrame(presence, now: now)) }
        presence.captureRequest = CaptureRequest(requestedAt: now)
        XCTAssertNotNil(gate.beginFrame(presence, now: now))
        XCTAssertNil(gate.recognize(chat, now: now))
        XCTAssertNotNil(gate.recognize(chat, now: now))
    }

    func testCaptureGateRejectsExpiredRequestsAndInactiveKeyboard() throws {
        let now = Date()
        var gate = ManualCaptureGate()
        let request = CaptureRequest(requestedAt: now)
        let hidden = KeyboardPresence(sessionID: "one", isVisible: false,
            screenHeight: 900, keyboardHeight: 340, updatedAt: now, captureRequest: request)
        XCTAssertNil(gate.beginFrame(hidden, now: now))
        let stale = KeyboardPresence(sessionID: "one", isVisible: true,
            screenHeight: 900, keyboardHeight: 340, updatedAt: now.addingTimeInterval(-4), captureRequest: request)
        XCTAssertNil(gate.beginFrame(stale, now: now))
        let expired = KeyboardPresence(sessionID: "one", isVisible: true,
            screenHeight: 900, keyboardHeight: 340, updatedAt: now,
            captureRequest: CaptureRequest(requestedAt: now.addingTimeInterval(-11)))
        XCTAssertNil(gate.beginFrame(expired, now: now))
        XCTAssertNil(gate.beginFrame(nil, now: now))
        let data = try JSONEncoder().encode(hidden)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardPresence.self, from: data).captureRequest, request)
    }

    @MainActor func testNoClickMeansNoAnalysisEvenWithFreshSnapshots() async {
        var calls = 0
        let coordinator = AssistantCoordinator { _, _ in calls += 1; return .preview }
        let oldCapture = snapshot(CaptureRequest())
        for _ in 0..<100 { coordinator.receive(oldCapture, sessionID: "one", settings: readySettings) }
        await Task.yield()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(coordinator.captureRequest)
    }

    @MainActor func testOneClickMakesOneRequestAndKeepsResultUntilNextClick() async throws {
        var calls = 0
        var pending: CheckedContinuation<Suggestion, Error>?
        let started = expectation(description: "model started")
        let finished = expectation(description: "result visible")
        var phase = AssistantPhase.waiting
        let coordinator = AssistantCoordinator { context, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        coordinator.onPhase = {
            phase = $0
            if case .ready = $0 { finished.fulfill() }
        }
        let request = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: readySettings))
        XCTAssertEqual(phase, .recognizing)
        XCTAssertNil(coordinator.begin(sessionID: "one", settings: readySettings))
        let capture = snapshot(request)
        coordinator.receive(capture, sessionID: "one", settings: readySettings)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(phase, .analyzing)
        XCTAssertNil(coordinator.captureRequest) // OCR stops while the model works.
        XCTAssertNil(coordinator.begin(sessionID: "one", settings: readySettings))
        for _ in 0..<100 { coordinator.receive(capture, sessionID: "one", settings: readySettings) }
        let result = Suggestion(text: "推荐", intimacy: 72, explanation: "依据", isDemo: false, sessionID: "one", revision: 1)
        pending?.resume(returning: result)
        await fulfillment(of: [finished], timeout: 2)
        let later = Date().addingTimeInterval(60)
        coordinator.receive(nil, sessionID: "one", settings: readySettings, now: later)
        coordinator.receive(capture, sessionID: "one", settings: readySettings, now: later)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(phase, .ready(result))
        let next = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: readySettings))
        XCTAssertNotEqual(next.id, request.id)
        XCTAssertEqual(phase, .recognizing)
        coordinator.invalidate()
    }

    @MainActor func testStaleOrMismatchedCapturesCannotSatisfyNewClick() throws {
        let now = Date()
        var calls = 0
        let coordinator = AssistantCoordinator { _, _ in calls += 1; return .preview }
        let request = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: readySettings, now: now))
        let old = snapshot(CaptureRequest(requestedAt: now), at: now)
        coordinator.receive(old, sessionID: "one", settings: readySettings, now: now)
        let wrongChat = snapshot(request, sessionID: "other", at: now)
        coordinator.receive(wrongChat, sessionID: "one", settings: readySettings, now: now)
        let oldTime = snapshot(request, at: now.addingTimeInterval(-12))
        coordinator.receive(oldTime, sessionID: "one", settings: readySettings, now: now)
        var oldContext = snapshot(request, at: now)
        oldContext.context?.capturedAt = now.addingTimeInterval(-1)
        coordinator.receive(oldContext, sessionID: "one", settings: readySettings, now: now)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(coordinator.captureRequest, request)
        coordinator.receive(snapshot(request, at: now), sessionID: "new-document", settings: readySettings, now: now)
        XCTAssertNil(coordinator.captureRequest)
    }

    @MainActor func testCaptureTimeoutDoesNotRetryWithoutAnotherClick() throws {
        let now = Date()
        var phase = AssistantPhase.waiting
        var calls = 0
        let coordinator = AssistantCoordinator { _, _ in calls += 1; return .preview }
        coordinator.onPhase = { phase = $0 }
        let request = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: readySettings, now: now))
        coordinator.receive(nil, sessionID: "one", settings: readySettings, now: now.addingTimeInterval(10))
        guard case .unavailable = phase else { return XCTFail("Capture must time out") }
        coordinator.receive(snapshot(request), sessionID: "one", settings: readySettings)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(coordinator.captureRequest)
        XCTAssertNotNil(coordinator.begin(sessionID: "one", settings: readySettings))
    }

    @MainActor func testLateResultCannotOverwriteAnotherClickOrChat() async throws {
        var pending: [String: CheckedContinuation<Suggestion, Error>] = [:]
        let started = expectation(description: "both requests started"); started.expectedFulfillmentCount = 2
        let finished = expectation(description: "new reply appears")
        var visible: [Suggestion] = []
        let coordinator = AssistantCoordinator { context, _ in
            try await withCheckedThrowingContinuation { continuation in
                pending[context.captureID!] = continuation; started.fulfill()
            }
        }
        coordinator.onPhase = { phase in
            if case .ready(let suggestion) = phase { visible.append(suggestion); finished.fulfill() }
        }
        let first = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: readySettings))
        coordinator.receive(snapshot(first), sessionID: "one", settings: readySettings)
        while pending[first.id] == nil { await Task.yield() }
        coordinator.invalidate()
        let second = try XCTUnwrap(coordinator.begin(sessionID: "two", settings: readySettings))
        coordinator.receive(snapshot(second, sessionID: "two"), sessionID: "two", settings: readySettings)
        await fulfillment(of: [started], timeout: 2)
        for (request, session) in [(first, "one"), (second, "two")] {
            pending[request.id]?.resume(returning: Suggestion(text: session, intimacy: nil, explanation: "", isDemo: false,
                                                            sessionID: session, revision: 1))
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(visible.map(\.sessionID), ["two"])
    }

    @MainActor func testModelFailureAndWrongResponseNeverAutoRetry() async throws {
        let finished = expectation(description: "invalid model response is rejected")
        var calls = 0
        let coordinator = AssistantCoordinator { _, _ in calls += 1; return .preview }
        coordinator.onPhase = { if case .unavailable = $0 { finished.fulfill() } }
        let request = try XCTUnwrap(coordinator.begin(sessionID: "one", settings: readySettings))
        let capture = snapshot(request)
        coordinator.receive(capture, sessionID: "one", settings: readySettings)
        await fulfillment(of: [finished], timeout: 2)
        for _ in 0..<100 { coordinator.receive(capture, sessionID: "one", settings: readySettings) }
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(coordinator.begin(sessionID: "one", settings: readySettings))
    }
}
