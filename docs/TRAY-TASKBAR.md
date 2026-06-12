# Tray icon + off-taskbar resident — how it's actually done on HarmonyOS PC

## Goal
"Close the window so the app disappears from the PC taskbar/dock but keeps a
persistent system-tray icon and stays alive" (the WPS behaviour).

## History of this problem
1. First attempt: `window.hide()` — `@systemapi`, dead end.
2. Second attempt (previous revision of this doc): the official
   "PC 应用通过系统托盘后台保活" pattern — `onPrepareToTerminate()` → `hideAbility()`
   plus a tray-attached keepalive process. The keepalive part works, **but in
   practice `hideAbility()` left the app icon sitting on the taskbar** — exactly
   the thing we were trying to remove.
3. Current approach, per Huawei developer-support's official answer (2026-06):
   *“如果不想在任务栏显示的话,您可以使用 terminateSelf 接口退出应用,该接口不会在
   任务栏显示。”* — i.e. don't hide the UIAbility, **exit it** with
   `UIAbilityContext.terminateSelf()`. A terminated ability has no taskbar entry
   by definition; the app as a whole stays alive through the tray-attached
   keepalive process, and the VPN tunnel stays up because it lives in its own
   `VpnExtensionAbility` process.

## How we implement it now
- **Tray icon + right-click menu** via `@hms.pcService.statusBarManager`
  (`addToStatusBar`). Menu: each profile with 连接 / 断开 / 重连, plus 打开主窗口.
  No custom 退出 — the system attaches its own 退出 to every tray icon.
- **Keepalive process**: `TrayService.holdStatusBar()` starts a hidden
  `BackGroundAbility` (UIAbility) with
  `StartOptions.processMode = contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM`
  and `startupVisibility = contextConstant.StartupVisibility.STARTUP_HIDE`.
  This is a **new process bound to the tray icon** that keeps the app alive in
  the background (PC otherwise forbids arbitrary background running).
- **Close → off the taskbar, still alive**: `EntryAbility.onPrepareToTerminate()`
  calls `this.context.terminateSelf()` (official advice; needs
  `ohos.permission.PREPARE_APP_TERMINATE`). Only the UI ability dies:
  - the VPN tunnel survives in the `OvpnVpnExtensionAbility` process;
  - the tray + `BackGroundAbility` keepalive process survive;
  - `onDestroy()`'s `killAllProcesses()` backstop is **gated by a `fullExit`
    flag** so a hide never kills the VPN.
- **Restore**: tray right-click → 打开主窗口. That menu item uses
  `notifyOnly: false`, so the **system itself** starts `EntryAbility` — it works
  even though the UI process is dead and none of our event listeners exist.
  (Left-click restore and per-profile tray menu actions are event-based
  (`notifyOnly: true`) and therefore only work while the UI process is alive —
  moving tray event handling into `BackGroundAbility` is the follow-up if we
  want them to work while hidden.)
- **Clean exit**: the system tray / Dock 退出 terminates `BackGroundAbility`.
  Since `EntryAbility` may already be terminated at that point, BG does the
  full teardown itself (publish `EV_COMMAND_STOP`, `stopVpnExtensionAbility`,
  `removeFromStatusBar`, then `killAllProcesses`), and still publishes
  `EV_BG_TERMINATE` for the window-open case so `EntryAbility` can run its
  graceful `doExit()`.
- **Tray reinstall guard**: every `EntryAbility` launch reinstalls the tray icon
  (remove stale + re-add). Removing the icon can take the attached keepalive
  process down with it, so `TrayService.init()` first publishes
  `EV_TRAY_REINSTALL`; for the next 5 s `BackGroundAbility` treats its own
  termination as a reinstall (just dies, no VPN teardown) instead of a user
  exit.

## Constraints
- API 17+ / HarmonyOS 5.0.5 Release SDK+ / DevEco 6.0.0+. Our target device is
  6.1.0, so supported.
- PC / 2-in-1 only (`SystemCapability.PCService.StatusBarManager`); on phone the
  tray is simply skipped (guarded by `canIUse`).

### Sources
- Huawei developer-support reply (2026-06): use `terminateSelf` to exit without
  a taskbar entry.
- PC 应用通过系统托盘后台保活 (official architecture guide):
  https://developer.huawei.com/consumer/cn/doc/architecture-guides/pc_status_bar-0000002551100435
- statusBarManager.addToStatusBar / onPrepareToTerminate / startAbility — see the
  links in that guide's 参考文档 section.
