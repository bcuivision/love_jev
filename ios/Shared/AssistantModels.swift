import Foundation

struct ChatContext: Codable, Equatable {
    var sessionID: String
    var revision: Int
    var text: String
    var source: String
    var capturedAt: Date
    var captureID: String? = nil
}

struct Suggestion: Codable, Equatable {
    var text: String
    var intimacy: Int?
    var explanation: String
    var isDemo: Bool
    var sessionID: String
    var revision: Int
    var reason: RecommendationReason? = nil

    static let preview = Suggestion(
        text: "要不要一起去之前说的那家咖啡店？",
        intimacy: 72,
        explanation: "仅依据本次可见聊天判断；期望效果不代表对方一定会这样回应。亲密度分数不代表恋爱成功率。",
        isDemo: true, sessionID: "preview", revision: 1,
        reason: RecommendationReason(
            relationshipStage: "逐渐熟悉，有进一步见面的意愿。",
            observation: "对方之前答应忙完一起去咖啡店，现在主动说想出去走走。",
            action: "顺着之前的约定，轻轻提一次邀请，让对方自由决定。",
            expectedResult: "希望确认对方是否愿意把见面的想法变成安排，也方便对方拒绝或改时间。"
        )
    )
}

struct RecommendationReason: Codable, Equatable {
    let relationshipStage: String
    let observation: String
    let action: String
    let expectedResult: String

    var isValid: Bool {
        [relationshipStage, observation, action, expectedResult].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 300
        }
    }
}

enum AssistantPhase: Equatable {
    case waiting
    case recognizing
    case analyzing
    case ready(Suggestion)
    case unavailable(String)
}

struct AssistantRequest: Encodable {
    let sessionID: String
    let revision: Int
    let context: String
    let source: String
}

struct AssistantResponse: Decodable {
    let sessionID: String
    let revision: Int
    let recommendation: String
    let intimacy: Int?
    let explanation: String
    let isDemo: Bool?
    let reason: RecommendationReason?
}

struct IntimacyAssessment: Codable, Equatable {
    let sessionID: String
    let revision: Int
    let intimacy: Int?
    let isDemo: Bool
    var isValid: Bool { intimacy.map { (0...100).contains($0) } ?? true }
}

private struct AssistantEvent: Decodable {
    let type: String
    let assessment: IntimacyAssessment?
    let result: AssistantResponse?
    let status: Int?
}

struct DraftImpact: Codable, Equatable {
    let sessionID: String
    let revision: Int
    let draftID: String
    let before: Int?
    let after: Int?
    let delta: Int?
    let explanation: String
    let isDemo: Bool

    var isValid: Bool {
        guard !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              explanation.count <= 500 else { return false }
        if before == nil, after == nil, delta == nil { return true }
        guard let before, let after, let delta else { return false }
        return !isDemo && (0...100).contains(before) && (0...100).contains(after)
            && (-12...12).contains(delta) && after - before == delta
    }
    var signedDelta: String { delta.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—" }
}

enum DraftImpactPhase: Equatable {
    case idle, composing, waiting, analyzing
    case unavailable(String)
    case ready(DraftImpact)
}

struct DraftImpactRequest: Encodable {
    let sessionID: String
    let revision: Int
    let context: String
    let source: String
    let draft: String
    let draftID: String
}

enum AssistantError: LocalizedError {
    case unconfigured, invalidResponse, staleResponse, emptyContext, server(Int)
    var errorDescription: String? {
        switch self {
        case .unconfigured: return "请先在设置 App 中配置分析服务"
        case .invalidResponse: return "分析结果暂不可用，请稍后重试"
        case .staleResponse: return "聊天已更新，正在等待最新结果"
        case .emptyContext: return "还没有可分析的聊天内容"
        case .server(let status): return "分析服务暂不可用（\(status)）"
        }
    }
}

struct AssistantClient {
    func analyzeDraft(_ draft: String, id: String, context: ChatContext, endpoint: URL, token: String) async throws -> DraftImpact {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/assistant/draft-impact"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(DraftImpactRequest(sessionID: context.sessionID,
            revision: context.revision, context: context.text, source: context.source, draft: draft, draftID: id))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.server(http.statusCode) }
        guard data.count < 16_000 else { throw AssistantError.invalidResponse }
        let result = try JSONDecoder().decode(DraftImpact.self, from: data)
        guard result.sessionID == context.sessionID, result.revision == context.revision,
              result.draftID == id else { throw AssistantError.staleResponse }
        guard result.isValid else { throw AssistantError.invalidResponse }
        return result
    }

    func analyze(_ context: ChatContext, endpoint: URL, token: String,
                 onAssessment: (@MainActor (IntimacyAssessment) -> Void)? = nil) async throws -> Suggestion {
        guard !context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantError.emptyContext
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/assistant/analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if onAssessment != nil { request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept") }
        if !token.isEmpty { request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(AssistantRequest(
            sessionID: context.sessionID, revision: context.revision,
            context: context.text, source: context.source
        ))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AssistantError.server(http.statusCode) }
        var buffer = Data()
        var received = 0
        var completed: AssistantResponse?
        let streaming = http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-ndjson") == true
        // Bound memory even if a peer sends a huge line without a newline.
        for try await byte in bytes {
            try Task.checkCancellation()
            received += 1
            guard received < 64_000 else { throw AssistantError.invalidResponse }
            if streaming, byte == 10 {
                guard !buffer.isEmpty else { continue }
                guard completed == nil else { throw AssistantError.invalidResponse }
                let event = try JSONDecoder().decode(AssistantEvent.self, from: buffer)
                buffer.removeAll(keepingCapacity: true)
                switch event.type {
                case "intimacy":
                    guard let value = event.assessment, value.isValid, !value.isDemo || value.intimacy == nil,
                          value.sessionID == context.sessionID, value.revision == context.revision else {
                        throw AssistantError.staleResponse
                    }
                    await onAssessment?(value)
                case "suggestion":
                    guard let result = event.result else { throw AssistantError.invalidResponse }
                    completed = result
                case "error": throw AssistantError.server(event.status ?? 502)
                default: throw AssistantError.invalidResponse
                }
            } else { buffer.append(byte) }
        }
        let result: AssistantResponse
        if streaming {
            guard let completed, buffer.isEmpty else { throw AssistantError.invalidResponse }
            result = completed
        } else { result = try JSONDecoder().decode(AssistantResponse.self, from: buffer) }
        guard result.sessionID == context.sessionID, result.revision == context.revision else {
            throw AssistantError.staleResponse
        }
        let reply = result.recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty, reply.count <= 300,
              result.intimacy.map({ (0...100).contains($0) }) ?? true,
              result.reason?.isValid ?? true else {
            throw AssistantError.invalidResponse
        }
        return Suggestion(text: reply, intimacy: result.intimacy,
                          explanation: result.explanation, isDemo: result.isDemo ?? false,
                          sessionID: result.sessionID, revision: result.revision, reason: result.reason)
    }
}
