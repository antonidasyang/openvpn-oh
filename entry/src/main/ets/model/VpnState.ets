// Mirrors openvpn3's CONNECTING/RECONNECTING/CONNECTED/etc. event names so the
// UI can map directly. See client/cli.cpp in openvpn3 for the canonical list.
export type Phase =
  | 'DISCONNECTED'
  | 'RESOLVE'
  | 'TCP_CONNECT'
  | 'UDP_CONNECT'
  | 'WAIT'
  | 'AUTH'
  | 'GET_CONFIG'
  | 'ASSIGN_IP'
  | 'ADD_ROUTES'
  | 'CONNECTED'
  | 'RECONNECTING'
  | 'PAUSE'
  | 'RESUME'
  | 'ERROR';

export interface Stats {
  bytesIn: bigint;
  bytesOut: bigint;
  packetsIn: bigint;
  packetsOut: bigint;
}

const EMPTY_STATS: Stats = {
  bytesIn:    0n,
  bytesOut:   0n,
  packetsIn:  0n,
  packetsOut: 0n,
};

// Single global ObservedV2 so UI pages can `@Local s = VpnState.instance` and
// have any change re-render automatically.
@ObservedV2
export class VpnStateData {
  @Trace phase: Phase = 'DISCONNECTED';
  @Trace activeProfileId: string = '';
  @Trace activeProfileName: string = '';
  @Trace lastError: string = '';
  @Trace lastEventInfo: string = '';
  @Trace stats: Stats = EMPTY_STATS;
  @Trace connectedSince: number = 0;  // epoch ms; 0 when not connected
  @Trace logLines: string[] = [];

  setPhase(p: Phase, info: string = ''): void {
    this.phase = p;
    this.lastEventInfo = info;
    if (p === 'CONNECTED' && this.connectedSince === 0) {
      this.connectedSince = Date.now();
    }
    if (p === 'DISCONNECTED' || p === 'ERROR') {
      this.connectedSince = 0;
    }
  }

  setError(msg: string): void {
    this.lastError = msg;
    this.phase = 'ERROR';
    this.connectedSince = 0;
  }

  setStats(s: Stats): void {
    this.stats = s;
  }

  appendLog(line: string): void {
    // Ring buffer — keep only the last 500 lines so the array stays cheap to
    // diff in ArkUI's reactivity layer.
    if (this.logLines.length > 500) {
      this.logLines = this.logLines.slice(-500);
    }
    this.logLines.push(line);
  }

  reset(): void {
    this.phase = 'DISCONNECTED';
    this.activeProfileId = '';
    this.activeProfileName = '';
    this.lastError = '';
    this.lastEventInfo = '';
    this.stats = EMPTY_STATS;
    this.connectedSince = 0;
  }
}

export const VpnState = new VpnStateData();
