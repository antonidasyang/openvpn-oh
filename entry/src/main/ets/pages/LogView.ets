import { router } from '@kit.ArkUI';
import { VpnState, VpnStateData } from '../model/VpnState';

@Entry
@ComponentV2
struct LogView {
  @Local private state: VpnStateData = VpnState;
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
      this.TopBar()
      if (this.state.logLines.length === 0) {
        Column() {
          Text($r('app.string.empty_logs'))
            .fontSize(14).fontColor($r('app.color.on_surface_dim'))
            .textAlign(TextAlign.Center)
        }
        .padding(40).width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0, scroller: this.scroller }) {
          ForEach(this.state.logLines, (line: string, idx: number): void => {
            ListItem() {
              Text(line)
                .fontFamily('HarmonyOS Sans Mono')
                .fontSize(12)
                .fontColor($r('app.color.on_surface'))
                .width('100%')
                .padding({ left: 12, right: 12, top: 2, bottom: 2 })
            }
          }, (line: string, idx: number): string => `${idx}-${line.length}`)
        }
        .layoutWeight(1)
        .backgroundColor($r('app.color.surface'))
        .padding({ top: 8, bottom: 8 })
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
      Text($r('app.string.title_logs'))
        .fontSize(18).fontWeight(FontWeight.Bold)
        .margin({ left: 8 })
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
      Button('Clear')
        .height(36)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.on_surface'))
        .onClick((): void => { this.state.logLines = []; })
    }
    .padding(16).width('100%')
  }
}
