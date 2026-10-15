// swift-tools-version: 5.9
// iHearYou | Signature: i729
import PackageDescription
import Foundation
let sherpa = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor/Sherpa")

let package = Package(
    name: "iHearYou",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "iHearYou", targets: ["iHearYou"])],
    targets: [
        .target(name: "AudioDSP", path: "Sources/AudioDSP", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-I", sherpa.appendingPathComponent("include").path])],
                linkerSettings: [.unsafeFlags(["-L", sherpa.appendingPathComponent("lib").path, "-lsherpa-onnx-c-api",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", sherpa.appendingPathComponent("lib").path]), .linkedLibrary("c++")]),
        .target(name: "AudioSafety", path: "Sources/AudioSafety", publicHeadersPath: "include"),
        .executableTarget(name: "iHearYou", dependencies: ["AudioDSP", "AudioSafety"], path: "Sources/iHearYou",
                          linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("CoreAudio")]),
        .testTarget(name: "AudioDSPTests", dependencies: ["AudioDSP", "AudioSafety", "iHearYou"], path: "Tests")
    ]
)
