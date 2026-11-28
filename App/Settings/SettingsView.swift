import SwiftUI

/// Settings window (⌘,) (DESIGN.md ch.4 "Settings window"). Choosing a section on the left shows its settings on the right.
/// App-wide settings stored in UserDefaults (only the goal is per project); changes apply to open windows immediately.
/// Fixed window size. Always opens on "General".
struct SettingsView: View {
  /// Left list 180 + right 520. The right width fits the slider (240) and labels comfortably.
  /// Height fits the longest pane, "Editor", without scrolling and still fits a 13-inch screen (checked with snapshots).
  static let windowSize = CGSize(width: 700, height: 640)
  static let sidebarWidth: CGFloat = 180

  @State private var section: SettingsSection = .general
  /// Horizontal layout of list rows. Set at runtime by measuring the window close button position. nil before measuring.
  @State private var layout: RowLayout?

  init(section: SettingsSection = .general) {
    _section = State(initialValue: section)
  }

  var body: some View {
    NavigationSplitView {
      // Rows are stacked by hand instead of a system List: List draws rows only from 16 pt from the panel's left,
      // so the icon couldn't reach the red close button's line (9 pt from the window's left). Selection, hover and click were already custom, so nothing is lost.
      // Instead of the system selection (blue accent rect), draw the same gray rect as the workspace sidebar.
      VStack(spacing: 0) {
        ForEach(SettingsSection.allCases) { item in
          // Icon on the red close button's line, name left-aligned to the right of the icon. Spacing is the system default.
          HStack {
            // Uncolored icons: dark gray in light, light gray in dark
            // Equal icon column width so names' left edges line up. Icons hug the column's left to keep the button line.
            // Hidden until the measurement arrives: so drawing once at the default position and moving isn't visible.
            Image(systemName: item.symbolName)
              .foregroundStyle(.secondary)
              .frame(width: 20, alignment: .leading)
              .opacity(layout == nil ? 0 : 1)
            Text(item.title)
          }
          .padding(.leading, layout?.iconPadding ?? 0)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .rowHighlight(isSelected: item == section)
          .padding(.horizontal, layout?.boxMargin ?? 0)
          // Clickable including the gaps between rows (same reason as the workspace sidebar)
          .padding(.vertical, 1)
          .contentShape(Rectangle())
          .onTapGesture { section = item }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(item == section ? [.isButton, .isSelected] : .isButton)
        }
        Spacer(minLength: 0)
      }
      // Measured once from the panel's left edge (no need per row). The panel edge is fixed regardless of padding, so the value doesn't wobble.
      .background(TrafficLightOffsetReader { offset in
        layout = RowLayout(buttonOffset: TrafficLightOffsetReader.contentInset(for: offset))
      })
      .navigationSplitViewColumnWidth(Self.sidebarWidth)
      // The window has a fixed size, so the list never needs collapsing.
      .toolbar(removing: .sidebarToggle)
    } detail: {
      switch section {
      case .general: GeneralSettingsPane()
      case .editor: EditorSettingsPane()
      case .caret: CaretSettingsPane()
      case .shortcuts: ShortcutsSettingsPane()
      }
    }
    .navigationTitle(section.title)
    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
  }
}

/// Horizontal layout of Settings list rows. The distance from the panel's left edge to the close button is split in half:
/// the first half between the panel edge and the gray rect, the second between the rect's edge and the icon. So icon left edge = button left edge.
/// Not hard-coded for the same reason as the workspace sidebar (button position varies with macOS version and window style).
private struct RowLayout: Equatable {
  let boxMargin: CGFloat
  let iconPadding: CGFloat

  init(buttonOffset: CGFloat) {
    boxMargin = buttonOffset / 2
    iconPadding = buttonOffset - boxMargin
  }
}

/// Sections of the Settings list. Declaration order is list order (Caret right below Editor).
enum SettingsSection: String, CaseIterable, Identifiable {
  case general, editor, caret, shortcuts

  var id: Self { self }

  var title: String {
    switch self {
    case .general: "일반"
    case .editor: "편집기"
    case .caret: "커서"
    case .shortcuts: "단축키"
    }
  }

  var symbolName: String {
    switch self {
    case .general: "gearshape"
    case .editor: "doc.text"
    case .caret: "character.cursor.ibeam"
    case .shortcuts: "keyboard"
    }
  }
}
