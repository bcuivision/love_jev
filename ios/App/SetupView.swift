import SwiftUI
import ReplayKit

struct SetupView: View {
    @State private var preview = false
    @State private var testDraft = ""
    @State private var settings = SharedStore().settings()
    @State private var status = "尚未启动屏幕广播"
    @State private var saveError: String?
    @State private var connectionStatus = "尚未检查连接"
    @State private var checkingConnection = false
    @State private var testRecommendation: String?
    private let store = SharedStore()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 31)).foregroundStyle(.blue)
                        Text("让下一句话，自然一点。")
                            .font(.system(size: 25, weight: .semibold))
                        Text("开启屏幕广播，回到微信。点星光识别聊天后，输入草稿就能预估亲密度加减分：暖色升温，蓝色降温。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                    Button { preview = true } label: { Label("预览键盘交互", systemImage: "keyboard") }
                        .accessibilityIdentifier("openPreview")
                }
                Section("启用键盘") {
                    Label("设置 → 通用 → 键盘 → 键盘", systemImage: "1.circle")
                    Label("添加新键盘 → 恋爱吧", systemImage: "2.circle")
                    Label("打开「允许完全访问」", systemImage: "3.circle")
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("在微信输入框长按地球图标，切换到「恋爱吧」。完全访问用于联网和扩展之间共享数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    HStack(spacing: 16) {
                        BroadcastPicker().frame(width: 48, height: 48)
                            .disabled(!settings.isReady || !store.isAvailable)
                            .opacity(settings.isReady && store.isAvailable ? 1 : 0.3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("开始屏幕广播")
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text("在系统面板确认后回到微信，展开恋爱吧键盘，点星光按钮开始一次分析。录屏状态会一直可见；结束时从系统状态栏或控制中心停止。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !store.isAvailable {
                        Label("共享数据不可用，请为三个 Target 配置同一 App Group。", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Toggle("允许分析当前聊天文字", isOn: $settings.analysisConsent)
                        .accessibilityIdentifier("analysisConsent")
                    Text("本键盘展开且你点星光后，会识别一次可见聊天。随后停笔时，未发送草稿会与本次聊天一起交给配置的服务及 Jev 预估；回复推荐使用 GPT / Jev。不上传录屏视频，不保存草稿。关闭此开关可停止分析。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("聊天辅助") }
                Section {
                    LabeledContent("服务状态", value: connectionStatus)
                    Button {
                        Task { await checkConnection(testReply: true) }
                    } label: {
                        HStack {
                            Text("测试服务连接")
                            if checkingConnection { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(checkingConnection || settings.endpointURL == nil || settings.accessToken.isEmpty)
                    .accessibilityIdentifier("checkServiceConnection")
                    if let testRecommendation {
                        Text("测试推荐：\(testRecommendation)").font(.subheadline)
                    }
                    DisclosureGroup("连接设置") {
                        TextField("分析服务地址", text: $settings.endpoint)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("serviceEndpoint")
                        SecureField("服务访问口令", text: $settings.accessToken)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    TextField("可选：只分析此联系人", text: $settings.targetContact)
                        .autocorrectionDisabled()
                    if !settings.endpoint.isEmpty && settings.endpointURL == nil {
                        Text("请输入有效的分析服务地址。调试版本也支持同一 Wi-Fi 下的 Mac 地址。")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    Text("本地演示时，请让手机与 Mac 连接同一 Wi-Fi，并保持 Mac 服务运行。测试连接使用一段虚构对话，不读取当前聊天。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                } header: { Text("连接分析服务") }
                Section("键盘测试") {
                    TextField("点这里测试已启用的键盘", text: $testDraft, axis: .vertical)
                        .lineLimit(2...4).accessibilityIdentifier("keyboardTestField")
                    Text("当前拼音为基础离线词库。完整中文输入可用地球键切换系统键盘。预览中的聊天与分数均为示例。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("恋爱吧")
            .fullScreenCover(isPresented: $preview) { ConversationPreview(initiallyReady: false) }
            .onChange(of: settings) { _, value in
                do { try store.write(value, to: "settings.json"); saveError = nil }
                catch { saveError = "设置未保存，请检查 App Group 签名配置。" }
            }
            .task {
                importLocalConnection()
                recordConnectionCheck(ok: false)
                if settings.endpointURL != nil && !settings.accessToken.isEmpty {
                    await checkConnection(testReply: ProcessInfo.processInfo.arguments.contains("--verify-service"))
                }
                while !Task.isCancelled {
                    if let snapshot = store.read("capture.json", as: CaptureSnapshot.self), snapshot.isFresh() {
                        status = snapshot.message
                    } else { status = "尚未启动屏幕广播" }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func importLocalConnection() {
        #if DEBUG
        // Delivered into the app's private container by the local setup script, never bundled model keys.
        let file = URL.documentsDirectory.appendingPathComponent("local-service.json")
        guard let data = try? Data(contentsOf: file), data.count < 16_000,
              let connection = try? JSONDecoder().decode(LocalConnection.self, from: data) else { return }
        var updated = settings
        updated.endpoint = connection.endpoint
        updated.accessToken = connection.accessToken
        guard updated.endpointURL != nil, updated.accessToken.count >= 24 else {
            saveError = "本地连接配置无效"; return
        }
        do {
            try store.write(updated, to: "settings.json")
            settings = updated
            try? FileManager.default.removeItem(at: file)
            saveError = nil
        } catch { saveError = "连接配置未保存，请检查 App Group 签名" }
        #endif
    }

    @MainActor private func checkConnection(testReply: Bool) async {
        guard !checkingConnection, let endpoint = settings.endpointURL else { return }
        checkingConnection = true
        connectionStatus = "正在连接…"
        testRecommendation = nil
        defer { checkingConnection = false }
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: endpoint.appendingPathComponent("health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AssistantError.invalidResponse }
            let health = try JSONDecoder().decode(ServiceHealth.self, from: data)
            guard health.status == "ready" else {
                connectionStatus = "已连接，后端尚未配置模型"
                recordConnectionCheck(ok: false); return
            }
            connectionStatus = health.mode == "fixture" ? "已连接 · 示例服务"
                : health.analysisMode == "reply_only" ? "已连接 · 仅回复推荐" : "已连接 · 回复与亲密度"
            if testReply {
                let context = ChatContext(sessionID: "connection-\(UUID().uuidString)", revision: 1,
                    text: "我：周末准备做什么？\n对方：想去公园散步，最近天气挺好。",
                    source: "test", capturedAt: Date())
                let reply = try await AssistantClient().analyze(context, endpoint: endpoint, token: settings.accessToken)
                testRecommendation = reply.text
                connectionStatus = reply.isDemo ? "示例联调通过 · 未调用模型" : "真实推荐测试通过"
            }
            recordConnectionCheck(ok: true)
        } catch {
            if let error = error as? AssistantError { connectionStatus = error.errorDescription ?? "连接失败" }
            else { connectionStatus = "无法连接，请检查 Wi-Fi、本地网络权限和 Mac 服务" }
            recordConnectionCheck(ok: false)
        }
    }

    private func recordConnectionCheck(ok: Bool) {
        #if DEBUG
        // Status only, for device-side diagnostics. No tokens or chat transcripts.
        let result: [String: Any] = ["ok": ok, "status": connectionStatus,
            "hasTestRecommendation": testRecommendation != nil, "analysisConsent": settings.analysisConsent,
            "hasEndpoint": settings.endpointURL != nil, "hasAccessToken": !settings.accessToken.isEmpty,
            "sharedStoreAvailable": store.isAvailable, "settingsSaved": store.settings() == settings,
            "timestamp": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("local-service-check.json"), options: .atomic)
        }
        #endif
    }
}

private struct LocalConnection: Decodable { let endpoint: String; let accessToken: String }
private struct ServiceHealth: Decodable { let status: String; let mode: String; let analysisMode: String? }

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        picker.showsMicrophoneButton = false
        picker.preferredExtension = Bundle.main.bundleIdentifier.map { $0 + ".broadcast" }
        picker.accessibilityLabel = "打开恋爱吧系统屏幕广播"
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.isUserInteractionEnabled = context.environment.isEnabled
    }
}
