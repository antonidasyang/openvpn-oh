import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import { vpnExtension } from '@kit.NetworkKit';
import commonEventManager from '@ohos.commonEventManager';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

import { OvpnEngine, OvpnTunConfig, OvpnEvent, OvpnProtectRequest,
         OvpnTunAddress, OvpnTunRoute, OvpnTunDns } from '../service/OvpnEngine';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnNotification } from '../service/VpnNotification';
import { ExtTray } from '../service/ExtTray';
import {
  EV_COMMAND_STOP, EV_COMMAND_PAUSE, EV_COMMAND_RESUME, EV_COMMAND_CREDS,
  EV_STATE_CHANGED, EV_LOG_LINE, EV_STATS_UPDATE, EV_TRAY_OPEN, EV_TRAY_EXIT,
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
  private bundleName: string = '';
  private tray: ExtTray = new ExtTray();
  // Saved so the tray's 重连 can rebuild the tunnel from scratch.
  private connectParams?: Record<string, Object>;
  // Appended to error messages so the on-screen red text reveals whether the
  // private-key password actually reached this (separate) process.
  private diag: string = '';

  async onCreate(want: Want): Promise<void> {
    log.info('onCreate', JSON.stringify(want.parameters ?? {}));
    this.bundleName = want.bundleName ?? '';
    await ProfileStore.init(this.context);
    await CredentialStore.init(this.context);
    VpnNotification.init(this.context, this.bundleName);
    await this.tray.init(this.context, (code: string): void => { this.onTrayAction(code); });
    this.connection = vpnExtension.createVpnConnection(this.context);
    await this.subscribeCommands();

    const params = want.parameters ?? ({} as Record<string, Object>);
    const action: string = (params['action'] as string) ?? '';
    const profileId: string = (params['profileId'] as string) ?? '';
    if (action === 'connect' && profileId) {
      await this.startTunnel(profileId, params);
    }
  }

  async onDestroy(): Promise<void> {
    log.info('onDestroy');
    this.tray.cancel();
    await VpnNotification.cancel();
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
      events: [EV_COMMAND_STOP, EV_COMMAND_PAUSE, EV_COMMAND_RESUME, EV_COMMAND_CREDS,
               EV_TRAY_OPEN, EV_TRAY_EXIT],
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
    if (data.event === EV_TRAY_EXIT) {
      this.onTrayAction('exit');
      return;
    }
    if (data.event === EV_TRAY_OPEN) {
      // The left-click popup opens the main window via its own UIExtension
      // context; nothing to do here.
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

  private async startTunnel(profileId: string, params: Record<string, Object>): Promise<void> {
    this.connectParams = params;
    // Prefer the profile payload carried in the Want — preferences is not
    // cross-process safe, so ProfileStore.get may not see what the UI saved.
    // Fall back to ProfileStore only if the Want did not carry the config.
    const configText: string = (params['configText'] as string) ?? '';
    let profile: Profile | undefined;
    if (configText) {
      profile = {
        id: profileId,
        displayName: (params['displayName'] as string) ?? profileId,
        configText,
        remoteHost: '', remotePort: '', remoteProto: '',
        autologin: (params['autologin'] as boolean) ?? false,
        privateKeyPasswordRequired: (params['privateKeyPasswordRequired'] as boolean) ?? false,
        staticChallenge: '', staticChallengeEcho: false,
        externalPki: false, createdAt: 0, lastConnectedAt: 0,
      };
    } else {
      profile = ProfileStore.get(profileId);
    }
    if (!profile) {
      this.broadcastState('CONFIG_ERROR', 'profile not found', 1, profileId, '');
      this.terminate();
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

    const keyPassword: string = (params['privateKeyPassword'] as string) ?? '';
    // Diagnostic: confirm whether a private-key password actually reached the
    // extension. Records only the length, never the secret itself.
    this.diag = `pkLen=${keyPassword.length} fromWant=${configText.length > 0}`;
    log.info('startTunnel config', this.diag + ` configLen=${profile.configText.length}`);
    this.engine.configure({
      content: profile.configText,
      guiVersion: 'openvpn-oh/0.1',
      compressionMode: 'yes',
      tunPersist: false,
      privateKeyPassword: keyPassword,
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
    const mkRoute = (addr: string, prefix: number, ipv6: boolean): vpnExtension.RouteInfo => {
      const route: vpnExtension.RouteInfo = {
        // HarmonyOS names the third-party VPN tun "vpn-tun"; a wrong name makes
        // the route a no-op so nothing is ever sent into the tunnel.
        interface: 'vpn-tun',
        destination: {
          address: { address: addr, family: ipv6 ? 2 : 1 },
          prefixLength: prefix,
        },
        gateway: { address: ipv6 ? '::' : '0.0.0.0', family: ipv6 ? 2 : 1 },
        hasGateway: false,
        isDefaultRoute: prefix === 0,
      };
      return route;
    };
    const routes: vpnExtension.RouteInfo[] = cfg.routes
      .filter((r: OvpnTunRoute): boolean => !r.exclude)
      .map((r: OvpnTunRoute): vpnExtension.RouteInfo => mkRoute(r.address, r.prefix, r.ipv6));
    // redirect-gateway only sets reroute flags; openvpn3 does NOT emit an
    // explicit 0.0.0.0/0 route, so we must add the default route ourselves or
    // nothing past the tun subnet is reachable.
    const hasV4Default = routes.some((r: vpnExtension.RouteInfo): boolean =>
      r.destination.prefixLength === 0 && r.destination.address.family === 1);
    const hasV6Default = routes.some((r: vpnExtension.RouteInfo): boolean =>
      r.destination.prefixLength === 0 && r.destination.address.family === 2);
    if (cfg.rerouteIpv4 && !hasV4Default) routes.push(mkRoute('0.0.0.0', 0, false));
    if (cfg.rerouteIpv6 && !hasV6Default) routes.push(mkRoute('::', 0, true));

    const dnsAddresses: string[] = cfg.dns.map((d: OvpnTunDns): string => d.address);
    const hasV4 = cfg.rerouteIpv4 || cfg.addresses.some((a: OvpnTunAddress): boolean => !a.ipv6);
    const hasV6 = cfg.rerouteIpv6 || cfg.addresses.some((a: OvpnTunAddress): boolean => a.ipv6);

    // Diagnostic: what did the server actually push?
    const addrSummary = cfg.addresses.map((a: OvpnTunAddress): string => `${a.address}/${a.prefix}`).join(',');
    const routeSummary = routes.map((r: vpnExtension.RouteInfo): string =>
      `${r.destination.address.address}/${r.destination.prefixLength}`).join(',');
    log.info('establishTun',
      `addrs=[${addrSummary}] routes=[${routeSummary}] reroute4=${cfg.rerouteIpv4} reroute6=${cfg.rerouteIpv6} dns=[${dnsAddresses.join(',')}] mtu=${cfg.mtu}`);

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
    // Keep the system-tray icon (+ notification) in sync with the tunnel.
    if (ev.name === 'CONNECTED') {
      this.tray.show(this.currentProfileName);
      VpnNotification.show('D2SVPN', `已连接 ${this.currentProfileName}`, this.currentProfileId);
    } else if (ev.name === 'RECONNECTING') {
      this.tray.show(this.currentProfileName);
      VpnNotification.show('D2SVPN', `重新连接 ${this.currentProfileName}…`, this.currentProfileId);
    }
    if (ev.name === 'DISCONNECTED' || ev.fatal) {
      this.tray.cancel();
      this.stopStatsTimer();
      setTimeout((): void => this.terminate(), 500);
    }
  }

  // ---------- Tray menu actions (run in this extension process) ----------

  private onTrayAction(code: string): void {
    if (code === 'dis') {
      this.engine?.stop();           // -> DISCONNECTED -> tray.cancel + terminate
    } else if (code === 'rec') {
      this.reconnect().catch((e: Object): void => log.error('reconnect failed', e));
    } else if (code === 'exit') {
      try { this.engine?.stop(); } catch (e) { log.warn('exit stop threw', e as Object); }
      this.tray.cancel();
      this.terminate();
    }
    // 'open' is a notifyOnly:false menu action: the system launches
    // EntryAbility directly, so it never reaches here.
  }

  // Full restart of the tunnel from the saved connect params (no window).
  private async reconnect(): Promise<void> {
    const params = this.connectParams;
    const pid = this.currentProfileId;
    if (!params) return;
    this.stopStatsTimer();
    if (this.engine) {
      // Detach the listener first so the old engine's DISCONNECTED doesn't
      // trigger tray.cancel + terminate while we're rebuilding.
      try { this.engine.setEventListener((_ev: OvpnEvent): void => { /* ignore */ }); } catch (e) { /* ignore */ }
      try { this.engine.stop(); } catch (e) { log.warn('reconnect stop threw', e as Object); }
      this.engine.dispose();
      this.engine = undefined;
    }
    if (this.connection) {
      try { this.connection.destroy(); } catch (e) { log.warn('reconnect destroy threw', e as Object); }
      this.connection = undefined;
    }
    this.connection = vpnExtension.createVpnConnection(this.context);
    await this.startTunnel(pid, params);
  }

  // VpnExtensionContext has no terminateSelf(), unlike UIAbilityContext.
  // The supported way to stop a VPN extension is to ask the framework to
  // stop it via vpnExtension.stopVpnExtensionAbility with a Want pointing
  // back at this ability.
  private terminate(): void {
    const want: Want = {
      bundleName: this.bundleName,
      abilityName: 'OvpnVpnExtensionAbility',
    };
    vpnExtension.stopVpnExtensionAbility(want).catch((e: Object): void => {
      log.warn('stopVpnExtensionAbility(self) failed', e);
    });
  }

  private onEngineLog(line: string): void {
    this.broadcast(EV_LOG_LINE, line);
  }

  private broadcastState(phase: string, info: string, code: number,
                         profileId: string, profileName: string): void {
    // Surface the diagnostic in on-screen error text since the extension's
    // hilog runs in a separate process that's hard to capture.
    const text = code > 0 && this.diag ? `${info} [${this.diag}]` : info;
    const payload: StateChangedPayload = { phase, info: text, errorCode: code, profileId, profileName };
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

