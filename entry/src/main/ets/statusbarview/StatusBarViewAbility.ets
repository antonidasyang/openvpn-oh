import StatusBarViewExtensionAbility from '@hms.pcService.StatusBarViewExtensionAbility';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';

// Content shown when the user left-clicks the tray icon. The right-click menu
// (owned by the UI process, see TrayService) is the main control surface.
export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    session.loadContent('pages/TrayPopup');
  }
}
