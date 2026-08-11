// swift-tools-version: 5.9
import PackageDescription

// 同步逻辑单独做成 library target，目的是能在 Mac 上直接 `swift test` 跑
// MyNASSyncTests，不需要建 Xcode 工程、不需要 tvOS 模拟器。
// tvOS app 本体（MyNASTV/）在 Xcode 里以本地 package 依赖的方式引用 MyNASSync。
//
// macOS 平台声明只为了跑测试；库本身只用 Foundation，不含任何 tvOS 专有 API。
let package = Package(
    name: "MyNASSync",
    platforms: [
        .tvOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MyNASSync", targets: ["MyNASSync"]),
    ],
    targets: [
        .target(name: "MyNASSync"),
        .testTarget(name: "MyNASSyncTests", dependencies: ["MyNASSync"]),
    ]
)
