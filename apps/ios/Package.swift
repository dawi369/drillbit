// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DrillbitCore", platforms: [.macOS(.v15)],
  products: [.library(name: "DrillbitCore", targets: ["DrillbitCore"])],
  targets: [
    .target(
      name: "DrillbitCore", path: ".",
      exclude: [
        "Config", "Drillbit/Assets.xcassets", "Tests", "DrillbitWidget", "Drillbit.xcodeproj",
        "project.yml", "build", "Shared/SharedStore.swift", "Drillbit/APIClient.swift",
        "Drillbit/AppModel.swift", "Drillbit/DrillbitApp.swift", "Drillbit/MemorySettings.swift",
        "Drillbit/Views.swift",
      ], sources: ["Shared/Models.swift", "Shared/VoiceTranscript.swift", "Drillbit/Persistence.swift", "Drillbit/CompanionCoordinator.swift"]),
    .testTarget(name: "DrillbitCoreTests", dependencies: ["DrillbitCore"], path: "Tests"),
  ])
