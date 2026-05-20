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
  }
}
