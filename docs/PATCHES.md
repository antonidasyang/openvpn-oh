# OHOS NDK porting patches for openvpn3

Track here each diff you have to apply to `entry/src/main/cpp/third_party/openvpn3/`
to make it compile and run on the HarmonyOS NDK. The fetch script clones a
pinned release tag, so patches are reproducible.

Each entry should include:

1. Symptom (compile error, runtime crash, behaviour mismatch).
2. The exact file + line in openvpn3.
3. The fix (ideally a `git diff` block).
4. Whether the fix is OHOS-specific (`#ifdef OPENVPN_PLATFORM_OHOS`) or upstreamable.

## Template

```
### <one-line title>

**Symptom**
<paste compile error or describe runtime issue>

**File**
`openvpn3/openvpn/<path>:<line>`

**Patch**
```diff
- old line
+ new line
```

**Notes**
- OHOS-specific? yes / no
- Reported upstream? link to issue/PR if so
```

## Known suspects (not yet confirmed)

These are likely-but-unverified rough edges. Verify, then either remove from
this list (if it turns out to compile fine) or move to the section above with
the actual fix.

- `epoll_pwait2` is only in newer glibc; OHOS NDK may not expose it. Fallback
  to `epoll_pwait` via `#ifndef HAVE_EPOLL_PWAIT2`.
- `pthread_setname_np` differs between glibc (2-arg) and musl/bionic-derived
  libcs. openvpn3 has handled this on Android — check if the same guard
  works on OHOS.
- `getifaddrs` — present on OHOS but the link-layer family numbering may
  differ from Linux. openvpn3's tun interface enumeration uses this.
- DNS resolver: openvpn3 uses ASIO's resolver, which calls `getaddrinfo`.
  OHOS supports this, but make sure the system DNS resolver does not
  itself try to route through the unestablished VPN (chicken-and-egg).
  The engine sidesteps this by calling `VpnConnection.protect(socket)`
  before connect; verify the protect path is wired up.
