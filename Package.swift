// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Semaphore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "Semaphore", targets: ["Semaphore"]),
        .library(name: "SemaphoreUI", targets: ["SemaphoreUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "605.0.0"),
    ],
    targets: [
        .macro(
            name: "SemaphoreMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Semaphore",
            dependencies: ["SemaphoreMacros"]
        ),
        .target(
            name: "SemaphoreUI",
            dependencies: ["Semaphore"]
        ),
        .testTarget(
            name: "SemaphoreTests",
            dependencies: ["Semaphore"]
        ),
        .testTarget(
            name: "SemaphoreMacroTests",
            dependencies: [
                "SemaphoreMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "SemaphoreUITests",
            dependencies: ["SemaphoreUI"]
        ),
    ]
)
