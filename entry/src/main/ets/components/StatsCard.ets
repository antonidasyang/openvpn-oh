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
  const two = (n: number) => n.toString().padStart(2, '0');
  return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${two(m)}:${two(s)}`;
}

// @ComponentV2 so it stays reactive under the @ComponentV2 parent (Index) +
// @ObservedV2/@Trace VpnState. A V1 (@Component/@Prop) child under a V2 parent
// does not refresh its props reliably — which made the byte counters only
// update on navigation.
@ComponentV2
export struct StatsCard {
  @Param bytesIn: number = 0;
  @Param bytesOut: number = 0;
  @Param connectedSince: number = 0;
  // Drives 1Hz redraws so the duration ticks even when nothing else changes.
  @Local private tick: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => { this.tick++; }, 1000);
  }
  aboutToDisappear(): void {
    if (this.timer !== -1) clearInterval(this.timer);
  }

  // Reads this.tick so the duration row re-renders every second under V2
  // (where only expressions that read a @Local re-evaluate on its change).
  private durationText(): string {
    // Reading this.tick (which increments every second) registers the
    // reactive dependency that re-evaluates this row once per second.
    return this.tick >= 0 ? formatDuration(this.connectedSince) : '';
  }

  build() {
    Column({ space: 12 }) {
      this.Row($r('app.string.label_bytes_in'),   formatBytes(this.bytesIn))
      this.Row($r('app.string.label_bytes_out'),  formatBytes(this.bytesOut))
      this.Row($r('app.string.label_duration'),   this.durationText())
    }
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
    .width('100%')
  }

  @Builder
  Row(label: Resource, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
      Text(value).fontSize(15).fontColor($r('app.color.on_surface')).fontWeight(FontWeight.Medium)
    }
    .width('100%')
  }
}
