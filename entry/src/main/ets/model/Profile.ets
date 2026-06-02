// Persisted OpenVPN profile. The .ovpn text is the source of truth — every
// other field is metadata derived from it (via eval_config) and surfaced for
// the UI so we don't reparse on every render.

export interface Profile {
  id: string;             // UUID
  displayName: string;    // user-facing name
  configText: string;     // full .ovpn content (with inline certs/keys)
  remoteHost: string;     // first remote
  remotePort: string;
  remoteProto: string;    // udp / tcp
  autologin: boolean;     // no creds needed
  privateKeyPasswordRequired: boolean; // inline private key is encrypted
  staticChallenge: string;
  staticChallengeEcho: boolean;
  externalPki: boolean;   // requires HW-backed key (not yet supported)
  createdAt: number;      // epoch ms
  lastConnectedAt: number;
}

export function newProfileId(): string {
  const r = () => Math.floor(Math.random() * 0xFFFFFFFF).toString(16).padStart(8, '0');
  return `${r()}-${r()}`;
}
