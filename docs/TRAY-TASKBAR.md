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

WPS Office ships preinstalled / as a Huawei partner app, so it has these
privileges. A side-loaded third-party app (our case) does not.

### Sources
- @ohos.window `hide()` is documented as a system interface (systemapi):
  https://blog.csdn.net/2401_84194030/article/details/139298785
- ServiceExtensionAbility residence/auto-start is a manufacturer privilege:
  https://blog.csdn.net/lee1054908698/article/details/142104026
- HarmonyOS background-task rules (continuous task needs a foreground
  notification): https://harmonyosdev.csdn.net/69a2bc220a2f6a37c5942eb8.html

## Practical outcome
- Achievable today: **taskbar entry + tray icon coexist** (minimize keeps
  both; click either to use the app). The tray's right-click menu is the
  background control surface.
- To get true "tray-only, no taskbar": the app must be granted system /
  preinstall privilege (e.g. an OEM/Huawei partnership or a system signature),
  then switch the close action to `window.hide()` and/or move tray ownership
  into a resident `ServiceExtensionAbility`.
