import Foundation

/// Run against explicit DEMO_MODE=1 with the service token in the environment.
@main struct ServiceCheck {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["APP_ACCESS_TOKEN"], !token.isEmpty else {
            throw AssistantError.unconfigured
        }
        let endpoint = URL(string: ProcessInfo.processInfo.environment["SERVICE_URL"] ?? "http://localhost:8787")!
        let context = ChatContext(sessionID: "swift-integration", revision: 9,
            text: "我：今天忙完了吗？\n对方：刚忙完，想出去走走。", source: "test", capturedAt: Date())
        let result = try await AssistantClient().analyze(context, endpoint: endpoint, token: token)
        precondition(result.isDemo, "This check must use fixture mode")
        precondition(result.sessionID == context.sessionID && result.revision == context.revision)
        precondition(result.intimacy == nil)
        let impact = try await AssistantClient().analyzeDraft("忙了一天辛苦了", id: "swift-draft",
            context: context, endpoint: endpoint, token: token)
        precondition(impact.isDemo && impact.delta == nil && impact.before == nil && impact.after == nil)
        precondition(impact.draftID == "swift-draft" && impact.sessionID == context.sessionID)
        print("PASS: Swift HTTP client → Node service → authenticated, versioned reply and draft-impact fixtures")
    }
}
