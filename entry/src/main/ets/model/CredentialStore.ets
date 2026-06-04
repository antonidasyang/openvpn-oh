import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { logger } from '../util/Logger';

const log = logger('CredentialStore');
const STORE = 'ovpn_credentials';

// Stores per-profile username/password and the private-key password in the
// app's private preferences (EL2, device-encrypted, app-sandboxed). HUKS
// encryption was removed: it failed to round-trip on the target device, which
// silently broke "remember password". The sandbox is private to this app.
//
// Every preferences call is wrapped in try/catch: a credential read/write that
// fails should degrade gracefully (no saved password) rather than break the
// connect flow or crash the app.

interface StoredCred {
  username: string;
  password: string;
  cachePassword: boolean;
}

export interface LoadedCred {
  username: string;
  password: string;
  cached: boolean;
}

class CredentialStoreImpl {
  private store?: preferences.Preferences;

  async init(context: common.Context): Promise<void> {
    if (this.store) return;
    try {
      this.store = await preferences.getPreferences(context, STORE);
    } catch (e) {
      log.error('init failed; credentials disabled', e as Object);
    }
  }

  async save(profileId: string, username: string, password: string,
             cachePassword: boolean): Promise<void> {
    if (!this.store) return;
    const record: StoredCred = {
      username,
      password: cachePassword ? password : '',
      cachePassword,
    };
    try {
      await this.store.put(profileId, JSON.stringify(record));
      await this.store.flush();
    } catch (e) {
      log.error('save failed', e as Object);
    }
  }

  async load(profileId: string): Promise<LoadedCred | null> {
    if (!this.store) return null;
    try {
      const raw = await this.store.get(profileId, '') as string;
      if (!raw) return null;
      const record = JSON.parse(raw) as StoredCred;
      const out: LoadedCred = {
        username: record.username ?? '',
        password: record.cachePassword ? (record.password ?? '') : '',
        cached: record.cachePassword === true,
      };
      return out;
    } catch (e) {
      log.error('failed to load credentials', e as Object);
      return null;
    }
  }

  async delete(profileId: string): Promise<void> {
    if (!this.store) return;
    try {
      await this.store.delete(profileId);
      await this.store.delete(profileId + '.pk');
      await this.store.flush();
    } catch (e) {
      log.error('delete failed', e as Object);
    }
  }

  // ----- Private-key password (separate from auth creds) -----

  async saveKeyPassword(profileId: string, keyPassword: string): Promise<void> {
    if (!this.store) return;
    try {
      if (!keyPassword) {
        await this.store.delete(profileId + '.pk');
      } else {
        await this.store.put(profileId + '.pk', keyPassword);
      }
      await this.store.flush();
    } catch (e) {
      log.error('saveKeyPassword failed', e as Object);
    }
  }

  async loadKeyPassword(profileId: string): Promise<string> {
    if (!this.store) return '';
    try {
      const v = await this.store.get(profileId + '.pk', '') as string;
      return v;
    } catch (e) {
      log.error('loadKeyPassword failed', e as Object);
      return '';
    }
  }
}

export const CredentialStore = new CredentialStoreImpl();
