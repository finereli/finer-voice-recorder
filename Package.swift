// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "VoiceRecorder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "VoiceRecorder", path: "Sources/VoiceRecorder")
    ]
)
