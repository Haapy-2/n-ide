import NovelCore
import SwiftUI

/// Project search panel shown in place of the sidebar (DESIGN ch.6). Input field on top, results grouped by episode below.
/// Result row = line number + line preview (only the match on an accent background). Clicking goes to that spot in that episode.
struct SearchPanel: View {
  let search: ProjectSearch
  let replace: ProjectReplace
  let episodes: [EpisodeMeta]
  /// Focus the input field on every change (when ⇧⌘F is pressed again).
  let focusRequest: Int
  /// Row inner left padding (nil = not measured yet). The workspace holds it so closing/reopening the panel doesn't re-measure (same reason as EpisodeList).
  @Binding var measuredInset: CGFloat?
  let onReveal: (TextReveal) -> Void
  /// Replace all finished (toast, search again).
  let onReplaced: (ProjectReplace.Report) -> Void
  /// An episode was clicked in the replaced-episodes list (go there, with `바꾸기 전` preselected in the snapshot panel).
  let onShowReplaced: (ProjectReplace.Report.Episode) -> Void
  let onClose: () -> Void
  @FocusState private var fieldFocused: Bool
  /// Last clicked result (gray rect)
  @State private var picked: PickedMatch?
  /// Last clicked episode in the replaced-episodes list
  @State private var pickedReplaced: EpisodeID?

  private var contentInset: CGFloat { measuredInset ?? TrafficLightOffsetReader.contentInset(for: nil) }

  var body: some View {
    @Bindable var search = search
    @Bindable var replace = replace
    // Episode numbers are built once so each row doesn't search the whole list (500 episodes × 500 result groups = 250k comparisons per keystroke of the replacement).
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
                // A real button, so VoiceOver and keyboard can press it.
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
    // On first open in a window, hidden until measured (after one draw). Showing with default padding first would make it jump sideways.
    .opacity(measuredInset == nil ? 0 : 1)
    .onChange(of: search.query) {
      replace.clearFinished()
      pickedReplaced = nil
      search.schedule()
    }
    .onChange(of: search.caseSensitive) { search.schedule() }
    // Search again when the episode list changes via trash or ⌘Z. Otherwise results for deleted episodes linger and restored ones are missing.
    .onChange(of: episodes.map(\.id)) { search.refresh() }
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

  /// Replacement shown in result rows. Only while a replacement is typed (empty = plain search results).
  private var previewReplacement: String? {
    let replacement = replace.replacement
    guard !replacement.isEmpty, TextReplace.canReplace(search.resultQuery, with: replacement) else { return nil }
    return replacement
  }

  /// Only when the current result was found with the current phrase and has matches. Disabled while counting or replacing.
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

  /// Title next to the number column. Empty string if empty or same as the number ("1화") to avoid duplication.
  private func title(_ id: EpisodeID, _ positions: [EpisodeID: Int]) -> String {
    guard let index = positions[id] else { return "" }
    let title = episodes[index].title
    return EpisodeLabel.text(number: index + 1, title: title) == "\(index + 1)화" ? "" : title
  }

  private func header(for found: ProjectSearchResult.Episode, _ positions: [EpisodeID: Int]) -> some View {
    let index = positions[found.id]
    let title = self.title(found.id, positions)
    return HStack(spacing: 6) {
      Text(index.map { "\($0 + 1)화" } ?? "")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
      if !title.isEmpty {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text("\(found.matches.count)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
    }
    .padding(.leading, contentInset)
    .padding(.trailing, 12)
  }

  /// One line under the input: searching, result count, no results, truncated, unreadable episodes. After replacing, the replace result.
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

/// One row of the replaced-episodes list: `3화  제목  · 12곳`. Same typography as episode group header rows.
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
      if !title.isEmpty {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
      }
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

/// One result row: line number + preview (only the match on an 18% accent background, DESIGN ch.6).
private struct SearchMatchRow: View {
  let match: SearchMatch
  /// While typing a replacement: the match in deleted-line color with strikethrough, followed by the replacement in inserted-line color (like VS Code search & replace).
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
