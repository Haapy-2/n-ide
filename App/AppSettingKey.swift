import Foundation

/// Key names for app-wide settings (UserDefaults). Gathered here so the Settings window and screens use the same names.
enum AppSettingKey {
  /// Blur other apps/desktop behind the sidebar (default: on)
  static let sidebarSeesThroughWindow = "sidebarSeesThroughWindow"
  /// Status bar character-count display `CharacterCountDisplay` (default: both)
  static let characterCountDisplay = "characterCountDisplay"
  /// Basis for goal progress and sidebar counts `CharacterCountBasis` (default: with spaces)
  static let characterCountGoalBasis = "characterCountGoalBasis"
  /// Status bar goal progress style `GoalProgressStyle` (default: ring)
  static let goalProgressStyle = "goalProgressStyle"
  /// Seconds to wait before recounting. 0 = live (default: 0.2)
  static let characterCountInterval = "characterCountInterval"
  /// Hide the status bar while typing (default: off = always visible)
  static let statusBarHidesWhileTyping = "statusBarHidesWhileTyping"
  /// Hide the status bar after 10 s idle (default: on)
  static let statusBarHidesWhenIdle = "statusBarHidesWhenIdle"
  /// Show character counts on sidebar episode rows (default: on)
  static let sidebarShowsCharacterCount = "sidebarShowsCharacterCount"
  /// App theme `AppTheme` (default: system)
  static let appTheme = "appTheme"
  /// How long the sidebar undo confirmation rests after "don't ask again" `UndoConfirmPause` (default: one week)
  static let undoConfirmPause = "undoConfirmPause"
  /// End time of that rest (seconds since 1970). Absent = ask every time.
  static let undoConfirmPausedUntil = "undoConfirmPausedUntil"
  /// Seconds a toast (top-right of the editor) stays. 0.5–5 in 0.5 steps (default: 2)
  static let toastDuration = "toastDuration"
  /// Automatic snapshots on (default: on). Leave and manual snapshots work even when off
  static let autoSnapshotEnabled = "autoSnapshotEnabled"
  /// Automatic snapshot interval in minutes: one of 5·10·15·30·60 (default: 30)
  static let autoSnapshotMinutes = "autoSnapshotMinutes"
  /// Automatic/leave snapshots kept per episode. 10–100 in steps of 10 (default: 50)
  static let snapshotRetention = "snapshotRetention"
  /// User shortcut overrides `ShortcutSettings.storageText` (default: empty = all defaults)
  static let shortcuts = "shortcuts"
  /// Body font `BodyFont` (default: Pretendard)
  static let bodyFont = "bodyFont"
  /// Font size in pt (default: 17)
  static let fontSize = "fontSize"
  /// Line spacing multiplier (default: 1.75)
  static let lineSpacing = "lineSpacing"
  /// Paragraph spacing in lines (default: 0.6)
  static let paragraphSpacing = "paragraphSpacing"
  /// Body width as Hangul characters per line (default: 40)
  static let lineWidthInCharacters = "lineWidthInCharacters"
  /// Line numbers in the editor's left margin (default: off)
  static let showsLineNumbers = "showsLineNumbers"
  /// With line numbers on, also number blank lines (default: on). Numbering is the same either way (matches the diff view)
  static let numbersBlankLines = "numbersBlankLines"
  /// Same-word multi-cursor (⌘D) on (default: on). So it can be turned off immediately if it misbehaves on a real manuscript
  static let multiCursorEnabled = "multiCursorEnabled"
  /// Caret width in pt. 1–4 in 0.5 steps (default: 2)
  static let caretWidth = "caretWidth"
  /// Caret height as a multiple of font size. 1.0–1.75 (default: 1.2)
  static let caretHeightRatio = "caretHeightRatio"
  /// Light-mode caret color `CaretColor.storageText` (default: empty = accent)
  static let caretColorLight = "caretColorLight"
  /// Dark-mode caret color `CaretColor.storageText` (default: empty = accent)
  static let caretColorDark = "caretColorDark"
  /// Episode groups collapsed in the sidebar (GroupIDs joined by commas). Remembered on this Mac only.
  static let collapsedEpisodeGroups = "collapsedEpisodeGroups"
  /// Per-episode last caret / top-of-screen character and open time (`EpisodeViewStates`). Remembered on this Mac only.
  static let episodeViewStates = "episodeViewStates"
}
