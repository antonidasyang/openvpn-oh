import statusBarManager from '@hms.pcService.statusBarManager';
import image from '@ohos.multimedia.image';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from './VpnController';
import { EV_STATE_CHANGED, StateChangedPayload, EV_TRAY_OPEN, EV_TRAY_EXIT } from './CommonEvents';
import { logger } from '../util/Logger';

const log = logger('TrayService');

// System-tray (status bar) integration for HarmonyOS PC / 2-in-1 via
// @hms.pcService.statusBarManager. Provides the persistent tray icon plus a
// right-click menu: every profile with connect / disconnect / reconnect, and
// open-window / exit. Menu clicks are identified by menuCode through the
// 'rightMenuClick' event (StatusBarMenuAction has no parameters field).
class TrayServiceImpl {
  private ctx?: common.UIAbilityContext;
  private icon?: statusBarManager.StatusBarIcon;
  private installed: boolean = false;
  private phase: string = 'DISCONNECTED';
  private activeId: string = '';
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private unsubProfiles?: () => void;

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.installed) return;
    if (!canIUse('SystemCapability.PCService.StatusBarManager')) {
      log.info('status bar not supported on this device; skipping tray');
      return;
    }
    this.ctx = ctx;
    try {
      this.icon = await this.loadIcon(ctx);
      const item: statusBarManager.StatusBarItem = {
        icons: this.icon,
        quickOperation: {
          title: 'D2SVPN',
          height: 160,
          abilityName: 'StatusBarViewAbility',
          moduleName: 'entry',
        },
        statusBarGroupMenu: this.buildMenu(),
        hoverTips: 'D2SVPN',
      };
      statusBarManager.addToStatusBar(ctx, item);
      this.installed = true;
    } catch (e) {
      log.warn('tray install failed', e as Object);
      return;
    }
    this.registerEvents();
    this.unsubProfiles = ProfileStore.subscribe((): void => { this.refresh(); });
    await this.subscribeState();
  }

  private async loadIcon(ctx: common.UIAbilityContext): Promise<statusBarManager.StatusBarIcon> {
    const white = await this.pixmap(ctx, 'tray_white.png');
    const black = await this.pixmap(ctx, 'tray_black.png');
    return { white, black };
  }

  private async pixmap(ctx: common.UIAbilityContext, name: string): Promise<image.PixelMap> {
    const raw: Uint8Array = ctx.resourceManager.getRawFileContentSync(name);
    const ab: ArrayBuffer = raw.buffer.slice(0) as ArrayBuffer;
    const src = image.createImageSource(ab);
    return await src.createPixelMap();
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
    const appGroup: statusBarManager.StatusBarMenuItem[] = [
      { title: '打开主窗口', menuAction: this.action('open') },
      { title: '退出', menuAction: this.action('exit') },
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
    return { abilityName: 'EntryAbility', moduleName: 'entry', notifyOnly: true, menuCode: code };
  }

  refresh(): void {
    if (!this.ctx || !this.installed) return;
    try {
      statusBarManager.updateStatusBarMenu(this.ctx, this.buildMenu());
    } catch (e) {
      log.warn('updateStatusBarMenu failed', e as Object);
    }
  }

  remove(): void {
    if (!this.ctx || !this.installed) return;
    try { statusBarManager.removeFromStatusBar(this.ctx); } catch (e) { /* ignore */ }
    this.installed = false;
  }

  private registerEvents(): void {
    try {
      statusBarManager.on('rightMenuClick', (ev: emitter.EventData): void => {
        const code = this.codeOf(ev);
        log.info('rightMenuClick', `${code} raw=${JSON.stringify(ev)}`);
        if (code) this.dispatch(code);
      });
    } catch (e) {
      log.warn('on(rightMenuClick) failed', e as Object);
    }
  }

  private codeOf(ev: emitter.EventData): string {
    const d = ev.data as Record<string, Object> | undefined;
    if (!d) return '';
    const c = d['menuCode'];
    return typeof c === 'string' ? c as string : '';
  }

  private dispatch(code: string): void {
    if (code === 'open') { this.openWindow(); return; }
    if (code === 'exit') { this.exitApp(); return; }
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

  private openWindow(): void {
    if (!this.ctx) return;
    window.getLastWindow(this.ctx)
      .then((w: window.Window): Promise<void> => w.showWindow())
      .catch((e: Object): void => log.warn('showWindow failed', e as Object));
  }

  private exitApp(): void {
    VpnController.stop();
    this.remove();
    if (this.ctx) this.ctx.terminateSelf();
  }

  private async subscribeState(): Promise<void> {
    const info: commonEventManager.CommonEventSubscribeInfo = {
      events: [EV_STATE_CHANGED, EV_TRAY_OPEN, EV_TRAY_EXIT],
    };
    this.subscriber = await commonEventManager.createSubscriber(info);
    commonEventManager.subscribe(this.subscriber,
      (err: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (err) return;
        if (data.event === EV_TRAY_OPEN) { this.openWindow(); return; }
        if (data.event === EV_TRAY_EXIT) { this.exitApp(); return; }
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
