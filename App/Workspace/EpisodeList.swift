import NovelCore
import SwiftUI

/// 사이드바의 회차 목록. 한 줄: `번호  제목` (글자 수는 9단계에서 오른쪽 끝에 붙는다).
///
/// 선택 표시는 시스템 것을 쓰지 않고 은은한 회색 배경 하나만 직접 그린다.
/// 시스템 선택은 누르는 순간 파란 강조색으로 칠했다가 편집기로 초점이 넘어가면 회색으로 바뀌어
/// 번쩍이는 것처럼 보이고, 이를 끌 방법이 없다(사용자 요청, DESIGN.md 4장).
struct EpisodeList: View {
  let episodes: [EpisodeMeta]
  @Binding var selection: EpisodeID?

  var body: some View {
    List {
      Section("회차") {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
          EpisodeRow(number: index + 1, title: episode.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selection = episode.id }
            .listRowBackground(
              RoundedRectangle(cornerRadius: 6)
                .fill(episode.id == selection ? Color.ink.opacity(0.08) : .clear)
                .padding(.horizontal, 10))
            .accessibilityAddTraits(episode.id == selection ? [.isButton, .isSelected] : .isButton)
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
