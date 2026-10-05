// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudentFeature",
    platforms: [.iOS(.v17)],
    products: [
        // Full feature: services + section UI. Linked by the app target only.
        .library(name: "StudentFeature", targets: ["StudentFeature"]),
        // Snapshot types + widget views only. Linked by the widget extension.
        .library(name: "StudentFeatureWidgetKit", targets: ["StudentFeatureWidgetKit"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "StudentFeatureWidgetKit",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .target(
            name: "StudentFeature",
            dependencies: [
                "StudentFeatureWidgetKit",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(
            name: "StudentFeatureTests",
            dependencies: ["StudentFeature"]
        )
    ]
)
