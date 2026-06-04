import { VpnState, VpnStateData } from '../model/VpnState';

function formatBytes(n: number): string {
  let v = n;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return v < 10 ? `${v.toFixed(2)} ${units[i]}` : `${v.toFixed(1)} ${units[i]}`;
}

function formatDuration(sinceMs: number): string {
  if (sinceMs <= 0) return '—';
  const secs = Math.floor((Date.now() - sinceMs) / 1000);
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  const two = (n: number): string => n.toString().padStart(2, '0');
  return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${two(m)}:${two(s)}`;
}

// Reads the global @ObservedV2/@Trace VpnState DIRECTLY (not via @Param), so the
// byte counters re-render the instant VpnState.setStats runs — independent of
// whether the parent page re-renders. The duration is driven by a 1Hz @Local
// tick. Every reactive value is read inside build()'s Text() so V2's read-based
// reactivity tracks it (passing a precomputed string into an @Builder does not).
@ComponentV2
export struct StatsCard {
  @Local private vpn: VpnStateData = VpnState;
  @Local private tick: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval((): void => { this.tick++; }, 1000);
  }
  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.label_bytes_in'))
          .fontSize(14).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
        Text(formatBytes(Number(this.vpn.stats.bytesIn)))
          .fontSize(15).fontColor($r('app.color.on_surface')).fontWeight(FontWeight.Medium)
      }.width('100%')
      Row() {
        Text($r('app.string.label_bytes_out'))
          .fontSize(14).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
        Text(formatBytes(Number(this.vpn.stats.bytesOut)))
          .fontSize(15).fontColor($r('app.color.on_surface')).fontWeight(FontWeight.Medium)
      }.width('100%')
      Row() {
        Text($r('app.string.label_duration'))
          .fontSize(14).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
        // Reading this.tick (1Hz) keeps this row re-evaluating every second.
        Text(this.tick >= 0 ? formatDuration(this.vpn.connectedSince) : '')
          .fontSize(15).fontColor($r('app.color.on_surface')).fontWeight(FontWeight.Medium)
      }.width('100%')
    }
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
    .width('100%')
  }
}
