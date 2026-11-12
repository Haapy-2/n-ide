// 성능 측정용 한국어 더미 작품을 만든다.
// 사용법: make-dummy-novel <작품 폴더 경로> [회차 수=500] [긴 회차 수=10] [짧은 회차 글자 수=300]
// 앞의 "긴 회차"는 5,000자, 나머지는 짧게 만든다. 전부 5,000자로 만들려면 긴 회차 수를 회차 수와 같게 준다.
// 같은 인자로 실행하면 항상 같은 내용이 나온다(측정 조건을 매번 같게 하려고).
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

/// 결정적인 의사 난수 (같은 씨앗이면 같은 수열).
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
  var length = 0  // text.count를 매번 세면 느려서 따로 센다
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
    // 앱이 저장하는 것처럼 글자 수도 project.json에 넣어 둔다(사이드바가 본문을 읽지 않고 보여준다).
    project.episodes[index].characterCount = CharacterCount(counting: text)
  }
  try store.saveProject(project)
  print("✓ \(episodeCount)회차 더미 작품 (앞 \(longEpisodeCount)화 \(longEpisodeLength)자, 나머지 \(shortEpisodeLength)자): \(root.path(percentEncoded: false))")
} catch {
  print("✗ 더미 작품을 만들지 못함: \(error)")
  exit(1)
}
