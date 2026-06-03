import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import notificationManager from '@ohos.notificationManager';
import { EVENT_CLOSE_REQUEST } from '../service/CommonEvents';
import { TrayService } from '../service/TrayService';
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

  // Act on a tap from the ongoing notification (e.g. its 重连 button).
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

    // Install the system-tray icon + menu (HarmonyOS PC). No-op on phones.
    TrayService.init(this.context);

    // On 2-in-1/PC, intercept the title-bar close button so we can ask the
    // user (minimize / background / exit) instead of just quitting. For
    // windowStageClose, returning TRUE keeps the window open (intercepts the
    // close); FALSE lets it close. Wrapped in try/catch because this event is
    // only available on desktop-class devices.
    try {
      stage.on('windowStageClose', (): boolean => {
        try {
          emitter.emit({ eventId: EVENT_CLOSE_REQUEST });
        } catch (e) {
          log.warn('emit close-request failed', e as Object);
        }
        return true;
      });
    } catch (e) {
      log.warn('windowStageClose not supported', e as Object);
    }
  }
}
