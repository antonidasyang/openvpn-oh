import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { Profile, newProfileId } from './Profile';
import { logger } from '../util/Logger';

const log = logger('ProfileStore');
const STORE_NAME = 'ovpn_profiles';
const KEY_LIST = 'profiles_v1';

// Singleton store. Profiles are kept entirely in user preferences for now —
// adequate for hundreds of profiles, well under the 8KB per-value soft limit
// per preferences entry on small ones, and below the 16MB combined limit even
// for inlined certs. If we hit those limits we'll migrate to per-profile files
// under context.filesDir.

class ProfileStoreImpl {
  private store?: preferences.Preferences;
  private cache: Profile[] = [];
  private loaded = false;
  private listeners: Array<(profiles: Profile[]) => void> = [];

  async init(context: common.Context): Promise<void> {
    if (this.store) return;
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await this.store.get(KEY_LIST, '[]') as string;
      this.cache = JSON.parse(raw) as Profile[];
    } catch (e) {
      log.error('init failed / bad stored profiles, starting empty', e as Object);
      this.cache = [];
    }
    this.loaded = true;
    this.emit();
  }

  list(): Profile[] {
    return this.cache.slice();
  }

  get(id: string): Profile | undefined {
    return this.cache.find(p => p.id === id);
  }

  async upsert(profile: Profile): Promise<void> {
    if (!profile.id) profile.id = newProfileId();
    const idx = this.cache.findIndex(p => p.id === profile.id);
    if (idx >= 0) this.cache[idx] = profile;
    else this.cache.push(profile);
    await this.flush();
    this.emit();
  }

  async delete(id: string): Promise<void> {
    this.cache = this.cache.filter(p => p.id !== id);
    await this.flush();
    this.emit();
  }

  async touchLastConnected(id: string): Promise<void> {
    const p = this.cache.find(x => x.id === id);
    if (!p) return;
    p.lastConnectedAt = Date.now();
    await this.flush();
    this.emit();
  }

  subscribe(fn: (profiles: Profile[]) => void): () => void {
    this.listeners.push(fn);
    if (this.loaded) fn(this.list());
    return () => {
      this.listeners = this.listeners.filter(x => x !== fn);
    };
  }

  private async flush(): Promise<void> {
    if (!this.store) throw new Error('ProfileStore not initialized');
    try {
      await this.store.put(KEY_LIST, JSON.stringify(this.cache));
      await this.store.flush();
    } catch (e) {
      // Rethrow so callers (upsert/delete) still surface a real save failure.
      log.error('flush failed', e as Object);
      throw e as Error;
    }
  }

  private emit(): void {
    const snapshot = this.list();
    for (const fn of this.listeners) {
      try { fn(snapshot); } catch (e) { log.warn('listener threw', e as Object); }
    }
  }
}

export const ProfileStore = new ProfileStoreImpl();
