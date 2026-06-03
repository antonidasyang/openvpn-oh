// Minimal left-click popup for the tray icon. The real controls live in the
// tray's right-click menu (connect / disconnect / reconnect / open / exit).
@Entry
@Component
struct TrayPopup {
  build() {
    Column({ space: 6 }) {
      Text('D2SVPN')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text('右键托盘图标管理连接')
        .fontSize(12)
        .fontColor(Color.Gray)
    }
    .padding(16)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
