// Shared event names + payload shapes used to talk between the UI ability and
// the VpnExtensionAbility (which run in different processes). Both sides use
// @ohos.commonEventManager — it's the standard cross-process pub/sub on
// HarmonyOS NEXT.

export const EV_COMMAND_CONNECT = 'com.ovpn.harmony.cmd.connect';
export const EV_COMMAND_STOP    = 'com.ovpn.harmony.cmd.stop';
export const EV_COMMAND_PAUSE   = 'com.ovpn.harmony.cmd.pause';
export const EV_COMMAND_RESUME  = 'com.ovpn.harmony.cmd.resume';
export const EV_COMMAND_CREDS   = 'com.ovpn.harmony.cmd.creds';

// In-process (UI) emitter event id: ability -> page request to confirm close.
export const EVENT_CLOSE_REQUEST = 1001;

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
