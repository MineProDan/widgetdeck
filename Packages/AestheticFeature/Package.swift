// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AestheticFeature",
    platforms: [.iOS(.v17)],
    products: [
        // Full feature: services + section UI. Linked by the app target only.
        .library(name: "AestheticFeature", targets: ["AestheticFeature"]),
        // Snapshot types + widget views only. Linked by the widget extension.
        .library(name: "AestheticFeatureWidgetKit", targets: ["AestheticFeatureWidgetKit"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "AestheticFeatureWidgetKit",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .target(
            name: "AestheticFeature",
            dependencies: [
                "AestheticFeatureWidgetKit",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(
            name: "AestheticFeatureTests",
            dependencies: ["AestheticFeature"]
        )
    ]
)
