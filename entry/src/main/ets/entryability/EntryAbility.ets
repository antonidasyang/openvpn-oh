import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import { Profile } from '../model/Profile';
import { logger } from '../util/Logger';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from '../service/VpnController';

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
    await VpnController.dispose();
  }

  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    await stage.loadContent('pages/Index', (err) => {
      if (err) log.error('loadContent failed', err);
    });
    // No close interception: closing the window terminates this UIAbility, so
    // the taskbar/dock entry disappears. While connected, the VPN extension is
    // a separate windowless process that keeps running and owns the tray icon —
    // that's the "close to tray, no taskbar" behaviour. Disconnected, there is
    // nothing to keep, so the app simply exits.
  }
}
