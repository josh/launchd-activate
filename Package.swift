// swift-tools-version: 5.8

import PackageDescription

let package = Package(
  name: "launchd-activate",
  platforms: [
    .macOS(.v13)
  ],
  targets: [
    .executableTarget(name: "launchd-activate"),
    .testTarget(
      name: "CLITests",
      dependencies: ["launchd-activate"]
    ),
  ]
)
