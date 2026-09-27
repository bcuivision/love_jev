import Foundation

struct ServiceSettings: Codable, Equatable {
    var endpoint = ""
    var accessToken = ""
    var analysisConsent = false
    var targetContact = ""

    var endpointURL: URL? {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        var isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
        #if DEBUG
        // Debug builds can reach the team's Mac on a private LAN; public HTTP stays blocked.
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        let isPrivateIPv4 = parts.count == 4 && octets.count == 4 && octets.allSatisfy { (0...255).contains($0) }
            && (octets[0] == 10 || (octets[0] == 192 && octets[1] == 168)
                || (octets[0] == 172 && (16...31).contains(octets[1])))
        isLocal = isLocal || host.lowercased().hasSuffix(".local") || isPrivateIPv4
        #endif
        guard url.scheme == "https" || (url.scheme == "http" && isLocal) else { return nil }
        return url
    }
    var configurationIssue: String? {
        if endpointURL == nil { return "请打开恋爱吧，连接分析服务" }
        if accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请打开恋爱吧，配置服务口令" }
        if !analysisConsent { return "请在恋爱吧开启聊天分析" }
        return nil
    }
    var isReady: Bool { configurationIssue == nil }
}

struct CaptureRequest: Codable, Equatable {
    var id = UUID().uuidString
    var requestedAt = Date()

    func isFresh(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(requestedAt)
        return age >= 0 && age < 10
    }
}

struct KeyboardPresence: Codable {
    let sessionID: String
    let isVisible: Bool
    let screenHeight: Double
    let keyboardHeight: Double
    let updatedAt: Date
    var captureRequest: CaptureRequest? = nil
    func isFresh(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(updatedAt)
        return isVisible && age >= 0 && age < 3
    }
}

struct CaptureSnapshot: Codable {
    enum Status: String, Codable { case starting, waiting, recognizing, ready, paused, stopped, unavailable }
    var status: Status
    var message: String
    var context: ChatContext?
    var updatedAt = Date()
    var requestID: String? = nil
    func isFresh(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(updatedAt)
        return age >= 0 && age < 6
    }
}

/// A click authorizes one stable capture. Heartbeats alone never authorize OCR.
struct ManualCaptureGate {
    private var requestID: String?
    private var sessionID: String?
    private var candidate: VisibleChat?
    private var completed = false

    mutating func beginFrame(_ presence: KeyboardPresence?, now: Date = Date()) -> CaptureRequest? {
        guard let presence, presence.isFresh(at: now),
              let request = presence.captureRequest, request.isFresh(at: now) else { return nil }
        if request.id != requestID || presence.sessionID != sessionID {
            requestID = request.id
            sessionID = presence.sessionID
            candidate = nil
            completed = false
        }
        return completed ? nil : request
    }

    mutating func recognize(_ chat: VisibleChat?, now: Date = Date()) -> ChatContext? {
        guard !completed, let requestID, let sessionID else { return nil }
        guard let chat, chat == candidate else {
            candidate = chat
            return nil
        }
        return ChatContext(sessionID: sessionID, revision: 1,
                           text: String(chat.messages.suffix(60).joined(separator: "\n").suffix(10_000)),
                           source: "replaykit-ocr", capturedAt: now, captureID: requestID)
    }

    mutating func finish() { completed = true; candidate = nil }
}

/// Each file has one writer. Atomic replacement prevents partial cross-process reads.
struct SharedStore {
    let root: URL?
    init(root: URL? = nil) {
        if let root { self.root = root; return }
        let group = Bundle.main.object(forInfoDictionaryKey: "LianAiAppGroup") as? String
            ?? "group.com.jevdemo.lianaiba"
        #if os(iOS)
        self.root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        #else
        self.root = nil
        #endif
    }
    var isAvailable: Bool { root != nil }
    func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = root?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url), data.count < 128_000 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func write<T: Encodable>(_ value: T, to name: String) throws {
        guard let root else { throw StoreError.unavailable }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        guard data.count < 128_000 else { throw StoreError.oversized }
        let url = root.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        var protectedURL = url
        try? protectedURL.setResourceValues(resource)
    }
    func settings() -> ServiceSettings { read("settings.json", as: ServiceSettings.self) ?? ServiceSettings() }
    enum StoreError: Error { case unavailable, oversized }
}
