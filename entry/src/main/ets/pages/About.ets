import { bundleManager } from '@kit.AbilityKit';

// About / open-source license notice. Required because the VPN engine (OpenVPN 3)
// is AGPLv3: we must disclose the components + licenses and point users to the
// complete source.
@Entry
@Component
struct About {
  @State private version: string = '';

  aboutToAppear(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo): void => { this.version = info.versionName; })
      .catch((): void => { /* leave blank */ });
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .height(36).margin({ right: 8 })
          .backgroundColor($r('app.color.surface_dim'))
          .fontColor($r('app.color.on_surface'))
          .onClick((): void => { this.getUIContext().getRouter().back(); })
        Text('关于')
          .fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })
      .width('100%')

      Scroll() {
        Column({ space: 10 }) {
          Text('OVPN客户端')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.on_surface'))
          Text(this.version ? `版本 ${this.version}` : '')
            .fontSize(14).fontColor($r('app.color.on_surface_dim'))

          Text('开源许可声明')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.on_surface'))
            .margin({ top: 12 })
          Text('本应用为开源软件，基于以下开源组件构建：')
            .fontSize(14).fontColor($r('app.color.on_surface'))
          Text('• OpenVPN 3（release/3.10）—— GNU AGPL v3\n' +
               '• Asio（1.30.2）—— Boost Software License 1.0\n' +
               '• Mbed TLS（3.6.2）—— Apache License 2.0\n' +
               '• LZ4（1.10.0）—— BSD 2-Clause')
            .fontSize(14).fontColor($r('app.color.on_surface')).lineHeight(22)
          Text('本应用整体依据 GNU Affero General Public License v3（AGPLv3）授权。')
            .fontSize(14).fontColor($r('app.color.on_surface'))

          Text('完整源代码')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.on_surface'))
            .margin({ top: 12 })
          Text('https://github.com/antonidasyang/openvpn-oh')
            .fontSize(14).fontColor($r('app.color.brand_primary')).copyOption(CopyOptions.LocalDevice)
        }
        .width('100%').alignItems(HorizontalAlign.Start).padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
