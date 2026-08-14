// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "FeatureFlag",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "FeatureFlag", targets: ["FeatureFlag"]),
        .library(name: "FeatureFlagUI", targets: ["FeatureFlagUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "606.0.0"),
        // Build-time only: `swift package generate-documentation`, and how Swift Package
        // Index builds the hosted documentation. Nothing links it at runtime.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.3"),
    ],
    targets: [
        .macro(
            name: "FeatureFlagMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "FeatureFlag",
            dependencies: ["FeatureFlagMacros"]
        ),
        .target(
            name: "FeatureFlagUI",
            dependencies: ["FeatureFlag"]
        ),
        // Built but not shipped, so the example sources cannot silently rot. Only the
        // two @main entry points are excluded — those need real Xcode app targets.
        .target(
            name: "DemoExamples",
            dependencies: ["FeatureFlag", "FeatureFlagUI"],
            path: "Examples",
            exclude: [
                "README.md",
                "project.yml",
                "Screenshots",
                "FeatureFlagExamples.xcodeproj",
                "DemoApp/DemoApp.entitlements",
                "DemoCompanion/DemoCompanion.entitlements",
                "DemoApp/DemoApp.swift",
                "DemoCompanion/DemoCompanionApp.swift",
            ]
        ),
        .testTarget(
            name: "DemoExamplesTests",
            dependencies: ["DemoExamples", "FeatureFlag"]
        ),
        .testTarget(
            name: "FeatureFlagTests",
            dependencies: ["FeatureFlag"]
        ),
        .testTarget(
            name: "FeatureFlagMacroTests",
            dependencies: [
                "FeatureFlagMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "FeatureFlagUITests",
            dependencies: ["FeatureFlagUI"]
        ),
    ]
)
