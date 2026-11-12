import SwiftUI

/// 설정 창 "사이드바"
struct SidebarSettingsPane: View {
  @AppStorage(AppSettingKey.sidebarShowsCharacterCount) private var showsCount = true
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var seesThroughWindow = true

  var body: some View {
    Form {
      Section {
        Toggle("글자 수 보이기", isOn: $showsCount)
        Toggle("뒤로 창 비치기", isOn: $seesThroughWindow)
      }
    }
    .formStyle(.grouped)
  }
}
