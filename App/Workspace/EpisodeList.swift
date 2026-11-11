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
  /// nil이면(미리보기) 메뉴와 드래그가 없다.
  var onRename: ((EpisodeID) -> Void)? = nil
  var onTrash: ((EpisodeID) -> Void)? = nil
  var onAddAfter: ((EpisodeID) -> Void)? = nil
  var onMove: ((IndexSet, Int) -> Void)? = nil

  var body: some View {
    List {
      Section("회차") {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
          // 클릭 영역 = 회색 선택 칸 전체. 줄 여백을 0으로 하고 여백을 칸 안쪽에 직접 넣어
          // 글자뿐 아니라 칸의 빈 곳을 눌러도 선택되게 한다.
          EpisodeRow(number: index + 1, title: episode.title)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(episode.id == selection ? Color.ink.opacity(0.08) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            // 두 번 클릭하면 이름 변경. 한 번 클릭 선택은 두 번 클릭 판정을 기다리지 않고 바로 한다.
            .onTapGesture(count: 2) { onRename?(episode.id) }
            .simultaneousGesture(TapGesture().onEnded { selection = episode.id })
            .contextMenu {
              if let onAddAfter, let onRename, let onTrash {
                Button("아래에 새 회차") { onAddAfter(episode.id) }
                Button("이름 변경…") { onRename(episode.id) }
                Divider()
                Button("휴지통으로 이동…") { onTrash(episode.id) }
              }
            }
            .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(episode.id == selection ? [.isButton, .isSelected] : .isButton)
        }
        // 드래그로 순서 바꾸기. 번호는 순서로 매기므로 함께 바뀐다(파일 이름은 그대로).
        .onMove(perform: onMove)
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
