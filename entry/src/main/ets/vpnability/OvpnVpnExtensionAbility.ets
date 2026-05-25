import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import { vpnExtension } from '@kit.NetworkKit';
import commonEventManager from '@ohos.commonEventManager';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

import { OvpnEngine, OvpnTunConfig, OvpnEvent, OvpnProtectRequest,
         OvpnTunAddress, OvpnTunRoute, OvpnTunDns } from '../service/OvpnEngine';
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

export default class OvpnVpnExtensionAbility extends VpnExtensionAbility {
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

    const params = want.parameters ?? ({} as Record<string, Object>);
    const action: string = (params['action'] as string) ?? '';
    const profileId: string = (params['profileId'] as string) ?? '';
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
    commonEventManager.subscribe(this.subscriber,
      (err: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (err) { log.error('subscribe failed', err); return; }
        this.handleCommand(data).catch((e: Object): void => log.error('command failed', e));
      });
  }

  private async handleCommand(data: commonEventManager.CommonEventData): Promise<void> {
    if (data.event === EV_COMMAND_STOP) {
      this.engine?.stop();
      return;
    }
    if (data.event === EV_COMMAND_PAUSE) {
      this.engine?.pause(data.data ?? 'user');
      return;
    }
    if (data.event === EV_COMMAND_RESUME) {
      this.engine?.resume();
      return;
    }
    if (data.event === EV_COMMAND_CREDS) {
      try {
        const p = JSON.parse(data.data ?? '{}') as CredsCommandPayload;
        this.engine?.provideCreds(p.username, p.password, p.cachePassword);
        if (this.currentProfileId) {
          await CredentialStore.save(this.currentProfileId, p.username, p.password, p.cachePassword);
        }
      } catch (e) {
        log.error('creds payload bad', e as Object);
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
    this.engine.setEventListener((ev: OvpnEvent): void => this.onEngineEvent(ev));
    this.engine.setLogListener((line: string): void => this.onEngineLog(line));
    this.engine.setProtectHandler(async (req: OvpnProtectRequest): Promise<boolean> => {
      if (!this.connection) return false;
      try {
        await this.connection.protect(req.fd);
        return true;
      } catch (e) {
        log.error('VpnConnection.protect failed', e as Object);
        return false;
      }
    });
    this.engine.setTunHandler((cfg: OvpnTunConfig): Promise<number> => this.establishTun(cfg));

    this.engine.configure({
      content: profile.configText,
      guiVersion: 'openvpn-oh/0.1',
      compressionMode: 'yes',
      tunPersist: false,
    });

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
    const addresses: vpnExtension.LinkAddress[] = cfg.addresses.map(
      (a: OvpnTunAddress): vpnExtension.LinkAddress => {
        const linkAddr: vpnExtension.LinkAddress = {
          address: { address: a.address, family: a.ipv6 ? 2 : 1 },
          prefixLength: a.prefix,
        };
        return linkAddr;
      }
    );
    const routes: vpnExtension.RouteInfo[] = cfg.routes
      .filter((r: OvpnTunRoute): boolean => !r.exclude)
      .map((r: OvpnTunRoute): vpnExtension.RouteInfo => {
        const route: vpnExtension.RouteInfo = {
          interface: 'tun',
          destination: {
            address: { address: r.address, family: r.ipv6 ? 2 : 1 },
            prefixLength: r.prefix,
          },
          gateway: { address: r.ipv6 ? '::' : '0.0.0.0', family: r.ipv6 ? 2 : 1 },
          hasGateway: false,
          isDefaultRoute: r.prefix === 0,
        };
        return route;
      });
    const dnsAddresses: string[] = cfg.dns.map((d: OvpnTunDns): string => d.address);
    const hasV4 = cfg.rerouteIpv4 || cfg.addresses.some((a: OvpnTunAddress): boolean => !a.ipv6);
    const hasV6 = cfg.rerouteIpv6 || cfg.addresses.some((a: OvpnTunAddress): boolean => a.ipv6);

    const vpnConfig: vpnExtension.VpnConfig = {
      addresses,
      routes,
      dnsAddresses,
      searchDomains: cfg.searchDomains,
      mtu: cfg.mtu,
      isIPv4Accepted: hasV4,
      isIPv6Accepted: hasV6,
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
      setTimeout((): void => this.context.terminateSelf(), 500);
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
    const opts: commonEventManager.CommonEventPublishData = { data };
    commonEventManager.publish(event, opts, (_err: BusinessError): void => { /* ignore */ });
  }

  // ---------- Stats polling ----------

  private startStatsTimer(): void {
    this.stopStatsTimer();
    this.statsTimer = setInterval((): void => {
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

