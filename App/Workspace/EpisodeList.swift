import NovelCore
import SwiftUI

/// 사이드바의 회차 목록. 한 줄: `번호  제목` (글자 수는 9단계에서 오른쪽 끝에 붙는다).
struct EpisodeList: View {
  let episodes: [EpisodeMeta]
  @Binding var selection: EpisodeID?

  var body: some View {
    List(selection: $selection) {
      Section("회차") {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
          EpisodeRow(number: index + 1, title: episode.title)
            .tag(episode.id)
        }
      }
    }
  }
}

private struct EpisodeRow: View {
  let number: Int
  let title: String

  var body: some View {
    HStack(spacing: 8) {
      Text("\(number)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
        .frame(minWidth: 24, alignment: .trailing)
      Text(title.isEmpty ? "제목 없음" : title)
        .font(.system(size: 13))
        .foregroundStyle(title.isEmpty ? Color.inkMuted : Color.primary)
        .lineLimit(1)
    }
  }
}
