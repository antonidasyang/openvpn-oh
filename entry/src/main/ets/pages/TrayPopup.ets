import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { EV_TRAY_OPEN, EV_TRAY_EXIT } from '../service/CommonEvents';

// Left-click popup for the tray icon. Runs in the StatusBarView UIExtension
// (a separate process), so its buttons notify the main UI process via
// CommonEvents instead of calling it directly.
@Entry
@Component
struct TrayPopup {
  private fire(event: string): void {
    const opts: commonEventManager.CommonEventPublishData = {};
    commonEventManager.publish(event, opts, (_err: BusinessError): void => { /* ignore */ });
  }

  build() {
    Column({ space: 8 }) {
      Text('D2SVPN')
        .fontSize(15).fontWeight(FontWeight.Bold)
        .width('100%')
      Button('打开主窗口')
        .width('100%')
        .onClick((): void => { this.fire(EV_TRAY_OPEN); })
      Button('退出')
        .width('100%')
        .backgroundColor('#E0413A')
        .onClick((): void => { this.fire(EV_TRAY_EXIT); })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .justifyContent(FlexAlign.Center)
  }
}
