import CoreGraphics
import Foundation

// 실제 키보드처럼 키 코드를 시스템(HID)에 보낸다. 컴퓨터 유스의 key·type은 한글 입력기를 거치지 않아서(완성 글자를
// 바로 넣거나 키 코드가 0) 조합을 재현하지 못한다. 맨 앞 앱이 받으므로 전체 화면 제어로 앱을 앞에 둔 뒤 쓴다.
// 사용법: keys 14,4,c6,cs6 · 숫자는 키 코드, c는 ⌘, s는 ⇧. 환경 변수 FAST가 있으면 키 사이 약 11ms.
let tokens = CommandLine.arguments.dropFirst().joined(separator: ",").split(separator: ",")
let source = CGEventSource(stateID: .hidSystemState)
let fast = ProcessInfo.processInfo.environment["FAST"] != nil

for token in tokens {
  guard let code = UInt16(token.filter(\.isNumber)) else { continue }
  // 플래그를 키마다 적는다. 적지 않으면 앞 키의 ⌘가 남아 다음 글자가 단축키로 들어간다.
  var flags: CGEventFlags = []
  if token.contains("c") { flags.insert(.maskCommand) }
  if token.contains("s") { flags.insert(.maskShift) }
  let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
  down?.flags = flags
  up?.flags = flags
  down?.post(tap: .cghidEventTap)
  usleep(fast ? 3_000 : 30_000)
  up?.post(tap: .cghidEventTap)
  usleep(fast ? 8_000 : 90_000)
}
