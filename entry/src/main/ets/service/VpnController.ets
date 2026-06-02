import { vpnExtension } from '@kit.NetworkKit';
import commonEventManager from '@ohos.commonEventManager';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

import { Profile } from '../model/Profile';
import { VpnState, Phase, Stats } from '../model/VpnState';
import {
  EV_COMMAND_CONNECT, EV_COMMAND_STOP, EV_COMMAND_PAUSE, EV_COMMAND_RESUME, EV_COMMAND_CREDS,
  EV_STATE_CHANGED, EV_LOG_LINE, EV_STATS_UPDATE,
  ConnectCommandPayload, CredsCommandPayload, StateChangedPayload, StatsPayload,
} from './CommonEvents';
import { logger } from '../util/Logger';

const log = logger('VpnController');

// Drives the OvpnVpnExtensionAbility from the UI process. Owns no engine
// state itself — its only job is to start/stop the ability and pipe
// CommonEvent traffic into the global VpnState observable.

const PHASE_MAP: Record<string, Phase> = {
  'RESOLVE':       'RESOLVE',
  'TCP_CONNECT':   'TCP_CONNECT',
  'UDP_CONNECT':   'UDP_CONNECT',
  'WAIT':          'WAIT',
  'AUTH':          'AUTH',
  'AUTH_FAILED':   'ERROR',
  'GET_CONFIG':    'GET_CONFIG',
  'ASSIGN_IP':     'ASSIGN_IP',
  'ADD_ROUTES':    'ADD_ROUTES',
  'CONNECTED':     'CONNECTED',
  'RECONNECTING':  'RECONNECTING',
  'PAUSE':         'PAUSE',
  'RESUME':        'RESUME',
  'DISCONNECTED':  'DISCONNECTED',
  'CONNECT_ERROR': 'ERROR',
  'CONFIG_ERROR':  'ERROR',
  'FATAL':         'ERROR',
};

class VpnControllerImpl {
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private context?: common.UIAbilityContext;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.subscriber) return;

    const info: commonEventManager.CommonEventSubscribeInfo = {
      events: [EV_STATE_CHANGED, EV_LOG_LINE, EV_STATS_UPDATE],
    };
    this.subscriber = await commonEventManager.createSubscriber(info);
    commonEventManager.subscribe(this.subscriber,
      (err: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (err) {
          log.error('subscribe error', err);
          return;
        }
        this.handleEvent(data);
      });
  }

  async dispose(): Promise<void> {
    if (this.subscriber) {
      await commonEventManager.unsubscribe(this.subscriber);
      this.subscriber = undefined;
    }
  }

  async connect(profile: Profile, keyPassword: string = ''): Promise<void> {
    if (!this.context) throw new Error('VpnController not initialised');

    VpnState.activeProfileId = profile.id;
    VpnState.activeProfileName = profile.displayName;
    VpnState.setPhase('RESOLVE', 'starting tunnel');
    VpnState.lastError = '';

    // Pass the full profile payload through the Want. The extension runs in a
    // separate process and @ohos.data.preferences is not cross-process safe, so
    // we cannot rely on the extension re-reading the profile from ProfileStore.
    const params: Record<string, Object> = {
      'action': 'connect',
      'profileId': profile.id,
      'displayName': profile.displayName,
      'configText': profile.configText,
      'autologin': profile.autologin,
      'privateKeyPasswordRequired': profile.privateKeyPasswordRequired,
    };
    // Private-key password decrypts the inline client key; openvpn3 needs it on
    // the Config before parse, so it travels with the connect Want.
    if (keyPassword) params['privateKeyPassword'] = keyPassword;
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: 'OvpnVpnExtensionAbility',
      parameters: params,
    };

    try {
      await vpnExtension.startVpnExtensionAbility(want);
      const payload: ConnectCommandPayload = { profileId: profile.id };
      const opts: commonEventManager.CommonEventPublishData = { data: JSON.stringify(payload) };
      await this.publish(EV_COMMAND_CONNECT, opts);
    } catch (e) {
      const err = e as BusinessError;
      log.error('startVpnExtensionAbility failed', err);
      const msg = err.message ?? String(err);
      VpnState.setError(`Failed to start VPN: ${msg}`);
      throw new Error(msg);
    }
  }

  async stop(): Promise<void> {
    if (!this.context) return;
    const empty: commonEventManager.CommonEventPublishData = {};
    await this.publish(EV_COMMAND_STOP, empty);
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: 'OvpnVpnExtensionAbility',
    };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
    } catch (e) {
      log.warn('stopVpnExtensionAbility failed (may already be stopped)', e as Object);
    }
  }

  async pause(reason: string = 'user'): Promise<void> {
    const opts: commonEventManager.CommonEventPublishData = { data: reason };
    await this.publish(EV_COMMAND_PAUSE, opts);
  }

  async resume(): Promise<void> {
    const empty: commonEventManager.CommonEventPublishData = {};
    await this.publish(EV_COMMAND_RESUME, empty);
  }

  async submitCreds(username: string, password: string, cache: boolean): Promise<void> {
    const payload: CredsCommandPayload = { username, password, cachePassword: cache };
    const opts: commonEventManager.CommonEventPublishData = { data: JSON.stringify(payload) };
    await this.publish(EV_COMMAND_CREDS, opts);
  }

  // ----- Event handling -----

  private handleEvent(data: commonEventManager.CommonEventData): void {
    if (data.event === EV_STATE_CHANGED) {
      try {
        const p = JSON.parse(data.data ?? '{}') as StateChangedPayload;
        const phase = PHASE_MAP[p.phase] ?? 'ERROR';
        VpnState.setPhase(phase, p.info);
        if (p.errorCode > 0) VpnState.lastError = p.info;
        if (p.profileId) VpnState.activeProfileId = p.profileId;
        if (p.profileName) VpnState.activeProfileName = p.profileName;
      } catch (e) {
        log.warn('bad state payload', e as Object);
      }
      return;
    }
    if (data.event === EV_LOG_LINE) {
      VpnState.appendLog(data.data ?? '');
      return;
    }
    if (data.event === EV_STATS_UPDATE) {
      try {
        const s = JSON.parse(data.data ?? '{}') as StatsPayload;
        const stats: Stats = {
          bytesIn:    BigInt(s.bytesIn),
          bytesOut:   BigInt(s.bytesOut),
          packetsIn:  BigInt(s.packetsIn),
          packetsOut: BigInt(s.packetsOut),
        };
        VpnState.setStats(stats);
      } catch (e) {
        log.warn('bad stats payload', e as Object);
      }
    }
  }

  private async publish(event: string, opts: commonEventManager.CommonEventPublishData): Promise<void> {
    await new Promise<void>((resolve: () => void, reject: (e: BusinessError) => void): void => {
      commonEventManager.publish(event, opts, (err: BusinessError): void => {
        if (err) reject(err); else resolve();
      });
    });
  }
}

export const VpnController = new VpnControllerImpl();
