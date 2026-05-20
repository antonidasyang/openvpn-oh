# openvpn-oh

An OpenVPN client for HarmonyOS NEXT (5.0+). Supports phones and 2-in-1 PCs.

> Status: **scaffolded, not yet runnable end-to-end.** All ArkTS code is in
> place and the C++ engine binds the real openvpn3 ClientAPI — not a stub —
> but you have to fetch the native dependencies and resolve OHOS-NDK build
> patches on your machine before the first connection works. See
> [Where we stop](#where-we-stop) below.

License: **AGPL-3.0-or-later**, because openvpn3 is AGPLv3 and we link it
directly. See [LICENSE](./LICENSE).

## Architecture

```
                 ┌──────────────────────────────────┐
                 │  EntryAbility (UI process)       │
                 │   - Index / ImportConfig / ...   │
                 │   - VpnController (CommonEvents) │
                 └──────────────┬───────────────────┘
                                │ start / stop / pause /
                                │ resume / submitCreds
                                ▼  (commonEventManager broadcasts)
                 ┌──────────────────────────────────┐
                 │  OvpnVpnExtensionAbility         │
                 │  (separate VPN process, type=vpn)│
                 │   - vpnExtension.VpnConnection   │
                 │   - OvpnEngine (ArkTS wrapper)   │
                 └──────────────┬───────────────────┘
                                │ NAPI
                                ▼
                 ┌──────────────────────────────────┐
                 │  libovpnclient.so (C++)          │
                 │   OvpnClient : OpenVPNClient     │
                 │     - TunBuilder callbacks       │
                 │     - SocketProtect              │
                 │     - threadsafe-fn bridge       │
                 │   openvpn3 ClientAPI (vendored)  │
                 │   mbedTLS · ASIO · lz4           │
                 └──────────────────────────────────┘
```

The native engine subclasses `openvpn::ClientAPI::OpenVPNClient`. When openvpn3
calls `tun_builder_establish()` on its worker thread, we synchronously hop to
ArkTS via `napi_threadsafe_function`, call
`VpnConnection.create(VpnConfig)`, hand the tun fd back through
`completeEstablish(handle, fd)`, and unblock the worker. The same pattern
serves `socket_protect()`.

## Project layout

```
openvpn-oh/
├── AppScope/                       app-level resources (name, icon)
├── build-profile.json5             top-level hvigor config
├── hvigorfile.ts
├── oh-package.json5
├── entry/                          single HAP module
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   └── src/main/
│       ├── module.json5            declares EntryAbility + OvpnVpnExtensionAbility
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   ├── vpnability/OvpnVpnExtensionAbility.ets
│       │   ├── pages/              Index, ImportConfig, ProfileDetail, LogView
│       │   ├── components/         StatusPill, StatsCard, ProfileListItem
│       │   ├── model/              Profile, ProfileStore, CredentialStore, VpnState
│       │   ├── service/            OvpnEngine, VpnController, CommonEvents
│       │   └── util/               Logger
│       ├── cpp/
│       │   ├── CMakeLists.txt
│       │   ├── napi_init.cpp       NAPI surface (handle registry)
│       │   ├── ovpn_client.{h,cpp} OvpnClient + TunBuilder + SocketProtect
│       │   ├── async_bridge.h      SyncSlot<T>
│       │   ├── log.h               hilog wrappers
│       │   ├── types/libovpnclient/  TS declarations for the NAPI module
│       │   └── third_party/        ← populated by scripts/fetch-third-party.sh
│       └── resources/
└── scripts/
    └── fetch-third-party.sh        clones openvpn3 / asio / mbedtls / lz4
```

## Build

### Prerequisites

1. **DevEco Studio 5.0** (Marketplace edition or later).
2. **HarmonyOS NDK** installed via DevEco Studio (Preferences → SDK → Native).
   Confirm `ohos.toolchain.cmake` is present in your NDK install.
3. `git` and `bash` on your PATH (for the fetch script).

### One-time setup

```bash
git clone <this-repo> openvpn-oh
cd openvpn-oh
./scripts/fetch-third-party.sh         # ~250MB across openvpn3 + mbedtls + asio + lz4
```

The fetch script pins versions known to compile cleanly with the OHOS NDK
as of 2026-Q1. Re-run is idempotent.

### Open in DevEco Studio

1. File → Open → select the `openvpn-oh` directory.
2. Sync project (hvigor will pick up `entry/oh-package.json5`).
3. Provide a signing certificate. For internal testing you can use the
   "Automatic signing" toggle (Project Structure → Signing Configs).
4. Build → Build Hap. The native module compiles via CMake, producing
   `libovpnclient.so` for `arm64-v8a` and `x86_64` (configured in
   `entry/build-profile.json5`).
5. Run on a HarmonyOS NEXT device or emulator.

### App icon

A 1024 × 1024 icon (blue shield + keyhole) is installed at
`AppScope/resources/base/media/app_icon.png` and
`entry/src/main/resources/base/media/app_icon.png`. Source SVG lives at
`assets/icon.svg` — re-render with `qlmanage -t -s 1024 -o . icon.svg`
(or `rsvg-convert -w 1024 -h 1024 assets/icon.svg -o app_icon.png`) and
copy the result into both media folders if you tweak the design.

## Where we stop

This commit ships:

- ✅ Full app project layout that opens in DevEco Studio.
- ✅ ArkTS UI: profile list + import + detail + log viewer, adaptive between
  phone (single pane) and 2-in-1 PC (two-pane) layouts.
- ✅ Profile persistence in `@ohos.data.preferences`.
- ✅ Credential persistence using HUKS (AES-256-GCM-sealed passwords).
- ✅ CMakeLists wired to compile openvpn3 ClientAPI + mbedTLS + ASIO + lz4.
- ✅ Real `OvpnClient : openvpn::ClientAPI::OpenVPNClient` subclass — every
  `tun_builder_*` and `socket_protect()` callback is implemented and routed
  to ArkTS via `napi_threadsafe_function`.
- ✅ `OvpnVpnExtensionAbility` translating openvpn3's pushed config into
  `vpnExtension.VpnConfig` and feeding the resulting fd back into the engine.
- ✅ Bidirectional CommonEvent traffic between the UI and the VPN ability.

What still has to happen before the first successful tunnel:

1. **OHOS-NDK build patches for openvpn3.** openvpn3 was written against
   glibc and Apple/Windows POSIX; the HarmonyOS NDK ships musl-flavoured
   libc with some functions missing or renamed. Until proven otherwise,
   expect to patch:
   - `epoll_pwait2` calls (fall back to `epoll_pwait`)
   - any direct use of `pthread_setname_np` with the glibc 2-arg signature
   - `getifaddrs` — present in OHOS NDK, but the struct layout differs
     subtly; verify before assuming
   Track these in `docs/PATCHES.md`.
2. **Verify the `vpnExtension.VpnConfig` shape.** The exact field names
   (`addresses` vs `address`, `routes[].destination`, etc.) match the
   API as documented in the HarmonyOS NEXT 5.0 reference; if the device
   API differs, adjust `establishTun()` in
   `OvpnVpnExtensionAbility.ets`.
3. **Permission grant flow.** First launch will surface the system VPN
   dialog when `startVpnExtensionAbility` runs. If the request fails on
   your device, double-check that `ohos.permission.MANAGE_VPN` is granted
   (Settings → Apps → OpenVPN → Permissions).
4. **Real server.** Test against a known-good OpenVPN server. The free
   `udp.openvpn.com` test endpoint is a good first target.

I expect items 1–2 to take one or two more sessions. After that, ramping
through reconnect handling, IPv6 default route, and split tunnelling is
incremental.

## Adding a feature later

- **Reconnect on network change** — subscribe to `@ohos.net.connection`
  observer in the VPN ability and call `engine.pause('netchange')` / `engine.resume()`.
- **Per-app split tunnelling** — populate
  `vpnExtension.VpnConfig.trustedApplications` / `blockedApplications`
  in `establishTun()` from a new profile field.
- **External PKI / smartcard** — implement
  `external_pki_cert_request` / `external_pki_sign_request` in
  `ovpn_client.cpp` and route the sign request to HUKS via the same
  threadsafe-fn pattern used for tun establishment.

## License

This project is distributed under the GNU AGPL v3.0 or later. See
[LICENSE](./LICENSE).

Third-party components and their licenses:

| Component  | License             |
| ---------- | ------------------- |
| openvpn3   | AGPL-3.0            |
| mbedTLS    | Apache-2.0          |
| ASIO       | Boost Software 1.0  |
| lz4        | BSD-2-Clause        |
