// swift-tools-version: 6.4
// NovelCore: 데이터 모델, 파일 읽기·쓰기, 검색, 글자 수, 스냅샷. Foundation만 쓴다.
import PackageDescription

let package = Package(
  name: "NovelCore",
  // iOS도 넣어 두면 macOS 전용 API가 섞였을 때 바로 컴파일 오류로 알 수 있다.
  platforms: [.macOS(.v27), .iOS(.v27)],
  products: [
    .library(name: "NovelCore", targets: ["NovelCore"])
  ],
  targets: [
    .target(name: "NovelCore"),
    .testTarget(name: "NovelCoreTests", dependencies: ["NovelCore"]),
  ]
)
