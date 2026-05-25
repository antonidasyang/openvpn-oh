import { router } from '@kit.ArkUI';
import mediaquery from '@ohos.mediaquery';

import { ProfileStore } from '../model/ProfileStore';
import { VpnState, VpnStateData } from '../model/VpnState';
import { VpnController } from '../service/VpnController';
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
              onTap: (): void => this.openProfile(p),
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
        Text(this.state.activeProfileName || this.selectedDisplayName())
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
            .onClick((): void => { VpnController.stop(); })
        } else {
          Button($r('app.string.action_connect'))
            .width('100%')
            .backgroundColor($r('app.color.brand_primary'))
            .onClick((): void => this.connectSelected())
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
      const params: IndexRouteParams = { profileId: p.id };
      router.pushUrl({ url: 'pages/ProfileDetail', params });
    }
  }

  private connectSelected(): void {
    for (const p of this.profiles) {
      if (p.id === this.selectedId) {
        VpnController.connect(p);
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
        action: (): void => { ProfileStore.delete(p.id); }
      },
      secondaryButton: {
        value: $r('app.string.action_cancel'),
        action: (): void => {}
      },
    });
  }
}
