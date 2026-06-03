import StatusBarViewExtensionAbility from '@hms.pcService.StatusBarViewExtensionAbility';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';

// Content shown when the user left-clicks the tray icon. Kept minimal — the
// main control surface is the right-click menu (see TrayService).
export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    session.loadContent('pages/TrayPopup');
  }
}
