// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "brave-container-adapter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cbc", targets: ["CBC"]),
        .executable(name: "ContainerReceiver", targets: ["ContainerReceiver"]),
        .executable(name: "ContainerSetup", targets: ["ContainerSetup"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "BraveDestinations"),
        .target(name: "AppPackaging", dependencies: ["BraveDestinations"]),
        .executableTarget(name: "CBC", dependencies: ["BraveDestinations", "AppPackaging"]),
        .executableTarget(name: "ContainerReceiver", dependencies: ["BraveDestinations"]),
        .executableTarget(name: "ContainerSetup", dependencies: [
            "BraveDestinations", "AppPackaging", .product(name: "Sparkle", package: "Sparkle"),
        ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "BraveDestinationsTests", dependencies: ["BraveDestinations", "AppPackaging"],
                    resources: [.copy("Fixtures")]),
    ]
)
