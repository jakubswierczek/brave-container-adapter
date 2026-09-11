// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "choosy-brave-containers",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cbc", targets: ["CBC"]),
        .executable(name: "ContainerReceiver", targets: ["ContainerReceiver"]),
        .executable(name: "ContainerSetup", targets: ["ContainerSetup"]),
    ],
    targets: [
        .target(name: "BraveDestinations"),
        .target(name: "AppPackaging", dependencies: ["BraveDestinations"]),
        .executableTarget(name: "CBC", dependencies: ["BraveDestinations", "AppPackaging"]),
        .executableTarget(name: "ContainerReceiver", dependencies: ["BraveDestinations"]),
        .executableTarget(name: "ContainerSetup", dependencies: ["BraveDestinations", "AppPackaging"]),
        .testTarget(name: "BraveDestinationsTests", dependencies: ["BraveDestinations", "AppPackaging"],
                    resources: [.copy("Fixtures")]),
    ]
)
