import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
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
  }

  async onDestroy(): Promise<void> {
    await VpnController.dispose();
  }

  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    await stage.loadContent('pages/Index', (err) => {
      if (err) log.error('loadContent failed', err);
    });

    // On 2-in-1/PC, intercept the title-bar close button: instead of exiting,
    // minimize so the app (and the VPN tunnel) keeps running in the background.
    // Returning false cancels the close. Wrapped in try/catch because this
    // event is only available on desktop-class devices.
    try {
      stage.on('windowStageClose', (): boolean => {
        try {
          stage.getMainWindowSync().minimize();
        } catch (e) {
          log.warn('minimize on close failed', e as Object);
        }
        return false;
      });
    } catch (e) {
      log.warn('windowStageClose not supported', e as Object);
    }
  }
}
