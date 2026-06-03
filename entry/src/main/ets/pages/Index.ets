import { router, window } from '@kit.ArkUI';
import mediaquery from '@ohos.mediaquery';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';

import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnState, VpnStateData } from '../model/VpnState';
import { VpnController } from '../service/VpnController';
import { EVENT_CLOSE_REQUEST } from '../service/CommonEvents';
import { Profile } from '../model/Profile';

import { ProfileListItem } from '../components/ProfileListItem';
import { StatusPill } from '../components/StatusPill';
import { StatsCard } from '../components/StatsCard';

interface IndexRouteParams { profileId: string }

// Two-pane on 2-in-1 / tablet, single-pane on phone. Threshold 640dp matches
// the HarmonyOS NEXT "MD" breakpoint.
@Entry
@ComponentV2
struct Index {
  @Local private profiles: Profile[] = [];
  @Local private isWide: boolean = false;
  @Local private selectedId: string = '';
  @Local private state: VpnStateData = VpnState;
  @Local private keyPassword: string = '';
  @Local private pkRequired: boolean = false;

  private unsubscribe?: () => void;
  private mqListener?: mediaquery.MediaQueryListener;

  aboutToAppear(): void {
    this.profiles = ProfileStore.list();
    this.unsubscribe = ProfileStore.subscribe((list: Profile[]): void => {
      this.profiles = list;
    });
    this.mqListener = mediaquery.matchMediaSync('(min-width: 640vp)');
    this.mqListener.on('change', (r: mediaquery.MediaQueryResult): void => {
      this.isWide = r.matches;
    });
    this.isWide = this.mqListener.matches;

    // The ability cancels the window close and asks us to confirm what to do.
    emitter.on({ eventId: EVENT_CLOSE_REQUEST }, (): void => { this.onCloseRequest(); });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) this.unsubscribe();
    if (this.mqListener) this.mqListener.off('change');
    emitter.off(EVENT_CLOSE_REQUEST);
  }

  // Triggered when the user presses the window close button. Ask whether to
  // keep running in the background (minimize) or fully quit.
  private onCloseRequest(): void {
    AlertDialog.show({
      title: 'D2SVPN',
      // Minimize keeps the app (and the tray icon) alive; the tray icon's
      // right-click menu controls connections in the background. Exit quits.
      message: '最小化到托盘后台运行，还是退出？',
      buttons: [
        {
          // Move the ability to the background (keeps the process + tray icon
          // alive). On PC this hides the window; if it leaves a taskbar entry,
          // fall back is plain minimize.
          value: '最小化到托盘',
          action: (): void => {
            const ctx = getContext(this) as common.UIAbilityContext;
            ctx.moveAbilityToBackground()
              .catch((e: Object): void => {
                console.error('moveToBackground failed', JSON.stringify(e));
                window.getLastWindow(ctx)
                  .then((w: window.Window): Promise<void> => w.minimize())
                  .catch((err: Object): void => { console.error('minimize failed', JSON.stringify(err)); });
              });
          },
        },
        {
          value: '退出',
          fontColor: $r('app.color.status_error'),
          action: (): void => {
            VpnController.stop();
            (getContext(this) as common.UIAbilityContext).terminateSelf();
          },
        },
      ],
      buttonDirection: DialogButtonDirection.VERTICAL,
    });
  }

  build() {
    if (this.isWide) {
      this.WideLayout()
    } else {
      this.NarrowLayout()
    }
  }

  @Builder
  private NarrowLayout() {
    Column() {
      this.TopBar()
      this.ConnectionBanner()
      this.ProfileList()
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.surface_dim'))
  }

  @Builder
  private WideLayout() {
    Row() {
      Column() {
        this.TopBar()
        this.ProfileList()
      }
      .width('40%').height('100%')

      Divider().vertical(true).strokeWidth(1).color($r('app.color.surface_dim'))

      Column() {
        this.DetailPane()
      }
      .layoutWeight(1).height('100%')
      .padding(24)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private TopBar() {
    Row() {
      Text($r('app.string.title_profiles'))
        .fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
      Button('Logs')
        .height(36).margin({ right: 8 })
        .backgroundColor($r('app.color.surface_dim'))
        .fontColor($r('app.color.on_surface'))
        .onClick((): void => { router.pushUrl({ url: 'pages/LogView' }); })
      Button('+ New')
        .height(36)
        .backgroundColor($r('app.color.brand_primary'))
        .fontColor($r('app.color.brand_on_primary'))
        .onClick((): void => { router.pushUrl({ url: 'pages/ImportConfig' }); })
    }
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
    .width('100%')
  }

  @Builder
  private ConnectionBanner() {
    if (this.state.phase !== 'DISCONNECTED') {
      Row() {
        Column({ space: 4 }) {
          Text(this.state.activeProfileName || 'D2SVPN')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_dim'))
          StatusPill({ phase: this.state.phase })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button($r('app.string.action_disconnect'))
          .backgroundColor($r('app.color.status_error'))
          .fontColor($r('app.color.brand_on_primary'))
          .onClick((): void => { VpnController.stop(); })
      }
      .padding(16).margin({ left: 16, right: 16, top: 4, bottom: 8 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .width('auto')
    }
  }

  @Builder
  private ProfileList() {
    if (this.profiles.length === 0) {
      Column() {
        Text($r('app.string.empty_profiles'))
          .fontSize(15).fontColor($r('app.color.on_surface_dim'))
          .textAlign(TextAlign.Center)
      }
      .padding(40).width('100%').layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.profiles, (p: Profile): void => {
          ListItem() {
            ProfileListItem({
              profile: p,
              selected: this.isWide && p.id === this.selectedId,
              onTap: (): void => { this.openProfile(p); },
              onDelete: (): void => this.confirmDelete(p),
            })
          }
        }, (p: Profile): string => p.id)
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      .layoutWeight(1)
    }
  }

  @Builder
  private DetailPane() {
    if (!this.selectedId) {
      Column() {
        Text('Select a profile to view details')
          .fontColor($r('app.color.on_surface_dim'))
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: 16 }) {
        // Always show the SELECTED profile's name, not the globally active one,
        // so switching profiles in the list actually updates the panel.
        Text(this.selectedDisplayName())
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        if (this.isConnectedThis()) {
          StatusPill({ phase: this.state.phase })
          StatsCard({
            bytesIn:        Number(this.state.stats.bytesIn),
            bytesOut:       Number(this.state.stats.bytesOut),
            connectedSince: this.state.connectedSince,
          })
          Button($r('app.string.action_disconnect'))
            .width('100%')
            .backgroundColor($r('app.color.status_error'))
            .onClick((): void => { VpnController.stop(); })
        } else if (this.isBusyThis()) {
          StatusPill({ phase: this.state.phase })
          Button($r('app.string.action_cancel'))
            .width('100%')
            .backgroundColor($r('app.color.status_error'))
            .onClick((): void => { VpnController.stop(); })
        } else {
          // Idle or error for this profile (or a different one is connected):
          // show the connect form so the user can (re)enter the password and
          // retry. Connecting auto-disconnects any other active tunnel.
          if (this.isSelectedActive() && this.state.lastError) {
            Text(this.state.lastError)
              .fontSize(13).fontColor($r('app.color.status_error'))
          } else if (!this.isSelectedActive() && this.state.phase !== 'DISCONNECTED') {
            Text(`${this.state.activeProfileName} 已连接 — 连接此配置会自动断开它`)
              .fontSize(13).fontColor($r('app.color.on_surface_dim'))
          }
          if (this.showKeyField()) {
            Text($r('app.string.label_key_password'))
              .fontSize(14).fontColor($r('app.color.on_surface_dim'))
            TextInput({ placeholder: 'private key password', text: this.keyPassword })
              .type(InputType.Password)
              .onChange((v: string): void => { this.keyPassword = v; })
              .onSubmit((): void => { this.connectSelected(); })
              .backgroundColor($r('app.color.surface_dim'))
              .borderRadius(10)
          }
          Button($r('app.string.action_connect'))
            .width('100%')
            .backgroundColor($r('app.color.brand_primary'))
            .onClick((): void => { this.connectSelected(); })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  private isSelectedActive(): boolean {
    return !!this.selectedId && this.state.activeProfileId === this.selectedId;
  }

  // This profile is the connected one.
  private isConnectedThis(): boolean {
    return this.isSelectedActive() &&
      (this.state.phase === 'CONNECTED' || this.state.phase === 'RECONNECTING');
  }

  // This profile is mid-connection (so we offer Cancel). ERROR/DISCONNECTED are
  // NOT busy — those fall through to the connect form so the user can retry.
  private isBusyThis(): boolean {
    const p = this.state.phase;
    return this.isSelectedActive() &&
      p !== 'DISCONNECTED' && p !== 'ERROR' &&
      p !== 'CONNECTED' && p !== 'RECONNECTING';
  }

  private async openProfile(p: Profile): Promise<void> {
    if (this.isWide) {
      this.selectedId = p.id;
      // Reset and recompute the private-key-password state for this profile.
      VpnState.needKeyPassword = false;
      this.keyPassword = '';
      this.pkRequired = p.privateKeyPasswordRequired || this.detectKeyPassword(p.configText);
      if (this.pkRequired) {
        this.keyPassword = await CredentialStore.loadKeyPassword(p.id);
      }
    } else {
      const params: IndexRouteParams = { profileId: p.id };
      router.pushUrl({ url: 'pages/ProfileDetail', params });
    }
  }

  // Encrypted inline private keys carry these PEM markers — pure string scan,
  // never run the native engine on the UI thread.
  private detectKeyPassword(configText: string): boolean {
    return configText.includes('ENCRYPTED PRIVATE KEY')
        || (configText.includes('Proc-Type') && configText.includes('ENCRYPTED'));
  }

  private showKeyField(): boolean {
    return this.pkRequired || this.state.needKeyPassword;
  }

  private async connectSelected(): Promise<void> {
    for (const p of this.profiles) {
      if (p.id === this.selectedId) {
        // Don't start a doomed connection when the key needs a passphrase.
        if (this.showKeyField() && !this.keyPassword) {
          this.pkRequired = true;
          VpnState.setError('请输入私钥密码 / Enter the private key password');
          return;
        }
        if (this.showKeyField()) {
          await CredentialStore.saveKeyPassword(p.id, this.keyPassword);
        }
        await VpnController.connect(p, this.keyPassword);
        return;
      }
    }
  }

  private selectedDisplayName(): string {
    for (const p of this.profiles) {
      if (p.id === this.selectedId) return p.displayName;
    }
    return '';
  }

  private confirmDelete(p: Profile): void {
    AlertDialog.show({
      title: p.displayName,
      message: 'Delete this profile?',
      primaryButton: {
        value: $r('app.string.action_delete'),
        fontColor: $r('app.color.status_error'),
        action: (): void => {
          if (this.state.activeProfileId === p.id && this.state.phase !== 'DISCONNECTED') {
            VpnController.stop();
          }
          if (this.selectedId === p.id) this.selectedId = '';
          CredentialStore.delete(p.id);
          ProfileStore.delete(p.id);
        }
      },
      secondaryButton: {
        value: $r('app.string.action_cancel'),
        action: (): void => {}
      },
    });
  }
}
