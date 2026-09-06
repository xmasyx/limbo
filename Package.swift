// swift-tools-version: 6.0
import PackageDescription

// Limbo — quello che stai spostando, mentre lo sposti. macOS, Apple Silicon.
//
// Nessuna dipendenza, ed è una scelta che si difende: gli appunti sono
// NSPasteboard, il deposito è il filesystem, la condivisione è
// NSSharingService, la conversione è ImageIO + AVFoundation + PDFKit. Tutto
// già nel sistema. Una libreria in più qui sarebbe peso senza ricavo.
let package = Package(
    name: "Limbo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Limbo", targets: ["Limbo"])
    ],
    targets: [
        .executableTarget(
            name: "Limbo",
            path: "Sources/Limbo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LimboTests",
            dependencies: ["Limbo"],
            path: "Tests/LimboTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
