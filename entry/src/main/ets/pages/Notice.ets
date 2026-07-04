// Toast content for NoticeAbility. The text is pushed in via AppStorage
// ('noticeText') by NoticeAbility as EV_TRAY_NOTICE messages arrive.
@Entry
@Component
struct NoticePage {
  @StorageLink('noticeText') text: string = '请稍候…';

  build() {
    Column() {
      Text(this.text)
        .fontSize(16)
        .fontColor($r('app.color.on_surface'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
    .backgroundColor($r('app.color.surface'))
  }
}
