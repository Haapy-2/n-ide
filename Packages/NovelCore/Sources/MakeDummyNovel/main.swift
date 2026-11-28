// Creates a Korean dummy project for performance measurement.
// Usage: make-dummy-novel <project folder path> [episodes=500] [long episodes=10] [short episode chars=300]
// The leading "long episodes" are 5,000 chars, the rest short. For all 5,000 chars, pass long episodes equal to episodes.
// The same arguments always produce the same content (to keep measurement conditions identical).
import Foundation
import NovelCore

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
  print("사용법: make-dummy-novel <작품 폴더 경로> [회차 수=500] [긴 회차 수=10] [짧은 회차 글자 수=300]")
  exit(1)
}
let root = URL(filePath: arguments[1], directoryHint: .isDirectory)
let episodeCount = arguments.count > 2 ? Int(arguments[2]) ?? 500 : 500
let longEpisodeCount = arguments.count > 3 ? Int(arguments[3]) ?? 10 : 10
let shortEpisodeLength = arguments.count > 4 ? Int(arguments[4]) ?? 300 : 300
let longEpisodeLength = 5_000

struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return state
  }
}

let words = [
  "그는", "그녀는", "검을", "들었다", "비가", "내렸다", "골목에서", "조용히", "바라보았다", "달빛이",
  "창문", "너머로", "스며들었다", "오래된", "기억이", "떠올랐다", "숨을", "골랐다", "발걸음을", "멈췄다",
  "하늘은", "잿빛이었다", "손끝이", "떨렸다", "이번에는", "다르다", "누군가", "문을", "두드렸다", "대답은",
  "없었다", "바람이", "불었다", "칼날이", "번뜩였다", "마을", "사람들은", "수군거렸다", "아무도", "몰랐다",
]
let lines = ["\"여기서 뭐 해요?\"", "\"늦었군.\"", "\"다시는 그러지 마.\"", "\"약속했잖아.\""]

func makeEpisodeText(seed: UInt64, length charactersPerEpisode: Int) -> String {
  var random = SeededGenerator(state: seed)
  var text = ""
  var length = 0  // Counted separately since recounting text.count each time is slow
  func append(_ piece: String) {
    text += piece
    length += piece.count
  }
  var sentenceWords = 0
  while length < charactersPerEpisode {
    if sentenceWords == 0, Int.random(in: 0..<6, using: &random) == 0 {
      append(lines.randomElement(using: &random)! + "\n\n")
      continue
    }
    append(words.randomElement(using: &random)!)
    sentenceWords += 1
    if sentenceWords >= Int.random(in: 5...12, using: &random) {
      append(Int.random(in: 0..<3, using: &random) == 0 ? ".\n\n" : ". ")
      sentenceWords = 0
    } else {
      append(" ")
    }
  }
  return String(text.prefix(charactersPerEpisode))
}

do {
  if FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
    try FileManager.default.removeItem(at: root)
  }
  let store = try ProjectStore.create(at: root, title: root.deletingPathExtension().lastPathComponent)
  var project = try store.loadProject()
  project.episodes = (1...episodeCount).map { EpisodeMeta(id: EpisodeID(rawValue: String(format: "dummy-%04d", $0)), title: "\($0)화", goal: 5_000) }
  for index in project.episodes.indices {
    let length = index < longEpisodeCount ? longEpisodeLength : shortEpisodeLength
    let text = makeEpisodeText(seed: UInt64(index + 1), length: length)
    try store.writeEpisode(text, id: project.episodes[index].id)
    // Counts are put into project.json just as the app saves them (the sidebar shows them without reading bodies).
    project.episodes[index].characterCount = CharacterCount(counting: text)
  }
  try store.saveProject(project)
  print("✓ \(episodeCount)회차 더미 작품 (앞 \(longEpisodeCount)화 \(longEpisodeLength)자, 나머지 \(shortEpisodeLength)자): \(root.path(percentEncoded: false))")
} catch {
  print("✗ 더미 작품을 만들지 못함: \(error)")
  exit(1)
}
