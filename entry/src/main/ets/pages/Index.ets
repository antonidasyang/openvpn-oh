import { router } from '@kit.ArkUI';
import mediaquery from '@ohos.mediaquery';

import { ProfileStore } from '../model/ProfileStore';
import { VpnState } from '../model/VpnState';
import { VpnController } from '../service/VpnController';
import { Profile } from '../model/Profile';

import { ProfileListItem } from '../components/ProfileListItem';
import { StatusPill } from '../components/StatusPill';
import { StatsCard } from '../components/StatsCard';

// Two-pane on 2-in-1 / tablet, single-pane on phone. Threshold 640dp matches
// the HarmonyOS NEXT "MD" breakpoint.
@Entry
@Component
struct Index {
  @State private profiles: Profile[] = [];
  @State private isWide: boolean = false;
  @State private selectedId: string = '';
  @Local private state = VpnState;

  private unsubscribe?: () => void;
  private mqListener?: mediaquery.MediaQueryListener;

  aboutToAppear(): void {
    this.profiles = ProfileStore.list();
    this.unsubscribe = ProfileStore.subscribe(list => { this.profiles = list; });
    this.mqListener = mediaquery.matchMediaSync('(min-width: 640vp)');
    this.mqListener.on('change', (r: mediaquery.MediaQueryResult) => {
      this.isWide = r.matches;
    });
    this.isWide = this.mqListener.matches;
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) this.unsubscribe();
    if (this.mqListener) this.mqListener.off('change');
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
      Button({ type: ButtonType.Circle }) {
        Image($r('sys.media.ohos_ic_public_view_list'))
          .width(20).height(20)
          .fillColor($r('app.color.on_surface'))
      }
      .width(40).height(40).margin({ right: 8 })
      .backgroundColor($r('app.color.surface_dim'))
      .onClick(() => router.pushUrl({ url: 'pages/LogView' }))
      Button({ type: ButtonType.Circle }) {
        Image($r('sys.media.ohos_ic_public_add'))
          .width(20).height(20)
          .fillColor($r('app.color.brand_on_primary'))
      }
      .width(40).height(40)
      .backgroundColor($r('app.color.brand_primary'))
      .onClick(() => router.pushUrl({ url: 'pages/ImportConfig' }))
    }
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
    .width('100%')
  }

  @Builder
  private ConnectionBanner() {
    if (this.state.phase !== 'DISCONNECTED') {
      Row() {
        Column({ space: 4 }) {
          Text(this.state.activeProfileName || 'OpenVPN')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_dim'))
          StatusPill({ phase: this.state.phase })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button($r('app.string.action_disconnect'))
          .backgroundColor($r('app.color.status_error'))
          .fontColor($r('app.color.brand_on_primary'))
          .onClick(() => VpnController.stop())
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
        ForEach(this.profiles, (p: Profile) => {
          ListItem() {
            ProfileListItem({
              profile: p,
              onTap: () => this.openProfile(p),
              onDelete: () => this.confirmDelete(p),
            })
          }
        }, (p: Profile) => p.id)
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
        Text(this.state.activeProfileName || this.profiles.find(p => p.id === this.selectedId)?.displayName || '')
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        StatusPill({ phase: this.state.phase })
        StatsCard({
          bytesIn:        this.state.stats.bytesIn,
          bytesOut:       this.state.stats.bytesOut,
          connectedSince: this.state.connectedSince,
        })
        if (this.state.phase === 'CONNECTED' || this.state.phase === 'RECONNECTING') {
          Button($r('app.string.action_disconnect'))
            .width('100%')
            .backgroundColor($r('app.color.status_error'))
            .onClick(() => VpnController.stop())
        } else {
          Button($r('app.string.action_connect'))
            .width('100%')
            .backgroundColor($r('app.color.brand_primary'))
            .onClick(() => this.connectSelected())
        }
        if (this.state.lastError) {
          Text(this.state.lastError)
            .fontSize(13).fontColor($r('app.color.status_error'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  private openProfile(p: Profile): void {
    if (this.isWide) {
      this.selectedId = p.id;
    } else {
      router.pushUrl({ url: 'pages/ProfileDetail', params: { profileId: p.id } });
    }
  }

  private connectSelected(): void {
    const p = this.profiles.find(x => x.id === this.selectedId);
    if (p) VpnController.connect(p);
  }

  private confirmDelete(p: Profile): void {
    AlertDialog.show({
      title: p.displayName,
      message: 'Delete this profile?',
      primaryButton: {
        value: $r('app.string.action_delete'),
        fontColor: $r('app.color.status_error'),
        action: () => { ProfileStore.delete(p.id); }
      },
      secondaryButton: {
        value: $r('app.string.action_cancel'),
        action: () => {}
      },
    });
  }
}
