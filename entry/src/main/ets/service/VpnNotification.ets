import notificationManager from '@ohos.notificationManager';
import wantAgent from '@ohos.app.ability.wantAgent';
import { common } from '@kit.AbilityKit';
import { EV_COMMAND_STOP } from './CommonEvents';
import { logger } from '../util/Logger';

const log = logger('VpnNotification');
const NOTIF_ID = 4201;

// Ongoing notification published by the VPN extension (the process that stays
// alive while the tunnel is up). Acts as the "tray" surrogate on HarmonyOS:
// shows status and 断开 / 重连 / 打开 action buttons. HarmonyOS has no
// third-party system-tray API, so this is the closest equivalent.
class VpnNotificationImpl {
  private ctx?: common.Context;
  private bundleName: string = '';

  init(ctx: common.Context, bundleName: string): void {
    this.ctx = ctx;
    this.bundleName = bundleName;
  }

  async show(title: string, text: string, profileId: string): Promise<void> {
    try {
      // Open / reconnect re-launch the UI ability (carrying a notifAction);
      // disconnect publishes a CommonEvent so it works without a window.
      const openInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: this.bundleName, abilityName: 'EntryAbility',
          parameters: { 'notifAction': 'open' } as Record<string, Object>,
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 10,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const reconnectInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: this.bundleName, abilityName: 'EntryAbility',
          parameters: { 'notifAction': 'reconnect', 'profileId': profileId } as Record<string, Object>,
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 11,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const disconnectInfo: wantAgent.WantAgentInfo = {
        wants: [{ action: EV_COMMAND_STOP }],
        operationType: wantAgent.OperationType.SEND_COMMON_EVENT,
        requestCode: 12,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const openA = await wantAgent.getWantAgent(openInfo);
      const reconnectA = await wantAgent.getWantAgent(reconnectInfo);
      const disconnectA = await wantAgent.getWantAgent(disconnectInfo);

      const req: notificationManager.NotificationRequest = {
        id: NOTIF_ID,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        wantAgent: openA,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: text },
        },
        actionButtons: [
          { title: '断开', wantAgent: disconnectA },
          { title: '重连', wantAgent: reconnectA },
          { title: '打开', wantAgent: openA },
        ],
      };
      await notificationManager.publish(req);
    } catch (e) {
      log.warn('publish notification failed', e as Object);
    }
  }

  async cancel(): Promise<void> {
    try {
      await notificationManager.cancel(NOTIF_ID);
    } catch (e) {
      log.warn('cancel notification failed', e as Object);
    }
  }
}

export const VpnNotification = new VpnNotificationImpl();
