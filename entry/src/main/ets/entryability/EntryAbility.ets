import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { Profile } from '../model/Profile';
import { logger } from '../util/Logger';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from '../service/VpnController';
import { TrayService } from '../service/TrayService';
import { EV_BG_TERMINATE } from '../service/CommonEvents';

const log = logger('EntryAbility');

// PC tray keepalive model (see HarmonyOS "PC 应用通过系统托盘后台保活"):
// - Closing the window is intercepted in onPrepareToTerminate -> hideAbility(),
//   so the app drops off the taskbar but stays alive via BackGroundAbility (a
//   hidden process bound to the tray icon, started by TrayService.holdStatusBar).
// - Left-click the tray icon -> showAbility() brings the window back.
// - A real exit (system tray / Dock 退出) terminates BackGroundAbility, which
//   publishes EV_BG_TERMINATE; we then remove the tray and terminateSelf().
export default class EntryAbility extends UIAbility {
  private bgSubscriber?: commonEventManager.CommonEventSubscriber;

  async onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    log.info('onCreate');
    await ProfileStore.init(this.context);
    await CredentialStore.init(this.context);
    await VpnController.init(this.context);
    try {
      await notificationManager.requestEnableNotification(this.context);
    } catch (e) {
      log.warn('requestEnableNotification failed', e as Object);
    }
    await this.subscribeBgTerminate();
    await this.handleNotifAction(want);
  }

  async onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    await this.handleNotifAction(want);
  }

  // Act on a tap from the tray/notification reconnect action.
  private async handleNotifAction(want: Want): Promise<void> {
    const params = want.parameters ?? ({} as Record<string, Object>);
    const action: string = (params['notifAction'] as string) ?? '';
    if (action === 'reconnect') {
      const pid: string = (params['profileId'] as string) ?? '';
      const p: Profile | undefined = ProfileStore.get(pid);
      if (p) {
        const kp: string = await CredentialStore.loadKeyPassword(p.id);
        await VpnController.connect(p, kp);
      }
    }
  }

  // Closing the window must NOT quit the app: hide it and stay alive (the tray +
  // BackGroundAbility keep us running, off the taskbar). Returning true cancels
  // the termination. The real exit path is the system tray/Dock 退出, handled via
  // EV_BG_TERMINATE below.
  onPrepareToTerminate(): boolean {
    log.info('onPrepareToTerminate -> hideAbility (stay resident in tray)');
    this.context.hideAbility()
      .then((): void => { log.info('hideAbility OK'); })
      .catch((e: BusinessError): void => { log.warn('hideAbility failed', e as Object); });
    return true;
  }

  // BackGroundAbility tells us it's being destroyed (user picked the real 退出).
  // Tear down the tunnel + tray and terminate ourselves for a clean full exit.
  private async subscribeBgTerminate(): Promise<void> {
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [EV_BG_TERMINATE] };
    try {
      this.bgSubscriber = await commonEventManager.createSubscriber(info);
      commonEventManager.subscribe(this.bgSubscriber,
        (err: BusinessError, _data: commonEventManager.CommonEventData): void => {
          if (err) return;
          log.info('EV_BG_TERMINATE -> exiting');
          this.doExit();
        });
    } catch (e) {
      log.warn('subscribeBgTerminate failed', e as Object);
    }
  }

  private async doExit(): Promise<void> {
    try { await VpnController.stop(); } catch (e) { log.warn('stop on exit failed', e as Object); }
    try { TrayService.remove(); } catch (e) { /* ignore */ }
    try { await this.context.terminateSelf(); } catch (e) { log.warn('terminateSelf failed', e as Object); }
  }

  async onDestroy(): Promise<void> {
    try { await VpnController.dispose(); } catch (e) { /* ignore */ }
    if (this.bgSubscriber) {
      try { await commonEventManager.unsubscribe(this.bgSubscriber); } catch (e) { /* ignore */ }
      this.bgSubscriber = undefined;
    }
    // Backstop: ensure no extension process is left behind on exit.
    try {
      await this.context.getApplicationContext().killAllProcesses();
    } catch (e) {
      log.warn('killAllProcesses on destroy failed', e as Object);
    }
  }

  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    await stage.loadContent('pages/Index', (err) => {
      if (err) log.error('loadContent failed', err);
    });
    // Add the tray icon + right-click menu, then start the tray-attached
    // keepalive process (TrayService.init -> holdStatusBar).
    TrayService.init(this.context);
  }
}
