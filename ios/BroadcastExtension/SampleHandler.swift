import ReplayKit
import CoreMedia
import ImageIO

final class SampleHandler: RPBroadcastSampleHandler {
    private let store = SharedStore()
    private let recognizer = FrameRecognizer()
    private var captureGate = ManualCaptureGate()
    private var lastFrame = Date.distantPast
    private var lastIdleHeartbeat = Date.distantPast
    private var running = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard store.isAvailable, store.settings().isReady else {
            finishBroadcastWithError(NSError(domain: "LianAiBroadcast", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请先在恋爱吧中配置分析服务并启用聊天分析；若共享数据不可用，请检查三个 Target 的 App Group 签名。 "]))
            return
        }
        running = true
        captureGate = ManualCaptureGate()
        publish(.starting, "广播已启动，回到微信，点键盘上的星光按钮分析")
    }

    override func broadcastPaused() {
        running = false
        captureGate.finish()
        publish(.paused, "系统广播已暂停，请恢复后重新点星光按钮", requestID: currentRequestID)
    }
    override func broadcastResumed() {
        running = true
        publish(.waiting, "点星光按钮识别当前聊天")
    }
    override func broadcastFinished() {
        running = false
        captureGate.finish()
        publish(.stopped, "屏幕广播已停止", requestID: currentRequestID)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // No audio processing. Idle frames only check for a user-created request; they never run Vision.
        guard running, sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= 0.6 else { return }
        lastFrame = now
        let presence = store.read("keyboard.json", as: KeyboardPresence.self)
        guard let request = captureGate.beginFrame(presence, now: now), let presence else {
            // Keep a completed capture until the keyboard consumes it. A heartbeat must not overwrite it.
            if let presence, presence.isFresh(at: now), let request = presence.captureRequest,
               request.isFresh(at: now) { return }
            if now.timeIntervalSince(lastIdleHeartbeat) >= 2 {
                lastIdleHeartbeat = now
                publish(.waiting, "点星光按钮识别当前聊天")
            }
            return
        }
        let settings = store.settings()
        guard settings.isReady else {
            captureGate.finish()
            publish(.unavailable, "聊天分析已关闭，请重新配置", requestID: request.id)
            return
        }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), presence.screenHeight > 0 else { return }
        let rawOrientation = (CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                              attachmentModeOut: nil) as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let bottom = min(0.90, max(0.35, 1 - presence.keyboardHeight / presence.screenHeight))
        autoreleasepool {
            do {
                let lines = try recognizer.recognize(buffer, orientation: orientation, captureBottom: bottom)
                let chat = ChatSceneParser.parse(lines, captureBottom: bottom, targetContact: settings.targetContact)
                let context = captureGate.recognize(chat)
                // OCR must belong to this click and this input document, even if the user switched mid-frame.
                guard let latest = store.read("keyboard.json", as: KeyboardPresence.self),
                      latest.isFresh(), latest.sessionID == presence.sessionID,
                      latest.captureRequest?.id == request.id, request.isFresh(),
                      store.settings() == settings else { captureGate.finish(); return }
                guard let context else {
                    publish(.recognizing, "正在识别当前聊天…", requestID: request.id)
                    return
                }
                try store.write(CaptureSnapshot(status: .ready, message: "本次聊天识别完成", context: context,
                                                requestID: request.id), to: "capture.json")
                captureGate.finish()
            } catch {
                captureGate.finish()
                publish(.unavailable, "画面暂时无法识别，请回到文字聊天后重试", requestID: request.id)
            }
        }
    }

    private var currentRequestID: String? {
        store.read("keyboard.json", as: KeyboardPresence.self)?.captureRequest?.id
    }

    private func publish(_ status: CaptureSnapshot.Status, _ message: String, requestID: String? = nil) {
        try? store.write(CaptureSnapshot(status: status, message: message, context: nil,
                                       requestID: requestID), to: "capture.json")
    }
}
