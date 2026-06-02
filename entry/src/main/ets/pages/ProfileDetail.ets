import { router } from '@kit.ArkUI';

import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore, LoadedCred } from '../model/CredentialStore';
import { VpnController } from '../service/VpnController';
import { VpnState, VpnStateData } from '../model/VpnState';
import { Profile } from '../model/Profile';

import { StatusPill } from '../components/StatusPill';
import { StatsCard } from '../components/StatsCard';

interface ProfileRouteParams { profileId: string }

@Entry
@ComponentV2
struct ProfileDetail {
  @Local private profile: Profile | null = null;
  @Local private username: string = '';
  @Local private password: string = '';
  @Local private cache: boolean = false;
  @Local private credsExpanded: boolean = false;
  @Local private state: VpnStateData = VpnState;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as ProfileRouteParams | undefined;
    const id = params?.profileId;
    if (!id) {
      router.back();
      return;
    }
    this.profile = ProfileStore.get(id) ?? null;
    if (!this.profile) {
      router.back();
      return;
    }
    const cred: LoadedCred | null = await CredentialStore.load(this.profile.id);
    if (cred) {
      this.username = cred.username;
      this.password = cred.password;
      this.cache = cred.cached;
    }
    this.credsExpanded = !this.profile.autologin && !this.password;
  }

  build() {
    Column() {
      this.TopBar()
      if (this.profile) {
        Scroll() {
          Column({ space: 16 }) {
            this.Summary()
            this.ConnectArea()
            if (!this.profile!.autologin) this.Credentials()
            this.LogShortcut()
          }
          .padding(16)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.surface_dim'))
  }

  @Builder
  private TopBar() {
    Row() {
      Button('<')
        .width(40).height(40)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.on_surface'))
        .onClick((): void => { router.back(); })
      Text(this.profile?.displayName ?? '')
        .fontSize(18).fontWeight(FontWeight.Bold)
        .margin({ left: 8 })
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(16).width('100%')
  }

  @Builder
  private Summary() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.label_remote'))
          .fontSize(13).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
        Text(`${this.profile!.remoteProto}://${this.profile!.remoteHost}:${this.profile!.remotePort}`)
          .fontSize(14).fontColor($r('app.color.on_surface'))
      }
      Row() {
        Text('Auth')
          .fontSize(13).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
        Text(this.profile!.autologin ? 'Certificate' : 'Username + password')
          .fontSize(14).fontColor($r('app.color.on_surface'))
      }
    }
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .width('100%')
  }

  @Builder
  private ConnectArea() {
    Column({ space: 12 }) {
      StatusPill({ phase: this.state.phase })
      if (this.state.phase === 'CONNECTED' || this.state.phase === 'RECONNECTING') {
        StatsCard({
          bytesIn:        Number(this.state.stats.bytesIn),
          bytesOut:       Number(this.state.stats.bytesOut),
          connectedSince: this.state.connectedSince,
        })
        Button($r('app.string.action_disconnect'))
          .width('100%')
          .backgroundColor($r('app.color.status_error'))
          .onClick((): void => { VpnController.stop(); })
      } else {
        Button($r('app.string.action_connect'))
          .width('100%')
          .backgroundColor($r('app.color.brand_primary'))
          .onClick((): void => { this.connect(); })
      }
      if (this.state.lastError) {
        Text(this.state.lastError)
          .fontSize(13).fontColor($r('app.color.status_error'))
      }
    }
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private Credentials() {
    Column({ space: 12 }) {
      Row() {
        Text('Credentials')
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.credsExpanded })
          .onChange((on: boolean): void => { this.credsExpanded = on; })
      }
      if (this.credsExpanded) {
        TextInput({ placeholder: 'username', text: this.username })
          .onChange((v: string): void => { this.username = v; })
          .backgroundColor($r('app.color.surface_dim'))
          .borderRadius(10)
        TextInput({ placeholder: 'password', text: this.password })
          .type(InputType.Password)
          .onChange((v: string): void => { this.password = v; })
          .backgroundColor($r('app.color.surface_dim'))
          .borderRadius(10)
        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.cache })
            .onChange((on: boolean): void => { this.cache = on; })
          Text($r('app.string.label_save_credentials'))
            .fontSize(13)
            .fontColor($r('app.color.on_surface_dim'))
            .margin({ left: 8 })
        }
      }
    }
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private LogShortcut() {
    Row() {
      Text($r('app.string.title_logs'))
        .fontSize(15).fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
      Text('>')
        .fontSize(18).fontColor($r('app.color.on_surface_dim'))
    }
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .width('100%')
    .onClick((): void => { router.pushUrl({ url: 'pages/LogView' }); })
  }

  private async connect(): Promise<void> {
    if (!this.profile) return;
    if (!this.profile.autologin && this.username && this.password) {
      await VpnController.submitCreds(this.username, this.password, this.cache);
    }
    await VpnController.connect(this.profile);
    await ProfileStore.touchLastConnected(this.profile.id);
  }
}
