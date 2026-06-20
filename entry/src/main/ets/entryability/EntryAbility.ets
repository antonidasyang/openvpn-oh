import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from '../util/Logger';
import { ProfileStore } from '../model/ProfileStore';
import { TrayService } from '../service/TrayService';

const log = logger('EntryAbility');

// PATH B — EntryAbility is now only a BOOTSTRAPPER.
//
// It is the launcher home ability (entity.system.home), so the system always
// starts it. But the launcher home ability cannot be hidden off the taskbar
// (hideAbility only works on a status-bar-ATTACHED ability). So instead of
// hosting the UI here, we:
//   1. add the tray icon (addToStatusBar — required before an attached start),
//   2. start MainAbility attached to that tray item (STARTUP_SHOW) — that is the
//      real, resident main window, which CAN hide off the taskbar,
//   3. terminateSelf — our job is done; the attached MainAbility keeps the app
//      (and the VPN tunnel) alive.
//
// VERIFY on device: after this terminateSelf, the tray icon + MainAbility window
// + VPN must all survive (the documented "tray keepalive" intent). If they die,
// the tray item is bound to this caller's lifetime and EntryAbility must instead
// stay resident off-foreground (next iteration).
export default class EntryAbility extends UIAbility {
  async onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    log.info('onCreate (bootstrapper)');
    // Needed so the tray menu can list the profiles when we addToStatusBar.
    await ProfileStore.init(this.context);
  }

  async onWindowStageCreate(_stage: window.WindowStage): Promise<void> {
    // 1) add the tray icon (must exist before starting an attached ability),
    // 2) start the attached resident main window, 3) hand off and exit.
    try {
      await TrayService.installIcon(this.context);
      await TrayService.startMain(this.context);
    } catch (e) {
      log.error('bootstrap failed', e as Object);
    }
    log.info('bootstrap done -> terminateSelf');
    this.context.terminateSelf()
      .then((): void => { log.info('bootstrapper terminateSelf OK'); })
      .catch((e: Object): void => { log.warn('bootstrapper terminateSelf failed', e); });
  }
}
