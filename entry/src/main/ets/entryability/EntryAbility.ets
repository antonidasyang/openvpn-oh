import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import { Profile } from '../model/Profile';
import { logger } from '../util/Logger';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from '../service/VpnController';
import { TrayService } from '../service/TrayService';

const log = logger('EntryAbility');

export default class EntryAbility extends UIAbility {
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

  async onDestroy(): Promise<void> {
    // The app exits via the system tray's 退出 (which terminates this UIAbility).
    // But the VPN extension and statusBarView extension run as separate
    // processes that outlive the UIAbility — leaving the app "running" (DevEco's
    // red square stays lit, tray icon lingers). Tear the tunnel down and kill
    // every process of the app so exit is clean.
    try { await VpnController.stop(); } catch (e) { log.warn('stop on destroy failed', e as Object); }
    try { await VpnController.dispose(); } catch (e) { /* ignore */ }
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

    // Tray icon + right-click menu, owned by this (always-alive) UI process.
    TrayService.init(this.context);

    // Close button -> minimize instead of quitting, so the app process (and
    // therefore the VPN tunnel) keeps running. Returning true intercepts the
    // close. Full quit is available from the tray's 退出 menu item. (A
    // third-party app can't drop the taskbar entry while staying alive —
    // window.hide() is a system API and a windowless process can't hold the
    // tray; so taskbar + tray coexist.)
    try {
      stage.on('windowStageClose', (): boolean => {
        try {
          stage.getMainWindowSync().minimize();
        } catch (e) {
          log.warn('minimize on close failed', e as Object);
        }
        return true;
      });
    } catch (e) {
      log.warn('windowStageClose not supported', e as Object);
    }
  }
}
