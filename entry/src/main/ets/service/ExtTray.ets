import statusBarManager from '@hms.pcService.statusBarManager';
import image from '@ohos.multimedia.image';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { logger } from '../util/Logger';

const log = logger('ExtTray');

// System-tray (status bar) icon owned by the VPN EXTENSION process. The
// extension is windowless and stays alive while the tunnel is up, so it can
// hold the tray after the main window (and its taskbar entry) is closed —
// which is the only non-privileged way to get "tray, no taskbar". The icon
// exists only while connected; disconnecting removes it.
//
// Right-click menu codes ('dis' / 'rec' / 'exit') are delivered via the
// 'rightMenuClick' event (StatusBarMenuAction has no parameters); 'open' starts
// EntryAbility directly. The owner passes an onAction handler.
export class ExtTray {
  private ctx?: common.Context;
  private icon?: statusBarManager.StatusBarIcon;
  private shown: boolean = false;
  private onAction?: (code: string) => void;

  async init(ctx: common.Context, onAction: (code: string) => void): Promise<void> {
    this.ctx = ctx;
    this.onAction = onAction;
    if (!canIUse('SystemCapability.PCService.StatusBarManager')) {
      log.info('status bar unsupported; tray disabled');
      return;
    }
    try {
      this.icon = await this.loadIcon(ctx);
    } catch (e) {
      log.warn('tray icon load failed', e as Object);
    }
    try {
      statusBarManager.on('rightMenuClick', (ev: emitter.EventData): void => {
        const d = ev.data as Record<string, Object> | undefined;
        const c = d ? d['menuCode'] : undefined;
        const code = typeof c === 'string' ? c as string : '';
        if (code && this.onAction) this.onAction(code);
      });
    } catch (e) {
      log.warn('on(rightMenuClick) failed', e as Object);
    }
  }

  private async loadIcon(ctx: common.Context): Promise<statusBarManager.StatusBarIcon> {
    const white = await this.pix(ctx, 'tray_white.png');
    const black = await this.pix(ctx, 'tray_black.png');
    return { white, black };
  }

  private async pix(ctx: common.Context, name: string): Promise<image.PixelMap> {
    const raw: Uint8Array = ctx.resourceManager.getRawFileContentSync(name);
    const ab: ArrayBuffer = raw.buffer.slice(0) as ArrayBuffer;
    return await image.createImageSource(ab).createPixelMap();
  }

  // Show (or refresh) the tray for the connected profile.
  show(profileName: string): void {
    if (!this.ctx) { log.error('tray show: no context'); return; }
    if (!this.icon) { log.error('tray show: icon not loaded'); return; }
    try {
      if (this.shown) {
        statusBarManager.updateStatusBarMenu(this.ctx, this.menu(profileName));
      } else {
        const item: statusBarManager.StatusBarItem = {
          icons: this.icon,
          quickOperation: {
            title: 'D2SVPN', height: 160,
            abilityName: 'StatusBarViewAbility', moduleName: 'entry',
          },
          statusBarGroupMenu: this.menu(profileName),
          hoverTips: `D2SVPN — 已连接 ${profileName}`,
        };
        statusBarManager.addToStatusBar(this.ctx, item);
        this.shown = true;
        log.info('addToStatusBar OK');
      }
    } catch (e) {
      log.error('addToStatusBar FAILED', JSON.stringify(e));
    }
  }

  cancel(): void {
    if (!this.ctx || !this.shown) return;
    try { statusBarManager.removeFromStatusBar(this.ctx); } catch (e) { /* ignore */ }
    this.shown = false;
  }

  private menu(name: string): statusBarManager.StatusBarGroupMenu[] {
    const status: statusBarManager.StatusBarMenuItem = {
      title: `已连接：${name}`, menuAction: this.act('open', false),
    };
    const ctrl: statusBarManager.StatusBarMenuItem[] = [
      { title: '断开', menuAction: this.act('dis', true) },
      { title: '重连', menuAction: this.act('rec', true) },
    ];
    const appg: statusBarManager.StatusBarMenuItem[] = [
      { title: '打开主窗口', menuAction: this.act('open', false) },
      { title: '退出', menuAction: this.act('exit', true) },
    ];
    return [[status], ctrl, appg];
  }

  // notify=false starts EntryAbility directly (reliable open); notify=true
  // routes through rightMenuClick so the extension can act in-process.
  private act(code: string, notify: boolean): statusBarManager.StatusBarMenuAction {
    return { abilityName: 'EntryAbility', moduleName: 'entry', notifyOnly: notify, menuCode: code };
  }
}
