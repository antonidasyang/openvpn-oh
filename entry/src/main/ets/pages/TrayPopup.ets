import { common, Want } from '@kit.AbilityKit';

// Left-click popup for the tray icon. Runs in the StatusBarView UIExtension
// process. "打开主窗口" launches EntryAbility via this UIExtension's own
// context. Exit lives only in the right-click menu (TrayService.exitApp), which
// runs in the UI process and can actually tear the app down — a 退出 button
// here would be a dead duplicate (this process can't kill the UI process).
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
      const ctx = this.getUIContext().getHostContext() as common.UIExtensionContext;
      ctx.startAbility(want).catch((e: Object): void => {
        console.error('tray open failed', JSON.stringify(e));
      });
    } catch (e) {
      console.error('tray open ctx failed', JSON.stringify(e));
    }
  }

  build() {
    Column({ space: 8 }) {
      Text('D2SVPN')
        .fontSize(15).fontWeight(FontWeight.Bold)
        .width('100%')
      Button('打开主窗口')
        .width('100%')
        .onClick((): void => { this.openMain(); })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .justifyContent(FlexAlign.Center)
  }
}
