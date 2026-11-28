import Darwin
import Foundation

/// Performance measurement hooks (Scripts/perf.sh only). Do nothing without the environment variables.
/// - NOVEL_PERF_OPEN=<project path>: open that project directly instead of the picker.
/// - NOVEL_PERF_LAUNCH=1: once the editor can accept its first keystroke, print the time since process start and exit.
/// - NOVEL_PERF_MEASURE=1: measurement run. Neither reads nor writes this Mac's remembered state (episode positions), so one run can't affect the next.
enum LaunchProbe {
  static var isMeasuring: Bool {
    ProcessInfo.processInfo.environment["NOVEL_PERF_MEASURE"] == "1"
      || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  static var projectToOpen: URL? {
    ProcessInfo.processInfo.environment["NOVEL_PERF_OPEN"].map { URL(filePath: $0, directoryHint: .isDirectory) }
  }

  /// During memory measurement (NOVEL_PERF_OPEN without NOVEL_PERF_LAUNCH), fix the workspace window's content size to this value.
  /// The graphics buffer drawing the window scales with window area, so memory swung 90–112 MB depending on the window size macOS remembered.
  /// Not used for launch timing: resizing the window triggers another layout pass and lengthens launch time.
  static var windowContentSize: CGSize? {
    guard projectToOpen != nil, ProcessInfo.processInfo.environment["NOVEL_PERF_LAUNCH"] != "1" else { return nil }
    return CGSize(width: 1100, height: 760)
  }

  private static var reported = false

  static func editorReady() {
    guard ProcessInfo.processInfo.environment["NOVEL_PERF_LAUNCH"] == "1", !reported else { return }
    reported = true
    let elapsed = Date().timeIntervalSince(processStartDate())
    print("NOVEL_PERF launch_ms \(String(format: "%.1f", elapsed * 1000))")
    fflush(stdout)
    exit(0)
  }

  /// This process's start time as recorded by the kernel.
  private static func processStartDate() -> Date {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let start = info.kp_proc.p_un.__p_starttime
    return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
  }
}
