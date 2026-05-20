import { router } from '@kit.ArkUI';

import { ProfileStore } from '../model/ProfileStore';
import { CredentialStore } from '../model/CredentialStore';
import { VpnController } from '../service/VpnController';
import { VpnState } from '../model/VpnState';
import { Profile } from '../model/Profile';

import { StatusPill } from '../components/StatusPill';
import { StatsCard } from '../components/StatsCard';

@Entry
@Component
struct ProfileDetail {
  @State private profile: Profile | null = null;
  @State private username: string = '';
  @State private password: string = '';
  @State private cache: boolean = false;
  @State private credsExpanded: boolean = false;
  @Local private state = VpnState;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, string> | undefined;
    const id = params?.['profileId'];
    if (!id) {
      router.back();
      return;
    }
    this.profile = ProfileStore.get(id) ?? null;
    if (!this.profile) {
      router.back();
      return;
    }
    const cred = await CredentialStore.load(this.profile.id);
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
      Button({ type: ButtonType.Circle }) {
        Image($r('sys.media.ohos_ic_public_back'))
          .width(20).height(20)
          .fillColor($r('app.color.on_surface'))
      }
      .width(40).height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => router.back())
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
          bytesIn:        this.state.stats.bytesIn,
          bytesOut:       this.state.stats.bytesOut,
          connectedSince: this.state.connectedSince,
        })
        Button($r('app.string.action_disconnect'))
          .width('100%')
          .backgroundColor($r('app.color.status_error'))
          .onClick(() => VpnController.stop())
      } else {
        Button($r('app.string.action_connect'))
          .width('100%')
          .backgroundColor($r('app.color.brand_primary'))
          .onClick(() => this.connect())
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
          .onChange((on) => { this.credsExpanded = on; })
      }
      if (this.credsExpanded) {
        TextInput({ placeholder: 'username', text: this.username })
          .onChange(v => { this.username = v; })
          .backgroundColor($r('app.color.surface_dim'))
          .borderRadius(10)
        TextInput({ placeholder: 'password', text: this.password })
          .type(InputType.Password)
          .onChange(v => { this.password = v; })
          .backgroundColor($r('app.color.surface_dim'))
          .borderRadius(10)
        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.cache })
            .onChange((on) => { this.cache = on; })
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
      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(20).height(20)
        .fillColor($r('app.color.on_surface_dim'))
    }
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .width('100%')
    .onClick(() => router.pushUrl({ url: 'pages/LogView' }))
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
