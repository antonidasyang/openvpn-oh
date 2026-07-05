// Toast content for NoticeAbility. The text is pushed in via AppStorage
// ('noticeText') by NoticeAbility as EV_TRAY_NOTICE messages arrive. A full-size
// Stack centers the text both vertically and horizontally.
@Entry
@Component
struct NoticePage {
  @StorageLink('noticeText') text: string = '请稍候…';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.text)
        .fontSize(18)
        .fontColor($r('app.color.on_surface'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
  }
}
