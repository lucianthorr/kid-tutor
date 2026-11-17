// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidTutorKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KidTutorKit", targets: ["KidTutorKit"]),
        .executable(name: "kidtutor-export", targets: ["kidtutor-export"]),
    ],
    targets: [
        .target(name: "KidTutorKit"),
        .executableTarget(name: "kidtutor-export", dependencies: ["KidTutorKit"]),
        .testTarget(name: "KidTutorKitTests", dependencies: ["KidTutorKit"]),
    ]
)
