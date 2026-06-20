import statusBarManager from '@hms.pcService.statusBarManager';
import image from '@ohos.multimedia.image';
import { common, Want, StartOptions, contextConstant } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from './VpnController';
import { EV_STATE_CHANGED, StateChangedPayload } from './CommonEvents';
import { logger } from '../util/Logger';

const log = logger('TrayService');

// System-tray (status bar) integration for HarmonyOS PC / 2-in-1 via
// @hms.pcService.statusBarManager. Provides the persistent tray icon, a
// right-click menu (per profile: connect / disconnect / reconnect, plus
// 打开主窗口), left-click -> showAbility, and the tray-attached keepalive process
// (holdStatusBar). Right-click menu clicks are identified by menuCode through
// the 'rightMenuClick' event. There is no custom 退出 — the system attaches its
// own 退出 to the tray icon, whose termination is handled via BackGroundAbility.
class TrayServiceImpl {
  private ctx?: common.UIAbilityContext;
  private icon?: statusBarManager.StatusBarIcon;
  private installed: boolean = false;
  private phase: string = 'DISCONNECTED';
  private activeId: string = '';
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private unsubProfiles?: () => void;
  private lastSig: string = '';

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
  }

  // PATH B step 1 — called by EntryAbility (the bootstrapper). Add the tray icon.
  // The item MUST exist before starting an ability attached to it (startMain).
  async installIcon(ctx: common.UIAbilityContext): Promise<void> {
    if (!canIUse('SystemCapability.PCService.StatusBarManager')) {
      log.info('status bar not supported on this device; skipping tray');
      return;
    }
    this.ctx = ctx;
    // Clear any stale icon a previous run may have left behind, so addToStatusBar
    // does not stack a second icon (each with its own system 退出).
    try {
      statusBarManager.removeFromStatusBar(ctx);
      log.info('removeFromStatusBar (clear stale) OK');
    } catch (e) {
      log.info('removeFromStatusBar (clear stale) skipped', JSON.stringify(e));
    }
    try {
      this.icon = await this.loadIcon(ctx);
      const item: statusBarManager.StatusBarItem = {
        icons: this.icon,
        quickOperation: {
          // Empty abilityName => left-click shows no popup; MainAbility handles
          // it via the 'statusBarIconClick' event and calls showAbility().
          title: 'D2SVPN',
          height: 30,
          abilityName: '',
          moduleName: 'entry',
        },
        statusBarGroupMenu: this.buildMenu(),
        hoverTips: 'D2SVPN',
      };
      statusBarManager.addToStatusBar(ctx, item);
      this.installed = true;
      this.lastSig = this.menuSig();   // menu already set by addToStatusBar
      log.info('installIcon: addToStatusBar OK (bootstrapper)');
    } catch (e) {
      log.error('installIcon: addToStatusBar FAILED', JSON.stringify(e));
    }
  }

  // PATH B step 2 — called by EntryAbility. Start the REAL main window as an
  // ability ATTACHED to the tray item, shown immediately (STARTUP_SHOW). Being
  // attached is what (a) keeps the app alive when the bootstrapper exits and
  // (b) lets MainAbility hideAbility()/showAbility() off and onto the taskbar.
  async startMain(ctx: common.UIAbilityContext): Promise<void> {
    const want: Want = {
      bundleName: ctx.abilityInfo.bundleName,
      abilityName: 'MainAbility',
      moduleName: 'entry',
    };
    const options: StartOptions = {
      processMode: contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
      startupVisibility: contextConstant.StartupVisibility.STARTUP_SHOW,
    };
    await ctx.startAbility(want, options);
    log.info('startMain: attached MainAbility started (STARTUP_SHOW)');
  }

  // PATH B step 3 — called by MainAbility (the resident process). Wire up tray
  // click handlers + live menu/state updates from the process that stays alive.
  async attachHandlers(ctx: common.UIAbilityContext): Promise<void> {
    if (!canIUse('SystemCapability.PCService.StatusBarManager')) return;
    this.ctx = ctx;
    this.installed = true;
    this.registerEvents();
    this.unsubProfiles = ProfileStore.subscribe((): void => { this.refresh(); });
    await this.subscribeState();
    log.info('attachHandlers: tray handlers wired (resident process)');
  }

  private async loadIcon(ctx: common.UIAbilityContext): Promise<statusBarManager.StatusBarIcon> {
    const white = await this.pixmap(ctx, 'tray_white.png');
    const black = await this.pixmap(ctx, 'tray_black.png');
    return { white, black };
  }

  private async pixmap(ctx: common.UIAbilityContext, name: string): Promise<image.PixelMap> {
    try {
      const raw: Uint8Array = ctx.resourceManager.getRawFileContentSync(name);
      const ab: ArrayBuffer = raw.buffer.slice(0) as ArrayBuffer;
      const src = image.createImageSource(ab);
      return await src.createPixelMap();
    } catch (e) {
      log.error('pixmap load failed', e as Object);
      throw e as Error;
    }
  }

  private connectedFor(id: string): boolean {
    return this.activeId === id && this.phase !== 'DISCONNECTED' && this.phase !== 'ERROR';
  }

  private buildMenu(): statusBarManager.StatusBarGroupMenu[] {
    const profiles = ProfileStore.list();
    const profileGroup: statusBarManager.StatusBarMenuItem[] = profiles.map(
      (p: Profile): statusBarManager.StatusBarMenuItem => {
        const sub: statusBarManager.StatusBarSubMenuItem[] = this.connectedFor(p.id)
          ? [this.subItem('断开', 'dis|' + p.id), this.subItem('重连', 'rec|' + p.id)]
          : [this.subItem('连接', 'con|' + p.id)];
        const mi: statusBarManager.StatusBarMenuItem = { title: p.displayName, subMenu: sub };
        return mi;
      });
    // NOTE: no 退出 here on purpose. The system attaches its own default tray
    // menu (app icon + 退出) to every status-bar icon, and that OS-level 退出
    // properly destroys the process. Adding our own 退出 produced a visible
    // duplicate ("two 退出"). menuCode lives on StatusBarMenuAction (the field
    // exists on API 23 / 6.1.0; StatusBarMenuItem.menuCode is only since API24).
    //
    // Hide path is hideAbility() (the UI process stays alive), so the in-process
    // 'rightMenuClick' listener handles 打开主窗口 -> showAbility(). notifyOnly:true
    // = emitter event to this live process.
    const appGroup: statusBarManager.StatusBarMenuItem[] = [
      { title: '打开主窗口', menuAction: this.action('open') },
    ];
    const groups: statusBarManager.StatusBarGroupMenu[] = [];
    if (profileGroup.length > 0) groups.push(profileGroup);
    groups.push(appGroup);
    return groups;
  }

  private subItem(title: string, code: string): statusBarManager.StatusBarSubMenuItem {
    return { subTitle: title, menuAction: this.action(code) };
  }

  private action(code: string): statusBarManager.StatusBarMenuAction {
    return { abilityName: 'MainAbility', moduleName: 'entry', notifyOnly: true, menuCode: code };
  }

  // A compact signature of everything the menu depends on, so we only call
  // updateStatusBarMenu when it actually changes (the API is rate-limited:
  // error 1010710003 'called too frequently').
  private menuSig(): string {
    const profiles = ProfileStore.list();
    const parts = profiles.map((p: Profile): string =>
      `${p.id}:${p.displayName}:${this.connectedFor(p.id) ? 1 : 0}`);
    return parts.join('|') + '#' + this.activeId;
  }

  refresh(): void {
    if (!this.ctx || !this.installed) return;
    const sig = this.menuSig();
    if (sig === this.lastSig) return;
    this.lastSig = sig;
    try {
      if (canIUse('SystemCapability.PCService.StatusBarManager')) {
        statusBarManager.updateStatusBarMenu(this.ctx, this.buildMenu());
      }
    } catch (e) {
      log.warn('updateStatusBarMenu failed', e as Object);
    }
  }

  remove(): void {
    if (!this.ctx || !this.installed) return;
    try {
      if (canIUse('SystemCapability.PCService.StatusBarManager')) {
        statusBarManager.removeFromStatusBar(this.ctx);
      }
    } catch (e) { /* ignore */ }
    this.installed = false;
  }

  private registerEvents(): void {
    try {
      if (canIUse('SystemCapability.PCService.StatusBarManager')) {
        statusBarManager.on('rightMenuClick', (ev: emitter.EventData): void => {
          const code = this.codeOf(ev);
          log.info('rightMenuClick', `${code} raw=${JSON.stringify(ev)}`);
          if (code) this.dispatch(code);
        });
        // Left-click the tray icon -> bring the main window back to front.
        statusBarManager.on('statusBarIconClick', (ev: emitter.EventData): void => {
          const d = ev.data as Record<string, Object> | undefined;
          const kind = d ? d['iconClickType'] : undefined;
          if (kind === 'leftClick') this.openWindow();
        });
      }
    } catch (e) {
      log.warn('on(statusBar click) failed', e as Object);
    }
  }

  private codeOf(ev: emitter.EventData): string {
    const d = ev.data as Record<string, Object> | undefined;
    if (!d) return '';
    // The code may arrive under a few different keys across device versions.
    const keys: string[] = ['menuCode', 'code', 'menuId', 'id'];
    for (const k of keys) {
      const c = d[k];
      if (typeof c === 'string' && (c as string).length > 0) return c as string;
    }
    return '';
  }

  private dispatch(code: string): void {
    if (code === 'open') { this.openWindow(); return; }
    const sep = code.indexOf('|');
    if (sep < 0) return;
    const verb = code.substring(0, sep);
    const id = code.substring(sep + 1);
    if (verb === 'dis') { VpnController.stop(); return; }
    if (verb === 'con' || verb === 'rec') { this.connectProfile(id); return; }
  }

  private async connectProfile(id: string): Promise<void> {
    const p = ProfileStore.get(id);
    if (!p) return;
    const kp = await CredentialStore.loadKeyPassword(id);
    await VpnController.connect(p, kp);
  }

  // Bring the (hidden) main window back to the foreground. showAbility() is the
  // counterpart to EntryAbility's hideAbility() in onPrepareToTerminate.
  private openWindow(): void {
    const ctx = this.ctx;
    if (!ctx) return;
    ctx.showAbility()
      .then((): void => { log.info('showAbility OK'); })
      .catch((e: Object): void => { log.warn('showAbility failed', e as Object); });
  }

  private async subscribeState(): Promise<void> {
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [EV_STATE_CHANGED] };
    this.subscriber = await commonEventManager.createSubscriber(info);
    commonEventManager.subscribe(this.subscriber,
      (err: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (err) return;
        try {
          const p = JSON.parse(data.data ?? '{}') as StateChangedPayload;
          this.phase = p.phase;
          if (p.profileId) this.activeId = p.profileId;
          this.refresh();
        } catch (e) { /* ignore */ }
      });
  }
}

export const TrayService = new TrayServiceImpl();
