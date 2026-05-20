import { vpnExtension } from '@kit.NetworkKit';
import commonEventManager from '@ohos.commonEventManager';
import { Want } from '@kit.AbilityKit';

import { OvpnEngine, OvpnTunConfig, OvpnEvent } from '../service/OvpnEngine';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import {
  EV_COMMAND_STOP, EV_COMMAND_PAUSE, EV_COMMAND_RESUME, EV_COMMAND_CREDS,
  EV_STATE_CHANGED, EV_LOG_LINE, EV_STATS_UPDATE,
  CredsCommandPayload, StateChangedPayload, StatsPayload,
} from '../service/CommonEvents';
import { logger } from '../util/Logger';

const log = logger('OvpnVpnAbility');

// Runs in its own process. Owns the OvpnEngine and the VpnConnection. All
// commands from the UI arrive as CommonEvent broadcasts; state goes back out
// the same way.

export default class OvpnVpnExtensionAbility extends vpnExtension.VpnExtensionAbility {
  private engine?: OvpnEngine;
  private connection?: vpnExtension.VpnConnection;
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private statsTimer: number = -1;
  private currentProfileId: string = '';
  private currentProfileName: string = '';

  async onCreate(want: Want): Promise<void> {
    log.info('onCreate', JSON.stringify(want.parameters ?? {}));
    await ProfileStore.init(this.context);
    await CredentialStore.init(this.context);
    this.connection = vpnExtension.createVpnConnection(this.context);
    await this.subscribeCommands();

    const action = (want.parameters?.['action'] as string) ?? '';
    const profileId = (want.parameters?.['profileId'] as string) ?? '';
    if (action === 'connect' && profileId) {
      await this.startTunnel(profileId);
    }
  }

  async onDestroy(): Promise<void> {
    log.info('onDestroy');
    this.stopStatsTimer();
    if (this.engine) {
      try { this.engine.stop(); } catch (e) { log.warn('engine stop threw', e as Object); }
      this.engine.dispose();
      this.engine = undefined;
    }
    if (this.connection) {
      try { this.connection.destroy(); } catch (e) { log.warn('VpnConnection.destroy threw', e as Object); }
      this.connection = undefined;
    }
    if (this.subscriber) {
      await commonEventManager.unsubscribe(this.subscriber);
      this.subscriber = undefined;
    }
  }

  // ---------- Command subscription ----------

  private async subscribeCommands(): Promise<void> {
    const info: commonEventManager.CommonEventSubscribeInfo = {
      events: [EV_COMMAND_STOP, EV_COMMAND_PAUSE, EV_COMMAND_RESUME, EV_COMMAND_CREDS],
    };
    this.subscriber = await commonEventManager.createSubscriber(info);
    commonEventManager.subscribe(this.subscriber, (err, data) => {
      if (err) { log.error('subscribe failed', err as Object); return; }
      this.handleCommand(data).catch(e => log.error('command failed', e as Object));
    });
  }

  private async handleCommand(data: commonEventManager.CommonEventData): Promise<void> {
    switch (data.event) {
      case EV_COMMAND_STOP:
        this.engine?.stop();
        return;
      case EV_COMMAND_PAUSE:
        this.engine?.pause(data.data ?? 'user');
        return;
      case EV_COMMAND_RESUME:
        this.engine?.resume();
        return;
      case EV_COMMAND_CREDS: {
        try {
          const p = JSON.parse(data.data ?? '{}') as CredsCommandPayload;
          this.engine?.provideCreds(p.username, p.password, p.cachePassword);
          if (this.currentProfileId) {
            await CredentialStore.save(this.currentProfileId, p.username, p.password, p.cachePassword);
          }
        } catch (e) {
          log.error('creds payload bad', e as Object);
        }
        return;
      }
    }
  }

  // ---------- Tunnel lifecycle ----------

  private async startTunnel(profileId: string): Promise<void> {
    const profile = ProfileStore.get(profileId);
    if (!profile) {
      this.broadcastState('CONFIG_ERROR', 'profile not found', 1, profileId, '');
      this.context.terminateSelf();
      return;
    }
    this.currentProfileId = profile.id;
    this.currentProfileName = profile.displayName;

    this.engine = new OvpnEngine();
    this.engine.setEventListener(ev => this.onEngineEvent(ev));
    this.engine.setLogListener(line => this.onEngineLog(line));
    this.engine.setProtectHandler(async (req) => {
      if (!this.connection) return false;
      try {
        await this.connection.protect(req.fd);
        return true;
      } catch (e) {
        log.error('VpnConnection.protect failed', e as Object);
        return false;
      }
    });
    this.engine.setTunHandler(cfg => this.establishTun(cfg));

    this.engine.configure({
      content: profile.configText,
      guiVersion: 'openvpn-oh/0.1',
      compressionMode: 'yes',
      tunPersist: false,
    });

    // Auto-login profiles can connect immediately; user/pass profiles need
    // creds before connect(), which the UI will deliver via EV_COMMAND_CREDS.
    if (profile.autologin) {
      this.engine.startConnect();
    } else {
      const cached = await CredentialStore.load(profile.id);
      if (cached && cached.cached && cached.password) {
        this.engine.provideCreds(cached.username, cached.password, true);
        this.engine.startConnect();
      } else {
        this.broadcastState('AUTH', 'awaiting credentials', 0,
                            this.currentProfileId, this.currentProfileName);
        // The UI shows a credentials prompt and submits via EV_COMMAND_CREDS,
        // and then dispatches connect via another connect call.
        // For now we still kick off connect; openvpn3 will fire its auth
        // event and the UI can respond.
        this.engine.startConnect();
      }
    }

    this.startStatsTimer();
  }

  private async establishTun(cfg: OvpnTunConfig): Promise<number> {
    if (!this.connection) {
      log.error('establishTun with no connection');
      return -1;
    }
    const vpnConfig: vpnExtension.VpnConfig = {
      addresses: cfg.addresses.map(a => ({
        address: { address: a.address, family: a.ipv6 ? 2 : 1 },
        prefixLength: a.prefix,
      })),
      routes: cfg.routes.filter(r => !r.exclude).map(r => ({
        interface: 'tun',
        destination: {
          address: { address: r.address, family: r.ipv6 ? 2 : 1 },
          prefixLength: r.prefix,
        },
        hasGateway: false,
        isDefaultRoute: r.prefix === 0,
      })),
      dnsAddresses: cfg.dns.map(d => d.address),
      searchDomains: cfg.searchDomains,
      mtu: cfg.mtu,
      isIPv4Accepted: cfg.rerouteIpv4 || cfg.addresses.some(a => !a.ipv6),
      isIPv6Accepted: cfg.rerouteIpv6 || cfg.addresses.some(a => a.ipv6),
      isInternal: false,
      isBlocking: false,
      trustedApplications: [],
      blockedApplications: [],
    };
    try {
      const fd = await this.connection.create(vpnConfig);
      log.info('VpnConnection.create -> fd', fd);
      return fd;
    } catch (e) {
      log.error('VpnConnection.create failed', e as Object);
      return -1;
    }
  }

  // ---------- Engine event plumbing ----------

  private onEngineEvent(ev: OvpnEvent): void {
    log.info('event', ev.name, ev.info);
    this.broadcastState(ev.name, ev.info, ev.code,
                        this.currentProfileId, this.currentProfileName);
    if (ev.name === 'DISCONNECTED' || ev.fatal) {
      this.stopStatsTimer();
      // Let the system tear us down after a brief grace period so the UI
      // sees the final state event.
      setTimeout(() => this.context.terminateSelf(), 500);
    }
  }

  private onEngineLog(line: string): void {
    this.broadcast(EV_LOG_LINE, line);
  }

  private broadcastState(phase: string, info: string, code: number,
                         profileId: string, profileName: string): void {
    const payload: StateChangedPayload = { phase, info, errorCode: code, profileId, profileName };
    this.broadcast(EV_STATE_CHANGED, JSON.stringify(payload));
  }

  private broadcast(event: string, data: string): void {
    commonEventManager.publish(event, { data }, () => { /* ignore */ });
  }

  // ---------- Stats polling ----------

  private startStatsTimer(): void {
    this.stopStatsTimer();
    this.statsTimer = setInterval(() => {
      if (!this.engine) return;
      try {
        const s = this.engine.getStats();
        const payload: StatsPayload = {
          bytesIn:    Number(s.tun.bytesIn),
          bytesOut:   Number(s.tun.bytesOut),
          packetsIn:  Number(s.tun.packetsIn),
          packetsOut: Number(s.tun.packetsOut),
        };
        this.broadcast(EV_STATS_UPDATE, JSON.stringify(payload));
      } catch (e) {
        log.warn('stats poll failed', e as Object);
      }
    }, 1000);
  }

  private stopStatsTimer(): void {
    if (this.statsTimer !== -1) {
      clearInterval(this.statsTimer);
      this.statsTimer = -1;
    }
  }
}
