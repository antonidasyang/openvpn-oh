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

@Component
export struct StatsCard {
  @Prop bytesIn: number = 0;
  @Prop bytesOut: number = 0;
  @Prop connectedSince: number = 0;
  // Drives 1Hz redraws so the duration ticks even when nothing else changes.
  @State private tick: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => { this.tick++; }, 1000);
  }
  aboutToDisappear(): void {
    if (this.timer !== -1) clearInterval(this.timer);
  }

  build() {
    Column({ space: 12 }) {
      this.Row($r('app.string.label_bytes_in'),   formatBytes(this.bytesIn))
      this.Row($r('app.string.label_bytes_out'),  formatBytes(this.bytesOut))
      this.Row($r('app.string.label_duration'),   formatDuration(this.connectedSince))
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
