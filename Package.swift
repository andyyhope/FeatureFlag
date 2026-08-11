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
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "605.0.0"),
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
