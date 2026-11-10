import Foundation
import Testing
@testable import NovelCore

/// 사용자가 Finder와 텍스트 편집기로 열어 볼 수 있는 예시 작품을 build/samples/에 만든다.
/// 테스트를 돌릴 때마다 새로 만든다.
struct SampleProjectTests {
  @Test func writeSampleProjectForManualInspection() throws {
    let root = TestFolder.repoRoot.appending(path: "build/samples/예시 작품.novel", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(
      at: root.deletingLastPathComponent(), withIntermediateDirectories: true)

    let store = try ProjectStore.create(at: root, title: "예시 작품")
    var project = try store.loadProject()
    let episodes = [
      EpisodeMeta(title: "첫 만남", goal: 5_000),
      EpisodeMeta(title: "비 오는 날", goal: 5_000),
      EpisodeMeta(title: "", goal: 5_000),
    ]
    project.episodes = episodes
    let note = NoteMeta(title: "주인공")
    project.notes = [note]
    try store.saveProject(project)

    try store.writeEpisode("비가 그친 골목에서 그녀를 처음 만났다.\n\n\"여기서 뭐 해요?\"", id: episodes[0].id)
    try store.writeEpisode("그날도 비가 왔다.", id: episodes[1].id)
    try store.writeEpisode("", id: episodes[2].id)
    try store.writeNote("이름: 한서윤\n특징: 우산을 들고 다니지 않는다.", id: note.id)

    #expect(try store.loadProject().episodes.count == 3)
  }
}
