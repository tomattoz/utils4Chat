// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Utils9Chat",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Utils9Chat", targets: ["Utils9Chat"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tomattoz/utils", branch: "master"),
        .package(url: "https://github.com/tomattoz/utils4Client", branch: "master"),
        .package(url: "https://github.com/tomattoz/utils4AdapterAI", branch: "master"),
        .package(url: "https://github.com/tomattoz/utils4AsyncHttpClient", branch: "master"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "1.0.0"),
        .package(url: "https://github.com/loopwerk/Parsley", branch: "main"),
    ],
    targets: [
        .target(name: "Utils9Chat",
                dependencies: [
                    .product(name: "Utils9", package: "utils"),
                    .product(name: "Utils9AIAdapter", package: "utils4AdapterAI"),
                    .product(name: "Utils9AsyncHttpClient", package: "utils4AsyncHttpClient"),
                    .product(name: "Utils9Client", package: "utils4Client"),
                    .product(name: "SwiftUIIntrospect", package: "SwiftUI-Introspect"),
                    .product(name: "Parsley", package: "Parsley"),
                ],
                path: "Sources",
                resources: [
                    .process("DataBase/DataBase.xcdatamodeld")
                ])
    ]
)

