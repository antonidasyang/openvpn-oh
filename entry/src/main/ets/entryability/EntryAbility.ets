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

// PC tray keepalive model (per Huawei DevEco support: hideAbility() left the
// taskbar icon in place, so the official advice is to EXIT the UIAbility with
// terminateSelf() instead — that removes the taskbar entry):
// - Closing the window is intercepted in onPrepareToTerminate -> terminateSelf().
//   The UIAbility (and its taskbar icon) goes away; the app survives via
//   BackGroundAbility (hidden process bound to the tray icon, started by
//   TrayService.holdStatusBar), and the VPN tunnel survives in its own
//   VpnExtensionAbility process.
// - Tray right-click 打开主窗口 (notifyOnly:false) makes the SYSTEM start
//   EntryAbility again — no listener in this (dead) process is needed.
// - A real exit (system tray / Dock 退出) terminates BackGroundAbility, which
//   publishes EV_BG_TERMINATE (for when we are alive) and also tears everything
//   down itself (for when we are already terminated).
export default class EntryAbility extends UIAbility {
  private bgSubscriber?: commonEventManager.CommonEventSubscriber;
  // True only on the real exit path (doExit). Gates killAllProcesses in
  // onDestroy so a mere hide (terminateSelf) does not kill the VPN process.
  private fullExit: boolean = false;
  // Re-entrancy guard: if terminateSelf() triggers onPrepareToTerminate again,
  // let the termination proceed instead of looping.
  private terminating: boolean = false;

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

  // Closing the window must NOT quit the whole app, but hideAbility() proved to
  // leave the taskbar icon behind. Official guidance: exit this UIAbility with
  // terminateSelf() — no taskbar icon afterwards. The tray (BackGroundAbility
  // process) and the VPN tunnel (VpnExtensionAbility process) stay alive. The
  // real full exit is the system tray/Dock 退出, anchored in BackGroundAbility.
  onPrepareToTerminate(): boolean {
    if (this.terminating) return false;
    this.terminating = true;
    log.info('onPrepareToTerminate -> terminateSelf (official: leaves no taskbar icon)');
    this.context.terminateSelf()
      .then((): void => { log.info('terminateSelf OK'); })
      .catch((e: BusinessError): void => { log.warn('terminateSelf failed', e as Object); });
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
    this.fullExit = true;
    this.terminating = true;
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
    // Backstop on the REAL exit only: a hide (terminateSelf) must leave the
    // VPN extension and the tray keepalive process running.
    if (!this.fullExit) {
      log.info('onDestroy (hide): VPN + tray keepalive stay alive');
      return;
    }
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
