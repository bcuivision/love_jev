// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LianAiCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LianAiCore", targets: ["LianAiCore"])],
    targets: [
        .target(name: "LianAiCore", path: "ios/Shared", exclude: ["KeyboardSurface.swift"],
                sources: ["AssistantModels.swift", "KeyboardModel.swift", "PinyinEngine.swift",
                          "SharedStore.swift", "ChatScene.swift", "AssistantCoordinator.swift"],
                resources: [.process("Resources")]),
        .testTarget(name: "LianAiCoreTests", dependencies: ["LianAiCore"], path: "ios/Tests")
    ],
    swiftLanguageModes: [.v5]
)
