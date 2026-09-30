// swift-tools-version: 6.0
// Paquete con toda la lógica que no depende de la interfaz: se compila y se prueba
// también en Linux (CI y Claude Code). La app de iOS lo usa desde project.yml.
import PackageDescription

let package = Package(
    name: "RecuperaKit",
    defaultLocalization: "es",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
        .library(name: "HealthAPI", targets: ["HealthAPI"]),
        .library(name: "Store", targets: ["Store"]),
        .library(name: "Insights", targets: ["Insights"]),
        .library(name: "CoachKit", targets: ["CoachKit"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
        .library(name: "RunKit", targets: ["RunKit"]),
        .library(name: "FaceKit", targets: ["FaceKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "MetricsKit"),
        .target(name: "HealthAPI"),
        .target(name: "Store", dependencies: ["MetricsKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "Insights", dependencies: ["MetricsKit"]),
        .target(name: "CoachKit", dependencies: ["MetricsKit", "Insights", "Store", "RunKit"]),
        .target(name: "SyncKit", dependencies: ["MetricsKit", "HealthAPI", "Store", "Insights"]),
        .target(name: "RunKit", dependencies: ["MetricsKit", "Store"]),
        // Esferas del Apple Watch: sin dependencias, para que la app del reloj no arrastre la base de datos.
        .target(name: "FaceKit"),
        .testTarget(name: "MetricsKitTests", dependencies: ["MetricsKit"]),
        .testTarget(name: "HealthAPITests", dependencies: ["HealthAPI"]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
        .testTarget(name: "InsightsTests", dependencies: ["Insights"]),
        .testTarget(name: "CoachKitTests", dependencies: ["CoachKit", "Store", "Insights", "MetricsKit", "RunKit"]),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit"]),
        .testTarget(name: "RunKitTests", dependencies: ["RunKit", "Store", "MetricsKit"]),
        .testTarget(name: "FaceKitTests", dependencies: ["FaceKit"]),
    ]
)
