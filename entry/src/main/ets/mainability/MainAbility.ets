import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import { BusinessError } from '@ohos.base';
import { Profile } from '../model/Profile';
import { logger } from '../util/Logger';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from '../service/VpnController';
import { TrayService } from '../service/TrayService';

const log = logger('MainAbility');

// PATH B — the real main window lives here, NOT in EntryAbility.
//
// Why: UIAbilityContext.hideAbility()/showAbility() only work on an ability that
// was started via startAbility with processMode = NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM
// (or ATTACH_TO_STATUS_BAR_ITEM) — per the official .d.ts. EntryAbility is the
// launcher home ability (entity.system.home), which is NOT attached, so
// hideAbility() on it never removes the taskbar entry. MainAbility IS started
// attached (by EntryAbility, the bootstrapper), so:
//   - close the window -> onPrepareToTerminate -> hideAbility(): the window
//     leaves the TASKBAR but the ability/process stays alive (VPN keeps running,
//     tray icon stays). This is the supported use of hideAbility.
//   - tray 打开主窗口 / left-click -> showAbility() restores the same window.
//
// HYPOTHESIS to verify on device: an attached, STARTUP_SHOW foreground UIAbility
// (a) shows its window with NO taskbar entry, and (b) keeps the whole app +
// VPN alive after EntryAbility (the caller that owns the tray item) terminateSelf()s.
// v1 deliberately omits the full 退出 teardown — confirm the core first.
export default class MainAbility extends UIAbility {
  async onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    log.info('onCreate (attached main UI host)');
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

  // Close button -> hide off the taskbar but stay resident. hideAbility() is
  // valid here because this ability was started attached to the status-bar item.
  // Returning true cancels the system's default termination.
  onPrepareToTerminate(): boolean {
    log.info('onPrepareToTerminate -> hideAbility (off taskbar, stay alive)');
    this.context.hideAbility()
      .then((): void => { log.info('hideAbility OK'); })
      .catch((e: BusinessError): void => { log.warn('hideAbility failed', e as Object); });
    return true;
  }

  async onDestroy(): Promise<void> {
    try { await VpnController.dispose(); } catch (e) { /* ignore */ }
  }

  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    await stage.loadContent('pages/Index', (err): void => {
      if (err) log.error('loadContent failed', err);
    });
    // The tray icon itself was added by EntryAbility (the caller) before it
    // started us attached. Here we only wire up the click handlers + live menu
    // updates from THIS (the resident) process.
    TrayService.attachHandlers(this.context);
  }
}
