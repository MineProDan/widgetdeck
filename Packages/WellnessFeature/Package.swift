// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WellnessFeature",
    platforms: [.iOS(.v17)],
    products: [
        // Full feature: services + section UI. Linked by the app target only.
        .library(name: "WellnessFeature", targets: ["WellnessFeature"]),
        // Snapshot types + widget views only. Linked by the widget extension.
        .library(name: "WellnessFeatureWidgetKit", targets: ["WellnessFeatureWidgetKit"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "WellnessFeatureWidgetKit",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ],
            // Bundled so widgets can pick the daily quote/affirmation offline (no snapshot needed).
            resources: [.process("Resources/quotes.json"), .process("Resources/affirmations.json")]
        ),
        .target(
            name: "WellnessFeature",
            dependencies: [
                "WellnessFeatureWidgetKit",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(
            name: "WellnessFeatureTests",
            dependencies: ["WellnessFeature", "WellnessFeatureWidgetKit"]
        )
    ]
)
