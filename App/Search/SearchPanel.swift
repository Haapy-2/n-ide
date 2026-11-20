import NovelCore
import SwiftUI

/// 사이드바 자리에 뜨는 작품 전체 검색 패널(DESIGN 6장). 위에 입력 칸, 아래에 회차별로 묶인 결과.
/// 결과 한 줄 = 줄 번호 + 줄 미리 보기(일치한 곳만 accent 바탕). 누르면 그 회차의 그 자리로 간다.
struct SearchPanel: View {
  let search: ProjectSearch
  let episodes: [EpisodeMeta]
  /// 바뀔 때마다 입력 칸에 초점을 준다(⇧⌘F를 다시 눌렀을 때).
  let focusRequest: Int
  let onReveal: (TextReveal) -> Void
  let onClose: () -> Void
  @FocusState private var fieldFocused: Bool
  @State private var trafficLightOffset: CGFloat?
  /// 마지막으로 누른 결과(회색 칸)
  @State private var picked: PickedMatch?

  private var contentInset: CGFloat { TrafficLightOffsetReader.contentInset(for: trafficLightOffset) }

  var body: some View {
    @Bindable var search = search
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
      .background(TrafficLightOffsetReader { trafficLightOffset = $0 })

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
      .padding(.vertical, 8)

      if let status {
        Text(status)
          .font(.system(size: 11))
          .foregroundStyle(Color.inkMuted)
          .padding(.leading, contentInset)
          .padding(.trailing, 12)
          .padding(.bottom, 6)
      }

      List {
        if let result = search.result {
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
                  SearchMatchRow(match: match, inset: contentInset, isPicked: picked == PickedMatch(id: found.id, index: index))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                  .listRowBackground(Color.clear)
              }
            } header: {
              header(for: found)
            }
          }
        }
      }
      .environment(\.defaultMinListRowHeight, 0)
    }
    .onChange(of: search.query) { search.schedule() }
    .onChange(of: search.caseSensitive) { search.schedule() }
    .onChange(of: focusRequest, initial: true) { fieldFocused = true }
    .onAppear { search.refresh() }
    .onDisappear { search.cancel() }
  }

  private func header(for found: ProjectSearchResult.Episode) -> some View {
    let index = episodes.firstIndex { $0.id == found.id }
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

  /// 입력 칸 아래 한 줄: 찾는 중·결과 수·결과 없음·잘림·못 읽은 회차.
  private var status: String? {
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

private struct PickedMatch: Equatable {
  let id: EpisodeID
  let index: Int
}

/// 결과 한 줄: 줄 번호 + 미리 보기(일치한 곳만 accent 18% 바탕, DESIGN 6장).
private struct SearchMatchRow: View {
  let match: SearchMatch
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
    marked.backgroundColor = Color.accent.opacity(0.18)
    return AttributedString(before) + marked + AttributedString(after)
  }
}
