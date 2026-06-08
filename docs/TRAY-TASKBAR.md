# Tray icon + off-taskbar resident — how it's actually done on HarmonyOS PC

## Goal
"Close the window so the app disappears from the PC taskbar/dock but keeps a
persistent system-tray icon and stays alive" (the WPS behaviour).

## TL;DR — it IS possible for a normal third-party app
An earlier version of this doc concluded this was impossible without
system/preinstall privilege. **That was wrong.** HarmonyOS provides a supported
pattern for exactly this — see the official guide
"PC 应用通过系统托盘后台保活"
(developer.huawei.com architecture-guides/pc_status_bar). We now implement it.

## How we implement it
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
  calls `this.context.hideAbility()` and returns `true`. The window is hidden
  (dropping the taskbar/dock entry); the app stays resident via the tray-attached
  process. Requires permission `ohos.permission.PREPARE_APP_TERMINATE`.
- **Restore**: left-click the tray icon → `statusBarIconClick` event →
  `context.showAbility()` brings the window back (also the 打开主窗口 menu item).
- **Clean exit**: the system tray / Dock 退出 terminates `BackGroundAbility`; in
  its `onPrepareToTerminate()` it publishes `EV_BG_TERMINATE`; `EntryAbility`
  receives it, removes the tray icon and calls `terminateSelf()` (with
  `killAllProcesses()` as a backstop). This is what makes the whole app — UI,
  VPN extension, keepalive process — exit together (no lingering process / no
  stuck DevEco "running" indicator).

## Key APIs (and the earlier mistake)
- `context.hideAbility()` / `context.showAbility()` — **UIAbilityContext methods
  available to third-party apps**. The earlier doc wrongly cited `window.hide()`
  (which *is* `@systemapi`) and concluded it was impossible. `hideAbility()` is
  the right, non-system API.
- `NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` — the supported way to hold a resident
  background process tied to the tray, without a privileged
  `ServiceExtensionAbility` and without a long-time task (which extensions can't
  start anyway — that 401 was real but irrelevant to this approach).
- `onPrepareToTerminate()` (needs `ohos.permission.PREPARE_APP_TERMINATE`) — the
  correct close hook. Returning true + `hideAbility()` keeps the app resident;
  the cross-ability `EV_BG_TERMINATE` event distinguishes a real exit.

## Constraints
- API 17+ / HarmonyOS 5.0.5 Release SDK+ / DevEco 6.0.0+. Our target device is
  6.1.0, so supported.
- PC / 2-in-1 only (`SystemCapability.PCService.StatusBarManager`); on phone the
  tray is simply skipped (guarded by `canIUse`).

### Sources
- PC 应用通过系统托盘后台保活 (official architecture guide):
  https://developer.huawei.com/consumer/cn/doc/architecture-guides/pc_status_bar-0000002551100435
- statusBarManager.addToStatusBar / onPrepareToTerminate / startAbility — see the
  links in that guide's 参考文档 section.
