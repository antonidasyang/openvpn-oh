import commonEventManager from '@ohos.commonEventManager';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { EV_TRAY_EXIT } from '../service/CommonEvents';

// Left-click popup for the tray icon. Runs in the StatusBarView UIExtension
// process. "打开主窗口" launches EntryAbility via this UIExtension's own
// context; "退出" tells the VPN extension (which owns the tray) to quit.
@Entry
@Component
struct TrayPopup {
  private openMain(): void {
    const want: Want = {
      bundleName: 'com.d2ssoft.ovpn',
      abilityName: 'EntryAbility',
      moduleName: 'entry',
    };
    try {
      const ctx = getContext(this) as common.UIExtensionContext;
      ctx.startAbility(want).catch((e: Object): void => {
        console.error('tray open failed', JSON.stringify(e));
      });
    } catch (e) {
      console.error('tray open ctx failed', JSON.stringify(e));
    }
  }

  private exit(): void {
    const opts: commonEventManager.CommonEventPublishData = {};
    commonEventManager.publish(EV_TRAY_EXIT, opts, (_err: BusinessError): void => { /* ignore */ });
  }

  build() {
    Column({ space: 8 }) {
      Text('D2SVPN')
        .fontSize(15).fontWeight(FontWeight.Bold)
        .width('100%')
      Button('打开主窗口')
        .width('100%')
        .onClick((): void => { this.openMain(); })
      Button('退出')
        .width('100%')
        .backgroundColor('#E0413A')
        .onClick((): void => { this.exit(); })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .justifyContent(FlexAlign.Center)
  }
}
