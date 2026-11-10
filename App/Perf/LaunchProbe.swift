import Darwin
import Foundation

/// 성능 측정용 갈고리 (Scripts/perf.sh 전용). 환경 변수가 없으면 아무 일도 하지 않는다.
/// - NOVEL_PERF_OPEN=<작품 경로>: 작품 선택 창 대신 그 작품을 바로 연다.
/// - NOVEL_PERF_LAUNCH=1: 편집기가 처음 키 입력을 받을 수 있게 되면 프로세스 시작부터 걸린 시간을 찍고 끝낸다.
enum LaunchProbe {
  static var projectToOpen: URL? {
    ProcessInfo.processInfo.environment["NOVEL_PERF_OPEN"].map { URL(filePath: $0, directoryHint: .isDirectory) }
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

  /// 커널이 기록한 이 프로세스의 시작 시각.
  private static func processStartDate() -> Date {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let start = info.kp_proc.p_un.__p_starttime
    return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
  }
}
