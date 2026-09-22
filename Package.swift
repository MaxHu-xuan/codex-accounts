// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexAccounts",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CodexAccounts", targets: ["CodexAccounts"])],
    targets: [
        .executableTarget(name: "CodexAccounts", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CodexAccountsTests", dependencies: ["CodexAccounts"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
