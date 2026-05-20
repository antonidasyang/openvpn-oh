import { Phase } from '../model/VpnState';

const LABELS: Record<Phase, Resource> = {
  DISCONNECTED:  $r('app.string.status_disconnected'),
  RESOLVE:       $r('app.string.status_resolving'),
  TCP_CONNECT:   $r('app.string.status_tcp_connect'),
  UDP_CONNECT:   $r('app.string.status_tcp_connect'),
  WAIT:          $r('app.string.status_wait'),
  AUTH:          $r('app.string.status_auth'),
  GET_CONFIG:    $r('app.string.status_get_config'),
  ASSIGN_IP:     $r('app.string.status_assign_ip'),
  ADD_ROUTES:    $r('app.string.status_add_routes'),
  CONNECTED:     $r('app.string.status_connected'),
  RECONNECTING:  $r('app.string.status_reconnecting'),
  PAUSE:         $r('app.string.status_paused'),
  RESUME:        $r('app.string.status_resolving'),
  ERROR:         $r('app.string.status_error'),
};

const COLORS: Record<Phase, Resource> = {
  DISCONNECTED:  $r('app.color.on_surface_dim'),
  RESOLVE:       $r('app.color.brand_primary'),
  TCP_CONNECT:   $r('app.color.brand_primary'),
  UDP_CONNECT:   $r('app.color.brand_primary'),
  WAIT:          $r('app.color.brand_primary'),
  AUTH:          $r('app.color.status_warn'),
  GET_CONFIG:    $r('app.color.brand_primary'),
  ASSIGN_IP:     $r('app.color.brand_primary'),
  ADD_ROUTES:    $r('app.color.brand_primary'),
  CONNECTED:     $r('app.color.status_connected'),
  RECONNECTING:  $r('app.color.status_warn'),
  PAUSE:         $r('app.color.status_warn'),
  RESUME:        $r('app.color.brand_primary'),
  ERROR:         $r('app.color.status_error'),
};

@Component
export struct StatusPill {
  @Prop phase: Phase = 'DISCONNECTED';

  build() {
    Row({ space: 8 }) {
      Circle({ width: 10, height: 10 }).fill(COLORS[this.phase])
      Text(LABELS[this.phase])
        .fontSize(14)
        .fontColor($r('app.color.on_surface'))
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface_dim'))
    .borderRadius(999)
  }
}
