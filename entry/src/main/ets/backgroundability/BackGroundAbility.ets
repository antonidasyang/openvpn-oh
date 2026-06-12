import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { vpnExtension } from '@kit.NetworkKit';
import statusBarManager from '@hms.pcService.statusBarManager';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { EV_BG_TERMINATE, EV_COMMAND_STOP, EV_TRAY_REINSTALL } from '../service/CommonEvents';
import { logger } from '../util/Logger';

const log = logger('BackGroundAbility');

// Tray-attached keepalive process. EntryAbility starts this with
// ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM + StartupVisibility.STARTUP_HIDE,
// so it runs hidden in its own process bound to the status-bar (tray) icon and
// keeps the app alive on PC after the main window is gone.
//
// On a real app exit (user picks the system tray / Dock 退出), this ability is
// terminated. EntryAbility may already be terminateSelf()'d at that point (the
// hide path), so we cannot rely on it doing the teardown: publish
// EV_BG_TERMINATE for the alive case, AND run the full cleanup ourselves —
// stop the VPN extension, drop the tray icon, then kill every app process.
export default class BackGroundAbility extends UIAbility {
  private cleanedUp: boolean = false;
  // Set while EntryAbility reinstalls the tray icon (remove + re-add on every
  // Entry launch). If the icon removal terminates us during this window, it is
  // NOT a user exit — skip the cleanup; Entry restarts us right after.
  private reinstallUntil: number = 0;
  private reinstallSub?: commonEventManager.CommonEventSubscriber;

  onCreate(): void {
    log.info('onCreate (tray keepalive process)');
    this.subscribeReinstall();
  }

  private async subscribeReinstall(): Promise<void> {
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [EV_TRAY_REINSTALL] };
    try {
      this.reinstallSub = await commonEventManager.createSubscriber(info);
      commonEventManager.subscribe(this.reinstallSub,
        (err: BusinessError, _data: commonEventManager.CommonEventData): void => {
          if (err) return;
          log.info('EV_TRAY_REINSTALL: ignoring termination for 5s');
          this.reinstallUntil = Date.now() + 5000;
        });
    } catch (e) {
      log.warn('subscribeReinstall failed', e as Object);
    }
  }

  private inReinstallWindow(): boolean {
    return Date.now() < this.reinstallUntil;
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    // Started hidden (STARTUP_HIDE); a minimal page just satisfies the lifecycle.
    stage.loadContent('pages/Blank', (err): void => {
      if (err) log.error('loadContent failed', err);
    });
  }

  onPrepareToTerminate(): boolean {
    if (this.inReinstallWindow()) {
      log.info('onPrepareToTerminate during tray reinstall -> just die, no app exit');
      return false;
    }
    log.info('onPrepareToTerminate -> full app exit');
    const opts: commonEventManager.CommonEventPublishData = {};
    commonEventManager.publish(EV_BG_TERMINATE, opts, (err: BusinessError): void => {
      if (err) log.error('publish EV_BG_TERMINATE failed', err);
    });
    this.fullCleanup();
    // Return false: allow THIS ability to terminate once cleanup has run.
    return false;
  }

  onDestroy(): void {
    if (this.reinstallSub) {
      try { commonEventManager.unsubscribe(this.reinstallSub); } catch (e) { /* ignore */ }
      this.reinstallSub = undefined;
    }
    // Backstop in case the system destroys us without onPrepareToTerminate —
    // but never during a tray reinstall (Entry is about to restart us).
    if (!this.inReinstallWindow()) this.fullCleanup();
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
  }

  // Tear the whole app down from this process: EntryAbility may be dead (hidden
  // via terminateSelf), so nobody else will stop the VPN or remove the tray.
  private async fullCleanup(): Promise<void> {
    if (this.cleanedUp) return;
    this.cleanedUp = true;
    const empty: commonEventManager.CommonEventPublishData = {};
    try {
      commonEventManager.publish(EV_COMMAND_STOP, empty, (err: BusinessError): void => {
        if (err) log.warn('publish EV_COMMAND_STOP failed', err);
      });
    } catch (e) { /* ignore */ }
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: 'OvpnVpnExtensionAbility',
    };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
      log.info('stopVpnExtensionAbility OK');
    } catch (e) {
      log.warn('stopVpnExtensionAbility failed (may already be stopped)', e as Object);
    }
    try {
      if (canIUse('SystemCapability.PCService.StatusBarManager')) {
        statusBarManager.removeFromStatusBar(this.context);
      }
    } catch (e) { /* ignore: may fail with no foreground window */ }
    // Give a still-alive EntryAbility a moment to finish its own doExit path
    // before the hammer.
    await this.delay(800);
    try {
      await this.context.getApplicationContext().killAllProcesses();
    } catch (e) {
      log.warn('killAllProcesses failed', e as Object);
    }
  }
}
