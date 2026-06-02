// TypeScript surface of libovpnclient.so.
//
// All engine instances live in the native module. ArkTS holds an opaque
// `bigint` handle returned by create() and passes it to every other call.

export interface TunAddress {
  address: string;
  prefix: number;
  gateway: string;
  ipv6: boolean;
  net30: boolean;
}

export interface TunRoute {
  address: string;
  prefix: number;
  metric: number;
  ipv6: boolean;
  exclude: boolean;
}

export interface TunDns {
  address: string;
  ipv6: boolean;
}

export interface TunConfig {
  sessionName: string;
  remoteAddress: string;
  remoteIpv6: boolean;
  mtu: number;
  layer: number;
  rerouteIpv4: boolean;
  rerouteIpv6: boolean;
  addresses: TunAddress[];
  routes: TunRoute[];
  dns: TunDns[];
  searchDomains: string[];
}

export interface ProtectRequest {
  fd: number;
  remote: string;
  ipv6: boolean;
}

export interface OvpnEvent {
  name: string;
  info: string;
  code: number;
  fatal: boolean;
  error: boolean;
}

export interface EvalResult {
  error: boolean;
  message: string;
  profileName: string;
  userlockedUsername: string;
  remoteHost: string;
  remotePort: string;
  remoteProto: string;
  autologin: boolean;
  externalPki: boolean;
  staticChallenge: string;
  staticChallengeEcho: boolean;
  privateKeyPasswordRequired: boolean;
  allowPasswordSave: boolean;
}

export interface ConnectConfig {
  content: string;
  guiVersion?: string;
  privateKeyPassword?: string;
  serverOverride?: string;
  portOverride?: string;
  protoOverride?: string;
  ipv6?: string;
  compressionMode?: string;
  tlsCertProfileOverride?: string;
  disableClientCert?: boolean;
  connTimeout?: number;
  tunPersist?: boolean;
  googleDnsFallback?: boolean;
  autologinSessions?: boolean;
  info?: boolean;
}

export interface Stats {
  transport: {
    bytesIn: bigint;
    bytesOut: bigint;
    lastPacketReceived: number;
  };
  tun: {
    bytesIn: bigint;
    bytesOut: bigint;
    packetsIn: bigint;
    packetsOut: bigint;
    errorsIn: bigint;
    errorsOut: bigint;
  };
}

export type Handle = bigint;

export function create(): Handle;
export function destroy(h: Handle): void;
export function evalConfig(h: Handle, content: string): EvalResult;
export function setConfig(h: Handle, cfg: ConnectConfig): void;
export function setTunHandler(h: Handle, fn: (cfg: TunConfig) => void): void;
export function setProtectHandler(h: Handle, fn: (req: ProtectRequest) => void): void;
export function setEventListener(h: Handle, fn: (ev: OvpnEvent) => void): void;
export function setLogListener(h: Handle, fn: (line: string) => void): void;
export function provideCreds(h: Handle, username: string, password: string, cache: boolean): void;
export function startConnect(h: Handle): void;
export function stop(h: Handle): void;
export function pause(h: Handle, reason: string): void;
export function resume(h: Handle): void;
export function completeEstablish(h: Handle, fd: number): void;
export function completeProtect(h: Handle, ok: boolean): void;
export function getStats(h: Handle): Stats;
