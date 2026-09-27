import SwiftUI

@main
struct LianAiBaApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains(where: { ["--preview-ready", "--preview-warm", "--preview-cold", "--preview-neutral"].contains($0) }) {
                ConversationPreview(initiallyReady: true)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-loading") {
                ConversationPreview(initiallyReady: false, holdLoading: true)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-idle") {
                ConversationPreview(initiallyReady: false)
            } else {
                SetupView()
            }
        }
    }
}
