import Foundation

struct RecognizedChatLine: Equatable {
    enum Side: String { case me, other, none }
    var text: String
    var minX: Double
    var maxX: Double
    var top: Double
    var bottom: Double
    var side: Side
}

struct VisibleChat: Equatable {
    let title: String
    let messages: [String]
    var text: String { messages.joined(separator: "\n") }
}

enum ChatSceneParser {
    static let nonChatTitles: Set<String> = ["微信", "通讯录", "发现", "我", "设置", "聊天信息", "朋友圈", "支付", "服务", "搜索", "恋爱吧", "通知中心", "屏幕广播", "屏幕录制"]

    static func parse(_ lines: [RecognizedChatLine], captureBottom: Double, targetContact: String = "") -> VisibleChat? {
        let headers = lines.filter {
            $0.top > 0.045 && $0.bottom < 0.16 && $0.minX > 0.17 && $0.maxX < 0.83
        }.sorted { $0.top < $1.top }
        guard let header = headers.first(where: {
            let value = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && value.count < 40 && !nonChatTitles.contains(value)
                && value.range(of: "^[0-9:： .]+$", options: .regularExpression) == nil
        }) else { return nil }
        let title = header.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Group-count titles and obvious group headers are not supported.
        guard title.range(of: "[（(][0-9]+[)）]$", options: .regularExpression) == nil,
              !title.contains("群聊"), targetContact.isEmpty || title == targetContact else { return nil }
        let body = lines.filter {
            $0.top > max(0.14, header.bottom + 0.025) && $0.bottom < captureBottom - 0.065
                && $0.side != .none && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { abs($0.top - $1.top) > 0.008 ? $0.top < $1.top : $0.minX < $1.minX }
        guard body.count >= 2, body.contains(where: { $0.side == .other }) else { return nil }
        let messages = body.map { "\($0.side == .me ? "我" : "对方")：\($0.text)" }
        return VisibleChat(title: title, messages: messages)
    }
}

struct ChatAccumulator {
    private(set) var sessionID: String?
    private var pendingTitle: String?
    private var lastVisible: VisibleChat?
    private var revision = 0
    private var generation = UUID().uuidString
    private var messages: [String] = []

    mutating func reset() {
        sessionID = nil; pendingTitle = nil; lastVisible = nil; revision = 0; messages = []
        generation = UUID().uuidString
    }

    /// Requires the same header on two frames; history merges only where adjacent frames overlap.
    mutating func ingest(_ chat: VisibleChat, sessionID: String, now: Date = Date()) -> ChatContext? {
        if self.sessionID != sessionID { reset(); self.sessionID = sessionID }
        if pendingTitle != chat.title {
            pendingTitle = chat.title; lastVisible = nil; messages = []; revision += 1
            return nil
        }
        if lastVisible != chat {
            if messages.isEmpty { messages = chat.messages }
            else {
                let limit = min(messages.count, chat.messages.count)
                var overlap = 0
                if limit > 0 {
                    for count in stride(from: limit, through: 1, by: -1) {
                        if Array(messages.suffix(count)) == Array(chat.messages.prefix(count)) { overlap = count; break }
                    }
                }
                if overlap > 0 { messages += chat.messages.dropFirst(overlap) }
                else { messages = chat.messages } // Discontinuous scroll: don't invent chronology.
            }
            messages = Array(messages.suffix(60))
            lastVisible = chat
            revision += 1
        }
        return ChatContext(sessionID: sessionID, revision: revision,
                           text: String(messages.joined(separator: "\n").suffix(10_000)),
                           source: "replaykit-ocr", capturedAt: now, captureID: generation)
    }
}
