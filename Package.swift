// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InputPilot",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "InputPilot", targets: ["InputPilot"])],
    targets: [
        .target(name: "InputPilotCore"),
        .executableTarget(name: "InputPilot", dependencies: ["InputPilotCore"]),
        .testTarget(name: "InputPilotCoreTests", dependencies: ["InputPilotCore", "InputPilot"])
    ]
)
