// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OneRead", platforms: [.macOS(.v14)], products: [.executable(name: "OneRead", targets: ["OneRead"])], targets: [.executableTarget(name: "OneRead", resources: [.copy("AppIcon.png"), .copy("AppIcon.icns"), .copy("Reader.html"), .copy("ReaderScroll.js"), .copy("EconomistCatalogSeed.json"), .copy("MagazineCatalogSeeds.json"), .copy("ExamVocabulary.json"), .copy("ExamWordListNotices")], swiftSettings: [.swiftLanguageMode(.v5)])])
