import { Phase } from '../model/VpnState';

interface PhaseLabel { phase: Phase; label: Resource; color: Resource }

const TABLE: PhaseLabel[] = [
  { phase: 'DISCONNECTED', label: $r('app.string.status_disconnected'), color: $r('app.color.on_surface_dim') },
  { phase: 'RESOLVE',      label: $r('app.string.status_resolving'),    color: $r('app.color.brand_primary') },
  { phase: 'TCP_CONNECT',  label: $r('app.string.status_tcp_connect'),  color: $r('app.color.brand_primary') },
  { phase: 'UDP_CONNECT',  label: $r('app.string.status_tcp_connect'),  color: $r('app.color.brand_primary') },
  { phase: 'WAIT',         label: $r('app.string.status_wait'),         color: $r('app.color.brand_primary') },
  { phase: 'AUTH',         label: $r('app.string.status_auth'),         color: $r('app.color.status_warn') },
  { phase: 'GET_CONFIG',   label: $r('app.string.status_get_config'),   color: $r('app.color.brand_primary') },
  { phase: 'ASSIGN_IP',    label: $r('app.string.status_assign_ip'),    color: $r('app.color.brand_primary') },
  { phase: 'ADD_ROUTES',   label: $r('app.string.status_add_routes'),   color: $r('app.color.brand_primary') },
  { phase: 'CONNECTED',    label: $r('app.string.status_connected'),    color: $r('app.color.status_connected') },
  { phase: 'RECONNECTING', label: $r('app.string.status_reconnecting'), color: $r('app.color.status_warn') },
  { phase: 'PAUSE',        label: $r('app.string.status_paused'),       color: $r('app.color.status_warn') },
  { phase: 'RESUME',       label: $r('app.string.status_resolving'),    color: $r('app.color.brand_primary') },
  { phase: 'ERROR',        label: $r('app.string.status_error'),        color: $r('app.color.status_error') },
];

function lookup(phase: Phase): PhaseLabel {
  for (const entry of TABLE) {
    if (entry.phase === phase) return entry;
  }
  return TABLE[0];
}

@Component
export struct StatusPill {
  @Prop phase: Phase = 'DISCONNECTED';

  // ArkUI's build() body is restricted to the component tree — no local
  // variable declarations are allowed. Pull the lookup into instance
  // accessors so we can keep using a typed Map-style table.
  private label(): Resource { return lookup(this.phase).label; }
  private color(): Resource { return lookup(this.phase).color; }

  build() {
    Row({ space: 8 }) {
      Circle({ width: 10, height: 10 }).fill(this.color())
      Text(this.label())
        .fontSize(14)
        .fontColor($r('app.color.on_surface'))
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface_dim'))
    .borderRadius(999)
  }
}
