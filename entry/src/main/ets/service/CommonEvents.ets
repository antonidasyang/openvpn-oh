// Shared event names + payload shapes used to talk between the UI ability and
// the VpnExtensionAbility (which run in different processes). Both sides use
// @ohos.commonEventManager — it's the standard cross-process pub/sub on
// HarmonyOS NEXT.

export const EV_COMMAND_CONNECT = 'com.ovpn.harmony.cmd.connect';
export const EV_COMMAND_STOP    = 'com.ovpn.harmony.cmd.stop';
export const EV_COMMAND_PAUSE   = 'com.ovpn.harmony.cmd.pause';
export const EV_COMMAND_RESUME  = 'com.ovpn.harmony.cmd.resume';
export const EV_COMMAND_CREDS   = 'com.ovpn.harmony.cmd.creds';

// BackGroundAbility (the tray-attached keepalive process) -> EntryAbility:
// "I'm being terminated (user picked the system tray/Dock 退出)", so EntryAbility
// removes the tray icon and calls terminateSelf() for a clean full exit. See the
// HarmonyOS "PC 应用通过系统托盘后台保活" guide.
export const EV_BG_TERMINATE = 'com.ovpn.harmony.bg.terminate';

export const EV_STATE_CHANGED   = 'com.ovpn.harmony.evt.state';
export const EV_LOG_LINE        = 'com.ovpn.harmony.evt.log';
export const EV_STATS_UPDATE    = 'com.ovpn.harmony.evt.stats';

export interface ConnectCommandPayload {
  profileId: string;
}

export interface CredsCommandPayload {
  username: string;
  password: string;
  cachePassword: boolean;
}

export interface StateChangedPayload {
  phase: string;
  info: string;
  errorCode: number;
  profileId: string;
  profileName: string;
}

export interface StatsPayload {
  bytesIn: number;
  bytesOut: number;
  packetsIn: number;
  packetsOut: number;
}
