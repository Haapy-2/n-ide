import NovelCore
import SwiftUI

/// 전체 바꾸기 되돌리기 창(PLAN 14장 5번). 왼쪽은 지금 되돌리면 바뀌는 곳이 남은 회차(기본 모두 체크),
/// 오른쪽은 고른 회차의 `지금 → 되돌린 뒤` 비교. 체크하지 않은 회차는 파일도 편집기도 건드리지 않는다.
struct RevertSheet: View {
  let session: RevertSession
  let episodes: [EpisodeMeta]
  let onCancel: () -> Void
  let onRevert: (Set<EpisodeID>) -> Void

  var body: some View {
    @Bindable var session = session
    let record = session.undoable.record
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(record.memo) 되돌리기")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.ink)
        Text(subtitle(record))
          .font(.system(size: 12))
          .foregroundStyle(Color.inkMuted)
        if session.undoable.excluded > 0 {
          Text("\(session.undoable.excluded)개 회차는 이미 되돌려서 목록에 없어요.")
            .font(.system(size: 12))
            .foregroundStyle(Color.inkMuted)
        }
        if session.undoable.unreadable > 0 {
          Text("\(session.undoable.unreadable)개 회차는 바꾸기 전 스냅샷을 읽지 못해 되돌릴 수 없어요.")
            .font(.system(size: 12))
            .foregroundStyle(Color.inkMuted)
        }
      }
      .padding(16)
      Divider()
      HStack(spacing: 0) {
        List(selection: $session.focused) {
          ForEach(session.candidates) { candidate in
            row(candidate)
              .tag(candidate.id)
          }
        }
        .onKeyPress(.space) {
          guard let focused = session.focused else { return .ignored }
          session.toggle(focused)
          return .handled
        }
        .frame(width: 300)
        Divider()
        Group {
          if let diff = session.preview {
            DiffView(diff: diff, pastTitle: "지금", presentTitle: "되돌린 뒤")
          } else {
            Text(session.isLoadingPreview ? "비교하는 중…" : "회차를 누르면 지금 글과 되돌린 뒤를 비교해요.")
              .font(.system(size: 12))
              .foregroundStyle(Color.inkMuted)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .background(Color.paper)
      }
      Divider()
      HStack(spacing: 8) {
        Button("모두 선택") { session.checkAll() }
        Button("모두 해제") { session.uncheckAll() }
        Spacer()
        Button("취소", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("\(session.checked.count)개 회차 되돌리기") { onRevert(session.checked) }
          .keyboardShortcut(.defaultAction)
          .disabled(session.checked.isEmpty)
      }
      .padding(12)
    }
    .frame(minWidth: 760, idealWidth: 860, minHeight: 460, idealHeight: 560)
  }

  /// `오늘 15:02에 37개 회차, 412곳을 바꿨어요.`
  private func subtitle(_ record: ProjectReplace.Record) -> String {
    let when = Calendar.current.isDateInToday(record.date)
      ? "오늘 " + record.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
      : ProjectReplace.stamp(record.date)
    return "\(when)에 \(record.entries.count.formatted())개 회차, \(record.count.formatted())곳을 바꿨어요."
  }

  private func row(_ candidate: ProjectReplace.Candidate) -> some View {
    let isChecked = session.checked.contains(candidate.id)
    let index = episodes.firstIndex { $0.id == candidate.id }
    let title = index.map { episodes[$0].title } ?? ""
    return HStack(spacing: 8) {
      // 실제 체크 칸이라 손쉬운 사용(VoiceOver)으로도 켜고 끈다. ⇧클릭은 줄 전체의 동작이 먼저 받는다.
      Toggle(isOn: Binding(get: { isChecked }, set: { _ in session.toggle(candidate.id) })) { EmptyView() }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel("\(index.map { "\($0 + 1)화" } ?? "") 되돌리기")
      Text(index.map { "\($0 + 1)화" } ?? "")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
      Text(title.isEmpty ? "제목 없음" : title)
        .font(.system(size: 12))
        .foregroundStyle(title.isEmpty ? Color.inkMuted : Color.ink)
        .lineLimit(1)
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 1) {
        Text("\(candidate.count.formatted())곳")
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(Color.inkMuted)
        if candidate.kept > 0 {
          Text("그 뒤에 고침 (\(candidate.kept)곳은 그대로)")
            .font(.system(size: 10))
            .foregroundStyle(Color.inkMuted)
        }
      }
    }
    .padding(.vertical, 2)
    // ⌘클릭: 고른 줄은 그대로 두고 체크만 바꾼다.
    .highPriorityGesture(TapGesture().modifiers(.command).onEnded { session.toggle(candidate.id) })
    .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { session.extend(to: candidate.id) })
  }
}
