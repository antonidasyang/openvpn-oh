import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';
import { EV_TRAY_NOTICE, TrayNoticePayload } from '../service/CommonEvents';
import { logger } from '../util/Logger';

const log = logger('NoticeAbility');

// A tiny toast window. On this PC firmware a tray VPN-op menu click always
// raises the ability named in the menu action (notifyOnly is ignored), so
// rather than fight it, the 连接/断开 menu items name THIS ability. It shows
// "正在连接 X… / 已连接 X / 已断开 X / 连接失败" (pushed by EntryAbility's
// rightMenuClick handler over EV_TRAY_NOTICE) and closes itself. The actual VPN
// work happens in EntryAbility; this window is only feedback.
export default class NoticeAbility extends UIAbility {
  private sub?: commonEventManager.CommonEventSubscriber;
  private closeTimer: number = -1;
  private guardTimer: number = -1;

  async onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    AppStorage.setOrCreate<string>('noticeText', '请稍候…');
    await this.subscribe();
    this.armGuard();
  }

  async onNewWant(_want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    // Raised again by another tray click while still open — restart the guard so
    // the fresh action gets its full display time.
    this.armGuard();
  }

  // Never linger: hard timeout even if no terminal notice arrives.
  private armGuard(): void {
    if (this.guardTimer >= 0) clearTimeout(this.guardTimer);
    this.guardTimer = setTimeout((): void => { this.close(); }, 12000);
  }

  private async subscribe(): Promise<void> {
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [EV_TRAY_NOTICE] };
    try {
      this.sub = await commonEventManager.createSubscriber(info);
      commonEventManager.subscribe(this.sub,
        (err: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (err) return;
          try {
            const p = JSON.parse(data.data ?? '{}') as TrayNoticePayload;
            AppStorage.setOrCreate<string>('noticeText', p.text);
            if (this.closeTimer >= 0) clearTimeout(this.closeTimer);
            if (p.done) {
              // terminal message ("已连接 / 已断开 / 连接失败") — linger briefly, then close.
              this.closeTimer = setTimeout((): void => { this.close(); }, 1600);
            }
          } catch (e) { /* ignore bad payload */ }
        });
    } catch (e) {
      log.warn('subscribe failed', e as Object);
    }
  }

  private close(): void {
    this.context.terminateSelf()
      .catch((e: Object): void => { log.warn('terminateSelf failed', e); });
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Notice', (err): void => {
      if (err) log.error('loadContent failed', err);
    });
    // Shrink to a small toast, just big enough for the text. Use the ASYNC
    // getMainWindow() so the window is fully ready — the earlier SYNC resize ran
    // too early and collapsed the window into a thin sliver.
    stage.getMainWindow().then((win: window.Window): void => {
      win.resize(340, 150).catch((e: Object): void => { log.warn('resize failed', e); });
    }).catch((e: Object): void => { log.warn('getMainWindow failed', e); });
  }

  async onDestroy(): Promise<void> {
    if (this.sub) {
      try { await commonEventManager.unsubscribe(this.sub); } catch (e) { /* ignore */ }
      this.sub = undefined;
    }
    if (this.closeTimer >= 0) { clearTimeout(this.closeTimer); this.closeTimer = -1; }
    if (this.guardTimer >= 0) { clearTimeout(this.guardTimer); this.guardTimer = -1; }
  }
}
