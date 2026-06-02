import { Profile } from '../model/Profile';

@Component
export struct ProfileListItem {
  @Prop profile: Profile;
  @Prop selected: boolean = false;
  onTap?: () => void;
  onDelete?: () => void;

  build() {
    Row({ space: 12 }) {
      Column() {
        Text('VPN')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_primary'))
      }
      .width(48).height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.surface_dim'))
      .borderRadius(24)

      Column({ space: 4 }) {
        Text(this.profile.displayName)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
        Text(`${this.profile.remoteProto || 'udp'}://${this.profile.remoteHost}:${this.profile.remotePort}`)
          .fontSize(13)
          .fontColor($r('app.color.on_surface_dim'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('>')
        .fontSize(20)
        .fontColor($r('app.color.on_surface_dim'))
    }
    .padding(16)
    .backgroundColor(this.selected ? $r('app.color.surface_dim') : $r('app.color.surface'))
    .borderRadius(16)
    .border(this.selected
      ? { width: 2, color: $r('app.color.brand_primary') }
      : { width: 0, color: $r('app.color.surface') })
    .width('100%')
    .onClick((): void => { if (this.onTap) this.onTap(); })
    .gesture(
      LongPressGesture({ duration: 500 })
        .onAction((): void => { if (this.onDelete) this.onDelete(); })
    )
  }
}
