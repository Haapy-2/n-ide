import Foundation
import NovelCore

extension ProjectError {
  var userMessage: String {
    switch self {
    case .alreadyExists(let url):
      "‘\(url.lastPathComponent)’이(가) 이미 있어요. 덮어쓰지 않았어요. 다른 이름을 골라 주세요."
    case .missingProjectFile:
      "작품 폴더가 아니거나 작품 정보(project.json)와 회차 파일을 찾을 수 없어요. 아무것도 바꾸지 않았어요."
    case .corruptProjectFile:
      "작품 정보(project.json)를 읽을 수 없어요."
    case .newerSchemaVersion(let found, let supported):
      "더 새 버전의 앱으로 만든 작품이라 열 수 없어요(형식 \(found), 이 앱은 \(supported)까지). 파일은 그대로 두었어요."
    case .missingTextFile(let url):
      "본문 파일을 찾을 수 없어요: \(url.lastPathComponent)"
    case .notUTF8(let url):
      "본문 파일이 UTF-8 텍스트가 아니라 열 수 없어요: \(url.lastPathComponent)"
    case .writeFailed(let url, let reason, let problem):
      problem == .other
        ? "\(url.lastPathComponent)을(를) 저장하지 못했어요. (\(reason))"
        : "\(url.lastPathComponent)을(를) 저장하지 못했어요. \(problem.advice)"
    }
  }
}

nonisolated extension WriteProblem {
  /// 상태 줄에 짧게.
  var statusLabel: String {
    switch self {
    case .noPermission: "쓸 권한 없음"
    case .locked: "파일이 잠김"
    case .readOnlyVolume: "읽기 전용 디스크"
    case .diskFull: "디스크 공간 부족"
    case .missingFolder: "작품 폴더를 찾을 수 없음"
    case .other: "원고는 메모리에 있음"
    }
  }

  /// 사용자가 할 수 있는 일.
  var advice: String {
    switch self {
    case .noPermission:
      "작품 폴더에 쓸 권한이 없어요. Finder에서 작품 폴더의 정보 가져오기 → 공유 및 권한을 확인해 주세요."
    case .locked:
      "파일이나 폴더가 잠겨 있어요. Finder에서 정보 가져오기의 ‘잠김’을 끄면 다시 저장할 수 있어요."
    case .readOnlyVolume:
      "읽기 전용 디스크에 있는 작품이에요. 쓸 수 있는 곳으로 작품 폴더를 옮겨 주세요."
    case .diskFull:
      "디스크 공간이 모자라요. 공간을 비운 뒤 다시 시도해 주세요."
    case .missingFolder:
      "작품 폴더를 찾을 수 없어요. 외장 디스크가 빠졌거나 폴더를 옮겼을 수 있어요. 다시 연결한 뒤 다시 시도해 주세요."
    case .other:
      "잠시 뒤 다시 시도해 주세요."
    }
  }
}
