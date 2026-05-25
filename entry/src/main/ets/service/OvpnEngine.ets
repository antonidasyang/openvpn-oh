import ovpn from 'libovpnclient.so';
import { logger } from '../util/Logger';

const log = logger('OvpnEngine');

export type OvpnTunConfig = ovpn.TunConfig;
export type OvpnTunAddress = ovpn.TunAddress;
export type OvpnTunRoute = ovpn.TunRoute;
export type OvpnTunDns = ovpn.TunDns;
export type OvpnEvent = ovpn.OvpnEvent;
export type OvpnEvalResult = ovpn.EvalResult;
export type OvpnConnectConfig = ovpn.ConnectConfig;
export type OvpnStats = ovpn.Stats;
export type OvpnProtectRequest = ovpn.ProtectRequest;

// Higher-level wrapper over libovpnclient. The native side exposes a flat,
// handle-based C API; this class gives ArkTS code a typed object with
// proper async semantics for the tun/protect callbacks.
export class OvpnEngine {
  private handle: bigint = 0n;
  private tunHandler?: (cfg: OvpnTunConfig) => Promise<number>;
  private protectHandler?: (req: OvpnProtectRequest) => Promise<boolean>;

  constructor() {
    this.handle = ovpn.create();
    // The native side calls our handlers from the JS thread and expects us to
    // eventually call completeEstablish/completeProtect. We install thin
    // wrappers here that handle the awaiting and routing automatically.
    ovpn.setTunHandler(this.handle, (cfg: OvpnTunConfig): void => {
      const h = this.handle;
      if (!this.tunHandler) {
        log.error('tun_builder_establish called with no TS-side handler');
        ovpn.completeEstablish(h, -1);
        return;
      }
      this.tunHandler(cfg).then(
        (fd: number): void => { ovpn.completeEstablish(h, fd | 0); },
        (err: Object): void => {
          log.error('tun handler rejected', err);
          ovpn.completeEstablish(h, -1);
        }
      );
    });
    ovpn.setProtectHandler(this.handle, (req: OvpnProtectRequest): void => {
      const h = this.handle;
      if (!this.protectHandler) {
        ovpn.completeProtect(h, true);
        return;
      }
      this.protectHandler(req).then(
        (ok: boolean): void => { ovpn.completeProtect(h, ok); },
        (err: Object): void => {
          log.error('protect handler rejected', err);
          ovpn.completeProtect(h, false);
        }
      );
    });
  }

  setTunHandler(fn: (cfg: OvpnTunConfig) => Promise<number>): void {
    this.tunHandler = fn;
  }

  setProtectHandler(fn: (req: OvpnProtectRequest) => Promise<boolean>): void {
    this.protectHandler = fn;
  }

  setEventListener(fn: (ev: OvpnEvent) => void): void {
    ovpn.setEventListener(this.handle, fn);
  }

  setLogListener(fn: (line: string) => void): void {
    ovpn.setLogListener(this.handle, fn);
  }

  evalConfig(configText: string): OvpnEvalResult {
    return ovpn.evalConfig(this.handle, configText);
  }

  configure(cfg: OvpnConnectConfig): void {
    ovpn.setConfig(this.handle, cfg);
  }

  provideCreds(username: string, password: string, cache: boolean): void {
    ovpn.provideCreds(this.handle, username, password, cache);
  }

  startConnect(): void { ovpn.startConnect(this.handle); }
  stop():        void { ovpn.stop(this.handle); }
  pause(reason: string): void { ovpn.pause(this.handle, reason); }
  resume(): void { ovpn.resume(this.handle); }

  getStats(): OvpnStats { return ovpn.getStats(this.handle); }

  dispose(): void {
    if (this.handle !== 0n) {
      ovpn.destroy(this.handle);
      this.handle = 0n;
    }
  }
}
