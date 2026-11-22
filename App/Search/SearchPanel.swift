import NovelCore
import SwiftUI

/// 사이드바 자리에 뜨는 작품 전체 검색 패널(DESIGN 6장). 위에 입력 칸, 아래에 회차별로 묶인 결과.
/// 결과 한 줄 = 줄 번호 + 줄 미리 보기(일치한 곳만 accent 바탕). 누르면 그 회차의 그 자리로 간다.
struct SearchPanel: View {
  let search: ProjectSearch
  let replace: ProjectReplace
  let episodes: [EpisodeMeta]
  /// 바뀔 때마다 입력 칸에 초점을 준다(⇧⌘F를 다시 눌렀을 때).
  let focusRequest: Int
  /// 줄 안쪽 왼쪽 여백(nil이면 아직 안 잼). 패널을 닫았다 열어도 다시 재지 않게 작업 공간이 들고 있다(EpisodeList와 같은 까닭).
  @Binding var measuredInset: CGFloat?
  let onReveal: (TextReveal) -> Void
  /// 전체 바꾸기가 끝났다(토스트, 다시 찾기).
  let onReplaced: (ProjectReplace.Report) -> Void
  /// 바꾼 회차 목록에서 회차를 눌렀다(그 회차로, 스냅샷 판은 `바꾸기 전`을 골라 둔 채).
  let onShowReplaced: (ProjectReplace.Report.Episode) -> Void
  let onClose: () -> Void
  @FocusState private var fieldFocused: Bool
  /// 마지막으로 누른 결과(회색 칸)
  @State private var picked: PickedMatch?
  /// 바꾼 회차 목록에서 마지막으로 누른 회차
  @State private var pickedReplaced: EpisodeID?

  private var contentInset: CGFloat { measuredInset ?? TrafficLightOffsetReader.contentInset(for: nil) }

  var body: some View {
    @Bindable var search = search
    @Bindable var replace = replace
    // 회차 번호를 줄마다 목록 전체에서 찾지 않게 한 번 만든다(500회차 × 결과 묶음 500개면 바꿀 말을 칠 때마다 25만 번 비교).
    let positions = Dictionary(episodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("검색")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.inkMuted)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.inkMuted)
        }
        .buttonStyle(.plain)
        .help("회차 목록으로 (Esc)")
        .accessibilityLabel("검색 닫기")
      }
      .padding(.leading, contentInset)
      .padding(.trailing, 12)
      .padding(.top, 4)
      .background(TrafficLightOffsetReader { measuredInset = TrafficLightOffsetReader.contentInset(for: $0) })

      HStack(spacing: 6) {
        TextField("작품 전체에서 찾기", text: $search.query)
          .textFieldStyle(.roundedBorder)
          .focused($fieldFocused)
          .onSubmit { search.refresh() }
          .onExitCommand(perform: onClose)
        Toggle(isOn: $search.caseSensitive) {
          Text("Aa").font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.button)
        .help("영문 대소문자 구분")
        .accessibilityLabel("대소문자 구분")
      }
      .padding(.leading, contentInset - 4)
      .padding(.trailing, 10)
      .padding(.top, 8)

      HStack(spacing: 6) {
        TextField("바꿀 말", text: $replace.replacement)
          .textFieldStyle(.roundedBorder)
          .onExitCommand(perform: onClose)
          .help("비우면 찾은 말을 지워요")
        Button("모두 바꾸기") {
          Task { await replace.prepare(query: search.query, caseSensitive: search.caseSensitive) }
        }
        .disabled(!canReplace)
      }
      .padding(.leading, contentInset - 4)
      .padding(.trailing, 10)
      .padding(.top, 6)
      .padding(.bottom, 8)

      if let status {
        Text(status)
          .font(.system(size: 11))
          .foregroundStyle(Color.inkMuted)
          .padding(.leading, contentInset)
          .padding(.trailing, 12)
          .padding(.bottom, 6)
      }

      List {
        if let finished = replace.finished {
          Section {
            ForEach(finished.replaced, id: \.id) { entry in
              Button {
                pickedReplaced = entry.id
                onShowReplaced(entry)
              } label: {
                ReplacedEpisodeRow(
                  number: number(entry.id, positions), title: title(entry.id, positions), count: entry.count,
                  inset: contentInset,
                  isPicked: pickedReplaced == entry.id)
              }
              .buttonStyle(.plain)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
              .help("이 회차로 가서 바꾸기 전과 비교")
            }
          } header: {
            Text("바꾼 회차")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color.inkMuted)
              .padding(.leading, contentInset)
          }
        } else if let result = search.result {
          ForEach(result.episodes, id: \.id) { found in
            Section {
              ForEach(Array(found.matches.enumerated()), id: \.offset) { index, match in
                // 진짜 버튼이라 VoiceOver·키보드로도 누를 수 있다.
                Button {
                  picked = PickedMatch(id: found.id, index: index)
                  onReveal(TextReveal(
                    episodeID: found.id, location: match.location, length: match.length,
                    query: search.resultQuery, caseSensitive: search.resultCaseSensitive))
                } label: {
                  SearchMatchRow(
                    match: match, replacement: previewReplacement, inset: contentInset,
                    isPicked: picked == PickedMatch(id: found.id, index: index))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                  .listRowBackground(Color.clear)
              }
            } header: {
              header(for: found, positions)
            }
          }
        }
      }
      .environment(\.defaultMinListRowHeight, 0)
    }
    // 창에서 처음 열 때는 잴 때까지(한 번 그린 뒤) 숨긴다. 기본 여백으로 먼저 보이면 곧바로 옆으로 튄다.
    .opacity(measuredInset == nil ? 0 : 1)
    .onChange(of: search.query) {
      replace.clearFinished()
      pickedReplaced = nil
      search.schedule()
    }
    .onChange(of: search.caseSensitive) { search.schedule() }
    .onChange(of: focusRequest, initial: true) { fieldFocused = true }
    .onAppear { search.refresh() }
    .onDisappear {
      search.cancel()
      replace.clearFinished()
    }
    .alert(replace.pending?.title ?? "", isPresented: isConfirmingReplace, presenting: replace.pending) { pending in
      Button("모두 바꾸기") {
        Task {
          guard let report = await replace.confirm(pending) else { return }
          onReplaced(report)
        }
      }
      Button("취소", role: .cancel) { replace.cancel() }
    } message: { pending in
      Text(pending.message)
    }
  }

  /// 결과 줄에 보일 바꿀 말. 바꿀 말을 친 동안만(비어 있으면 평소 찾기 결과 그대로).
  private var previewReplacement: String? {
    let replacement = replace.replacement
    guard !replacement.isEmpty, TextReplace.canReplace(search.resultQuery, with: replacement) else { return nil }
    return replacement
  }

  /// 지금 결과가 지금 입력한 문구로 찾은 것이고 찾은 곳이 있을 때만. 세거나 바꾸는 중에는 막는다.
  private var canReplace: Bool {
    guard !replace.isWorking, let result = search.result, result.matchCount > 0,
      search.resultQuery == search.query, search.resultCaseSensitive == search.caseSensitive
    else { return false }
    return TextReplace.canReplace(search.query, with: replace.replacement)
  }

  private var isConfirmingReplace: Binding<Bool> {
    Binding(get: { replace.pending != nil }, set: { if !$0 { replace.cancel() } })
  }

  private func number(_ id: EpisodeID, _ positions: [EpisodeID: Int]) -> String {
    positions[id].map { "\($0 + 1)화" } ?? ""
  }

  private func title(_ id: EpisodeID, _ positions: [EpisodeID: Int]) -> String {
    positions[id].map { episodes[$0].title } ?? ""
  }

  private func header(for found: ProjectSearchResult.Episode, _ positions: [EpisodeID: Int]) -> some View {
    let index = positions[found.id]
    let title = index.map { episodes[$0].title } ?? ""
    return HStack(spacing: 6) {
      Text(index.map { "\($0 + 1)화" } ?? "")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
      Text(title.isEmpty ? "제목 없음" : title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(title.isEmpty ? Color.inkMuted : Color.primary)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text("\(found.matches.count)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
    }
    .padding(.leading, contentInset)
    .padding(.trailing, 12)
  }

  /// 입력 칸 아래 한 줄: 찾는 중·결과 수·결과 없음·잘림·못 읽은 회차. 바꾼 뒤에는 바꾼 결과.
  private var status: String? {
    if let finished = replace.finished {
      var parts = ["\(finished.replaced.count.formatted())개 회차에서 \(finished.count.formatted())곳을 바꿨어요"]
      if finished.skipped > 0 { parts.append("\(finished.skipped)개 회차는 건너뛰었어요") }
      if finished.unreadable > 0 { parts.append("\(finished.unreadable)개 회차는 읽지 못했어요") }
      return parts.joined(separator: " · ")
    }
    guard TextSearch.isSearchable(search.query) else {
      return search.query.isEmpty ? nil : "줄바꿈이 든 문구는 찾을 수 없어요."
    }
    guard let result = search.result else { return search.isSearching ? "찾는 중…" : nil }
    var parts: [String] = []
    if result.matchCount == 0 {
      parts.append("찾은 곳이 없어요.")
    } else {
      parts.append("\(result.episodes.count.formatted())개 회차에서 \(result.matchCount.formatted())곳")
    }
    if result.isTruncated { parts.append("많아서 앞 \(result.matchCount.formatted())곳만 보여요.") }
    if !result.unreadable.isEmpty { parts.append("\(result.unreadable.count)개 회차는 읽지 못했어요.") }
    if search.isSearching { parts.append("찾는 중…") }
    return parts.joined(separator: " · ")
  }
}

/// 바꾼 회차 목록의 한 줄: `3화  제목  · 12곳`. 회차 묶음 제목 줄과 같은 글씨.
private struct ReplacedEpisodeRow: View {
  let number: String
  let title: String
  let count: Int
  let inset: CGFloat
  let isPicked: Bool

  var body: some View {
    HStack(spacing: 6) {
      Text(number)
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
      Text(title.isEmpty ? "제목 없음" : title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(title.isEmpty ? Color.inkMuted : Color.primary)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text("\(count.formatted())곳")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
    }
    .padding(.horizontal, inset)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .rowHighlight(isSelected: isPicked)
    .padding(.vertical, 1)
    .contentShape(Rectangle())
  }
}

private struct PickedMatch: Equatable {
  let id: EpisodeID
  let index: Int
}

/// 결과 한 줄: 줄 번호 + 미리 보기(일치한 곳만 accent 18% 바탕, DESIGN 6장).
private struct SearchMatchRow: View {
  let match: SearchMatch
  /// 바꿀 말을 치는 동안: 찾은 말은 지운 줄 색·취소선, 그 뒤에 바꿀 말을 넣은 줄 색으로(VS Code 검색 바꾸기와 같음).
  let replacement: String?
  let inset: CGFloat
  let isPicked: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(match.line)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
        .frame(minWidth: 26, alignment: .leading)
      Text(highlighted)
        .font(.system(size: 12))
        .lineLimit(2)
    }
    .padding(.horizontal, inset)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .rowHighlight(isSelected: isPicked)
    .padding(.vertical, 1)
    .contentShape(Rectangle())
  }

  private var highlighted: AttributedString {
    let preview = match.preview as NSString
    let before = preview.substring(to: match.previewMatch.lowerBound)
    let hit = preview.substring(with: NSRange(location: match.previewMatch.lowerBound, length: match.previewMatch.count))
    let after = preview.substring(from: match.previewMatch.upperBound)
    var marked = AttributedString(hit)
    guard let replacement else {
      marked.backgroundColor = Color.accent.opacity(0.18)
      return AttributedString(before) + marked + AttributedString(after)
    }
    marked.backgroundColor = Color.diffRemoved
    marked.strikethroughStyle = .single
    var inserted = AttributedString(replacement)
    inserted.backgroundColor = Color.diffAdded
    return AttributedString(before) + marked + inserted + AttributedString(after)
  }
}
