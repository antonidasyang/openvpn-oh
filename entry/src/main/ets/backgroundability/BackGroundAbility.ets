import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { EV_BG_TERMINATE } from '../service/CommonEvents';
import { logger } from '../util/Logger';

const log = logger('BackGroundAbility');

// Tray-attached keepalive process. EntryAbility starts this with
// ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM + StartupVisibility.STARTUP_HIDE,
// so it runs hidden in its own process bound to the status-bar (tray) icon and
// keeps the app alive on PC after the main window is hidden.
//
// On a real app exit (user picks the system tray / Dock 退出), this ability is
// terminated. We intercept that in onPrepareToTerminate to notify EntryAbility,
// which then removes the tray icon and terminateSelf()s for a clean full exit.
export default class BackGroundAbility extends UIAbility {
  onCreate(): void {
    log.info('onCreate (tray keepalive process)');
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    // Started hidden (STARTUP_HIDE); a minimal page just satisfies the lifecycle.
    stage.loadContent('pages/Blank', (err): void => {
      if (err) log.error('loadContent failed', err);
    });
  }

  onPrepareToTerminate(): boolean {
    log.info('onPrepareToTerminate -> notify EntryAbility to exit cleanly');
    const opts: commonEventManager.CommonEventPublishData = {};
    commonEventManager.publish(EV_BG_TERMINATE, opts, (err: BusinessError): void => {
      if (err) log.error('publish EV_BG_TERMINATE failed', err);
    });
    // Return false: allow THIS ability to terminate. EntryAbility will tear down
    // the tray and terminate itself on the published event.
    return false;
  }
}
