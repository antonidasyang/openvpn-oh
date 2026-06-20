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
//   so the window goes away but the whole app stays ALIVE: the VPN tunnel keeps
//   running (its own VpnExtensionAbility process) and the tray icon stays
//   (BackGroundAbility keepalive process). hideAbility does NOT destroy this
//   ability, so showAbility() brings the same window back instantly.
// - NOTE: terminateSelf() was tried (per Huawei support, to drop the taskbar
//   icon) but it EXITS the whole app — tray keepalive + VPN both die. Confirmed
//   on device 2026-06. So we are back to hideAbility; the lingering taskbar icon
//   is a known limitation pending the correct off-taskbar-while-alive API.
// - Tray left-click / 打开主窗口 -> showAbility() restores the window.
// - A real exit (system tray / Dock 退出) terminates BackGroundAbility, which
//   publishes EV_BG_TERMINATE (for when we are alive) and also tears everything
//   down itself (for when we are already terminated).
export default class EntryAbility extends UIAbility {
  private bgSubscriber?: commonEventManager.CommonEventSubscriber;
  // Tracks whether our window is currently in the foreground. This is how we
  // tell apart the two ways onPrepareToTerminate fires:
  //   - window in FOREGROUND  -> user clicked the X button -> minimize to tray
  //   - window in BACKGROUND  -> app is already minimized and the user picked
  //     the system tray/Dock 退出 -> a REAL exit, let it terminate.
  private isForeground: boolean = false;

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

  onForeground(): void { this.isForeground = true; }
  onBackground(): void { this.isForeground = false; }

  // Two cases reach here (see isForeground above):
  //  - foreground: the X button -> hide to tray (return true cancels the exit),
  //    the window/process/VPN all stay alive; showAbility() restores it.
  //  - background: the app is minimized and the user picked the tray/Dock 退出
  //    -> a real exit. Return false so the system terminates us; onDestroy then
  //    tears everything (VPN + tray keepalive) down via killAllProcesses.
  onPrepareToTerminate(): boolean {
    if (!this.isForeground) {
      log.info('onPrepareToTerminate (backgrounded) -> real exit, allow terminate');
      return false;
    }
    log.info('onPrepareToTerminate (foreground) -> hideAbility (minimize to tray)');
    this.isForeground = false;
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

  // Triggered by BackGroundAbility (EV_BG_TERMINATE) if the real exit goes
  // through that path instead: just terminate ourselves -> onDestroy does the
  // full teardown.
  private async doExit(): Promise<void> {
    try { await this.context.terminateSelf(); } catch (e) { log.warn('terminateSelf failed', e as Object); }
  }

  // A minimize goes through hideAbility(), which does NOT destroy this ability,
  // so onDestroy only ever runs on a REAL exit (tray/Dock 退出, or the system
  // reclaiming us). Tear everything down: stop the VPN, drop the tray icon, then
  // kill every app process (the tray keepalive included).
  async onDestroy(): Promise<void> {
    log.info('onDestroy -> full exit teardown');
    if (this.bgSubscriber) {
      try { await commonEventManager.unsubscribe(this.bgSubscriber); } catch (e) { /* ignore */ }
      this.bgSubscriber = undefined;
    }
    try { await VpnController.stop(); } catch (e) { log.warn('stop on exit failed', e as Object); }
    try { await VpnController.dispose(); } catch (e) { /* ignore */ }
    try { TrayService.remove(); } catch (e) { /* ignore */ }
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
