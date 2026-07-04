# 问题反馈：PC 状态栏 statusBarManager 菜单项 `notifyOnly: true` 未生效（点击仍拉起 ability/窗口）

## 一句话概述
在 2in1 / PC 上使用 `@hms.pcService.statusBarManager` 的系统托盘右键菜单，将菜单项
`StatusBarMenuAction.notifyOnly` 设为 `true` 后，点击菜单项**仍然会拉起并显示
`abilityName` 指定的 UIAbility 窗口**，而不是按文档只触发 `rightMenuClick` 事件。

## 运行环境（请提交前补全）
- 设备型号：________（2in1 / PC，SystemCapability.PCService.StatusBarManager）
- HarmonyOS / 系统版本：________（例如 6.1.x）
- API version：________（`const.ohos.apiversion`）
- DevEco Studio 版本：________
- SDK 版本：________
- 应用 bundleName：com.d2ssoft.ovpn

## 相关接口
- Kit：DesktopExtensionKit，模块 `@hms.pcService.statusBarManager`
- `statusBarManager.addToStatusBar(context, StatusBarItem)`
- `StatusBarMenuAction.notifyOnly`（@since 5.0.2(14)，文档描述：`right menu click event enable`）
- `statusBarManager.on('rightMenuClick', callback)`

## 期望行为
菜单项的 `menuAction.notifyOnly = true` 时，点击该菜单项应**仅触发
`rightMenuClick` 事件**（回调里能拿到 `menuCode`），**不应**拉起 / 前台化
`abilityName` 所指的 ability，也不应显示任何窗口。这样应用即可在“最小化到托盘”状态下，
纯靠事件回调处理托盘菜单操作（如连接/断开 VPN），全程不打扰用户。

## 实际行为
`notifyOnly` 被忽略：点击菜单项时，系统仍按 `abilityName` 把对应 UIAbility 拉到
前台并显示其窗口；`rightMenuClick` 事件**同时**也会触发。即“事件触发”和“拉起窗口”
两件事都发生了，`notifyOnly: true` 没有阻止后者。

## 最小复现代码
```typescript
import statusBarManager from '@hms.pcService.statusBarManager';
import { common } from '@kit.AbilityKit';

// context 为 UIAbilityContext（在主 UIAbility 中获取）
function installTray(context: common.UIAbilityContext,
                     white: image.PixelMap, black: image.PixelMap): void {
  // 关键：菜单项 action 设 notifyOnly = true，期望“只发事件、不拉起 ability”
  const action: statusBarManager.StatusBarMenuAction = {
    abilityName: 'EntryAbility',   // 期望 notifyOnly=true 时它不被拉起
    moduleName: 'entry',
    notifyOnly: true,
    menuCode: 'connect',
  };
  const sub: statusBarManager.StatusBarSubMenuItem = { subTitle: '连接', menuAction: action };
  const menuItem: statusBarManager.StatusBarMenuItem = { title: 'VPN配置A', subMenu: [sub] };

  const item: statusBarManager.StatusBarItem = {
    icons: { white, black },
    quickOperation: { title: 'Demo', height: 30, abilityName: '', moduleName: 'entry' },
    statusBarGroupMenu: [[menuItem]],
    hoverTips: 'Demo',
  };
  statusBarManager.addToStatusBar(context, item);

  // 右键菜单点击事件（此处能正常收到 menuCode='connect'）
  statusBarManager.on('rightMenuClick', (ev): void => {
    console.info('rightMenuClick data=' + JSON.stringify(ev.data)); // -> 含 menuCode: 'connect'
  });
}
```

## 复现步骤
1. 用上面的代码添加托盘图标及右键菜单（菜单项 `notifyOnly: true`）。
2. 将应用主窗口最小化 / 隐藏（例如 `UIAbilityContext.hideAbility()`），此时主 UIAbility
   进程仍存活、`rightMenuClick` 监听仍有效。
3. 右键系统托盘图标 → 点击菜单项“连接”。
4. **期望**：仅回调 `rightMenuClick`（收到 `menuCode='connect'`），不出现任何窗口。
5. **实际**：`abilityName` 指定的 `EntryAbility` 被拉到前台并显示其窗口；`rightMenuClick`
   同时也触发。

## 补充证据（已排除“用法错误”）
- 把 `menuAction.abilityName` 改为空字符串 `''`（期望“无目标可启动”），点击后系统弹出
  **“暂无可用打开方式”**提示框——这说明系统**仍在尝试按 abilityName 启动一个 ability**，
  即完全无视了 `notifyOnly: true`（若 `notifyOnly` 生效，空 abilityName 应只发事件、不报错）。
- `rightMenuClick` 事件本身工作正常（能稳定收到 `menuCode`）。所以问题**仅**在于
  `notifyOnly: true` 没有阻止“拉起/显示 ability 窗口”这一步。
- API 也不允许“无 action 的可点菜单项”作为替代：`StatusBarMenuItem` 的 `subMenu` 与
  `menuAction` “不可都缺省”，且 `StatusBarSubMenuItem.menuAction` 为必填——因此每个可点
  叶子项都必然带 `abilityName`，在本设备上就都会被拉起。

## 影响
应用（PC VPN 客户端）希望：最小化到托盘后，用户从托盘右键菜单点“连接某配置”能**静默直连**、
不弹出主窗口（类似 WPS / 微信 PC 版的托盘操作体验）。由于 `notifyOnly` 未生效，每次托盘菜单
操作都会强行弹出应用窗口，体验受损。目前只能用“让被拉起的 ability 全透明并立即 `hideAbility()`”
的方式绕过，但这是 workaround，不是正解。

## 诉求
1. 确认该系统版本上 `StatusBarMenuAction.notifyOnly: true` 的**预期行为**；
2. 若属缺陷，请修复：`notifyOnly: true` 时点击菜单项应**只触发 `rightMenuClick`、不拉起
   `abilityName`**；
3. 或提供官方推荐做法：在托盘右键菜单点击时“**仅回调、不打开任何窗口**”应如何实现
   （例如是否应指向某种无窗口的后台扩展 `AppServiceExtensionAbility`）。
