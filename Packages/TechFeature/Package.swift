// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TechFeature",
    platforms: [.iOS(.v17)],
    products: [
        // Full feature: services + section UI. Linked by the app target only.
        .library(name: "TechFeature", targets: ["TechFeature"]),
        // Snapshot types + widget views only. Linked by the widget extension.
        .library(name: "TechFeatureWidgetKit", targets: ["TechFeatureWidgetKit"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "TechFeatureWidgetKit",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .target(
            name: "TechFeature",
            dependencies: [
                "TechFeatureWidgetKit",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ],
            resources: [.process("Resources/ChipCatalog.json")]
        ),
        .testTarget(
            name: "TechFeatureTests",
            dependencies: ["TechFeature", "TechFeatureWidgetKit", .product(name: "CoreKit", package: "CoreKit")]
        )
    ]
)
