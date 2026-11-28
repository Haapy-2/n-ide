import NovelCore
import SwiftUI

/// Batch episode rename sheet (PLAN ch.15). Pick new names with one of three methods; `옛 이름 → 새 이름` is shown below.
/// Preview and apply share the same rule (`EpisodeTitleBatch`). On apply the workspace recomputes from the list titles at that time.
struct BatchRenameSheet: View {
  struct Request: Identifiable {
    let id = UUID()
    let episodeIDs: Set<EpisodeID>
  }

  enum Mode: String, CaseIterable, Identifiable {
    case replace = "글자 바꾸기"
    case affix = "앞·뒤에 붙이기"
    case numbered = "새 이름 + 번호"
    var id: Self { self }
  }

  let episodes: [EpisodeMeta]
  let targetIDs: Set<EpisodeID>
  let onCancel: () -> Void
  let onRename: (EpisodeTitleBatch.Rule) -> Void

  @State private var mode = Mode.replace
  @State private var find = ""
  @State private var replacement = ""
  @State private var prefix = ""
  @State private var suffix = ""
  @State private var name = ""
  @State private var start = 1
  @State private var numberFirst = false
  @State private var isApplying = false

  private static let numberRange = 0...99_999

  private var rule: EpisodeTitleBatch.Rule {
    switch mode {
    case .replace: .replace(find: find, with: replacement)
    case .affix: .affix(prefix: prefix, suffix: suffix)
    case .numbered: .numbered(name: name, start: start, numberFirst: numberFirst)
    }
  }

  var body: some View {
    let targets = episodes.enumerated().filter { targetIDs.contains($0.element.id) }
    let titles = EpisodeTitleBatch.titles(targets.map(\.element.title), by: rule)
    let changed = zip(targets, titles).filter { $0.0.element.title != $0.1 }.count
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Text("\(targets.count.formatted())개 회차 이름 변경")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.ink)
        Picker("방식", selection: $mode) {
          ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        fields
      }
      .padding(16)
      Divider()
      List {
        ForEach(Array(zip(targets, titles).enumerated()), id: \.offset) { _, pair in
          row(number: pair.0.offset + 1, old: pair.0.element.title, new: pair.1)
        }
      }
      Divider()
      HStack(spacing: 8) {
        Text(changed == 0 ? "바뀌는 회차가 없어요" : "\(changed.formatted())개 회차가 바뀌어요")
          .font(.system(size: 12))
          .foregroundStyle(Color.inkMuted)
        Spacer()
        Button("취소", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        // Return during Hangul composition applies after composition ends and the last character enters the field.
        // Return pressed again before the sheet closes would apply the rule twice, so it's accepted only once.
        Button("이름 바꾸기") {
          guard !isApplying else { return }
          isApplying = true
          DispatchQueue.main.async { onRename(rule) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(changed == 0 || isApplying)
      }
      .padding(12)
    }
    .frame(minWidth: 480, idealWidth: 540, minHeight: 420, idealHeight: 520)
  }

  @ViewBuilder
  private var fields: some View {
    switch mode {
    case .replace:
      field("찾을 말", $find)
      field("바꿀 말", $replacement)
    case .affix:
      field("앞에", $prefix)
      field("뒤에", $suffix)
    case .numbered:
      field("이름", $name)
      HStack(spacing: 8) {
        Text("시작 번호")
          .frame(width: 64, alignment: .leading)
        TextField("시작 번호", value: $start, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 80)
          .labelsHidden()
          .onChange(of: start) { start = min(max(start, Self.numberRange.lowerBound), Self.numberRange.upperBound) }
        Stepper("시작 번호", value: $start, in: Self.numberRange)
          .labelsHidden()
        Picker("번호 자리", selection: $numberFirst) {
          Text("이름 뒤").tag(false)
          Text("이름 앞").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
      }
      .font(.system(size: 12))
    }
  }

  private func field(_ label: String, _ text: Binding<String>) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.system(size: 12))
        .frame(width: 64, alignment: .leading)
      TextField(label, text: text)
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
    }
  }

  private func row(number: Int, old: String, new: String) -> some View {
    HStack(spacing: 8) {
      Text("\(number)화")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
        .frame(minWidth: 40, alignment: .leading)
      Text(Self.display(old))
        .font(.system(size: 12))
        .foregroundStyle(Color.inkMuted)
        .lineLimit(1)
      if old != new {
        Image(systemName: "arrow.right")
          .font(.system(size: 10))
          .foregroundStyle(Color.inkMuted)
        Text(Self.display(new))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.ink)
          .lineLimit(1)
      } else {
        Text("그대로")
          .font(.system(size: 11))
          .foregroundStyle(Color.inkMuted)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private static func display(_ title: String) -> String { title.isEmpty ? "제목 없음" : title }
}
