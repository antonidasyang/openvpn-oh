import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { logger } from '../util/Logger';

const log = logger('CredentialStore');
const STORE = 'ovpn_credentials';

// Stores per-profile username/password and the private-key password in the
// app's private preferences (EL2, device-encrypted, app-sandboxed). HUKS
// encryption was removed: it failed to round-trip on the target device, which
// silently broke "remember password". The sandbox is private to this app.

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
    if (!this.store) {
      this.store = await preferences.getPreferences(context, STORE);
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
    await this.store.put(profileId, JSON.stringify(record));
    await this.store.flush();
  }

  async load(profileId: string): Promise<LoadedCred | null> {
    if (!this.store) return null;
    const raw = await this.store.get(profileId, '') as string;
    if (!raw) return null;
    try {
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
    await this.store.delete(profileId);
    await this.store.delete(profileId + '.pk');
    await this.store.flush();
  }

  // ----- Private-key password (separate from auth creds) -----

  async saveKeyPassword(profileId: string, keyPassword: string): Promise<void> {
    if (!this.store) return;
    if (!keyPassword) {
      await this.store.delete(profileId + '.pk');
    } else {
      await this.store.put(profileId + '.pk', keyPassword);
    }
    await this.store.flush();
  }

  async loadKeyPassword(profileId: string): Promise<string> {
    if (!this.store) return '';
    const v = await this.store.get(profileId + '.pk', '') as string;
    return v;
  }
}

export const CredentialStore = new CredentialStoreImpl();
