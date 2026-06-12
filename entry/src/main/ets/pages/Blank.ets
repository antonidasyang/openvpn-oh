// Minimal placeholder page for BackGroundAbility, which runs hidden
// (STARTUP_HIDE). It exists only to satisfy the UIAbility window lifecycle; the
// process's real job is to keep the app alive while attached to the tray icon.
@Entry
@Component
struct BlankPage {
  build() {
    Column() {}
    .width('100%')
    .height('100%')
  }
}
