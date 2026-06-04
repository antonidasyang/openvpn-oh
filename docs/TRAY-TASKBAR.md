# Tray icon vs. taskbar entry — what's achievable for a third-party app

## Goal
"Close the window so the app disappears from the PC taskbar/dock but keeps a
persistent system-tray icon" (the WPS behaviour).

## What we implemented
- System-tray icon + right-click menu via `@hms.pcService.statusBarManager`
  (StatusBar / Desktop Extension Kit). Menu: every profile with
  连接 / 断开 / 重连, plus 打开主窗口 / 退出. Works.
- Close button → dialog 最小化 / 退出. Minimize keeps the process + tray alive.

## Why "no taskbar, only tray" is NOT possible for us (evidence)
The tray icon only lives as long as a process of the app is alive. Our only
process that can stay alive is the windowed UIAbility, and a UIAbility window
always has a dock/mission entry. Removing that entry while staying alive needs
one of two things, both gated to system / privileged apps:

1. `window.Window.hide()` — hides the main window (removes the dock entry)
   while keeping the ability alive. **This is a `@systemapi`** (system
   applications only); a normal third-party app cannot call it.
2. A windowless background service (`ServiceExtensionAbility`) that owns the
   tray and outlives the window. **Residence / auto-start for
   ServiceExtensionAbility is a device-manufacturer privilege**, not available
   to ordinary third-party apps; declaring it can even fail installation
   ("install parse profile prop check error").
3. The `module.json5` ability attribute `excludeFromMissions` (whether the
   UIAbility shows in Recents/taskbar). Official doc: *"Configurations of
   third-party applications do not take effect; the current configurations are
   only valid for system applications."* So setting it has no effect for us.

We also tried keeping a windowless process alive ourselves: starting a
long-time task (`backgroundTaskManager.startBackgroundRunning`) from the VPN
extension fails with **401 "Get ability context failed"** — extensions cannot
start a continuous task; only a UIAbility can, and that brings back the window /
taskbar entry. So a "resident tray-only process" cannot be built either.

WPS Office ships preinstalled / as a Huawei partner app, so it has these
privileges. A side-loaded third-party app (our case) does not.

### Two-process / windowless-tray designs don't escape this
- "One resident tray process + one window process": the resident tray process
  must be windowless **and** stay alive — i.e. a `ServiceExtensionAbility`
  (privileged) or a long-time task (extensions get 401). Neither is available.
- "No window at all, tray-only app": same wall — a tray needs a live process; a
  live UIAbility always registers a taskbar/mission entry that we can't hide;
  `terminateSelf()` kills the process and the tray with it.

## Does a "formal"/release signature unlock it? No.
There are three signing tiers, and only the third one matters here:

| Tier | How you get it | Can call `@systemapi` / use `excludeFromMissions`? |
|------|----------------|---------------------------------------------------|
| Auto-sign | DevEco local one-click | ❌ |
| Release / publish signature | Apply for `.cer`/`.p7b` in AGC to ship on AppGallery | ❌ — still a normal third-party app |
| System / privileged signature | Huawei preinstall list + OEM private key | ✅ (this is what WPS has) |

A release (publish) signature only solves *distribution* — it does **not** raise
the app's privilege level (APL). `@systemapi` and the "system-applications-only"
config attributes require `system_basic`/`system_core` APL, which a published
app does not get. The ACL ("restricted permission") channel in AGC can grant
specific *restricted permissions* (e.g. photo-album access) but **cannot** turn
a `normal` app into a system application or open `@systemapi`. Dropping the
taskbar entry is an app-*identity* gate (system app or not), not a grantable
permission — so the AGC publish flow can never provide it.

Only two routes give true "tray-only, no taskbar":
1. Get into Huawei's preinstall / privileged-app program (partner/business
   deal) — what WPS did; not available to ordinary developers.
2. Own the system signing key yourself (OpenHarmony custom ROM / device-maker
   identity).

### Sources
- @ohos.window `hide()` is documented as a system interface (systemapi):
  https://blog.csdn.net/2401_84194030/article/details/139298785
- ServiceExtensionAbility residence/auto-start is a manufacturer privilege:
  https://blog.csdn.net/lee1054908698/article/details/142104026
- HarmonyOS background-task rules (continuous task needs a foreground
  notification): https://harmonyosdev.csdn.net/69a2bc220a2f6a37c5942eb8.html
- `module.json5` `excludeFromMissions` is "only valid for system applications":
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/module-configuration-file
- Release/publish signing requires applying for `.cer`/`.p7b` in AGC (a
  distribution step, not a privilege upgrade):
  https://dev.to/simple_lau_1997/how-to-publish-a-harmonyos-application-21gp
- HarmonyOS permission/APL & ACL model (ACL grants restricted permissions, not
  system-app status):
  https://dev.to/liu_yang_fc0e605820ac220c/a-deep-guide-to-harmonyos-next-permission-management-15k4

## Practical outcome
- Achievable today: **taskbar entry + tray icon coexist** (minimize keeps
  both; click either to use the app). The tray's right-click menu is the
  background control surface.
- To get true "tray-only, no taskbar": the app must be granted system /
  preinstall privilege (e.g. an OEM/Huawei partnership or a system signature),
  then switch the close action to `window.hide()` and/or move tray ownership
  into a resident `ServiceExtensionAbility`.
