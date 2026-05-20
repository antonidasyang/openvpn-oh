import { huks } from '@kit.UniversalKeystoreKit';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { logger } from '../util/Logger';

const log = logger('CredentialStore');
const STORE = 'ovpn_credentials';
const HUKS_ALIAS = 'ovpn.cred.master.v1';

// Stores per-profile username/password. The password is encrypted with an
// AES-256-GCM key held by HUKS (HarmonyOS Universal Keystore) so it never
// leaves secure storage in cleartext on disk. The encrypted blob and the
// (random) IV are kept in user preferences, keyed by profile id.

interface SealedCred {
  username: string;
  ciphertext: string;  // base64
  iv: string;          // base64
  cachePassword: boolean;
}

class CredentialStoreImpl {
  private store?: preferences.Preferences;
  private keyReady = false;

  async init(context: common.Context): Promise<void> {
    if (!this.store) {
      this.store = await preferences.getPreferences(context, STORE);
    }
    await this.ensureMasterKey();
  }

  async save(profileId: string, username: string, password: string,
             cachePassword: boolean): Promise<void> {
    if (!cachePassword) {
      // Still remember the username so the prompt can pre-fill it.
      await this.store!.put(profileId, JSON.stringify({
        username, ciphertext: '', iv: '', cachePassword: false
      }));
      await this.store!.flush();
      return;
    }
    const sealed = await this.seal(password);
    const record: SealedCred = {
      username,
      ciphertext: sealed.ciphertext,
      iv: sealed.iv,
      cachePassword: true,
    };
    await this.store!.put(profileId, JSON.stringify(record));
    await this.store!.flush();
  }

  async load(profileId: string): Promise<{ username: string; password: string; cached: boolean } | null> {
    const raw = await this.store!.get(profileId, '') as string;
    if (!raw) return null;
    try {
      const record = JSON.parse(raw) as SealedCred;
      if (!record.cachePassword || !record.ciphertext) {
        return { username: record.username || '', password: '', cached: false };
      }
      const password = await this.unseal(record.ciphertext, record.iv);
      return { username: record.username || '', password, cached: true };
    } catch (e) {
      log.error('failed to load credentials', e as Object);
      return null;
    }
  }

  async delete(profileId: string): Promise<void> {
    await this.store!.delete(profileId);
    await this.store!.flush();
  }

  // ----- HUKS plumbing -----

  private async ensureMasterKey(): Promise<void> {
    if (this.keyReady) return;
    const exists = await huks.isKeyItemExist(HUKS_ALIAS, this.keyParams()).catch(() => false);
    if (!exists) {
      await huks.generateKeyItem(HUKS_ALIAS, this.keyParams());
    }
    this.keyReady = true;
  }

  private keyParams(): huks.HuksOptions {
    return {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,  value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING,    value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      ],
    };
  }

  private async seal(plaintext: string): Promise<{ ciphertext: string; iv: string }> {
    const iv = new Uint8Array(12);
    for (let i = 0; i < iv.length; i++) iv[i] = Math.floor(Math.random() * 256);

    const opts: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE,   value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,  value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING,    value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
      ],
      inData: new util.TextEncoder().encodeInto(plaintext),
    };

    const session = await huks.initSession(HUKS_ALIAS, opts);
    const result = await huks.finishSession(session.handle, opts);
    const ciphertext = result.outData!;
    return {
      ciphertext: new util.Base64Helper().encodeToStringSync(new Uint8Array(ciphertext)),
      iv:         new util.Base64Helper().encodeToStringSync(iv),
    };
  }

  private async unseal(ciphertextB64: string, ivB64: string): Promise<string> {
    const b64 = new util.Base64Helper();
    const iv         = b64.decodeSync(ivB64);
    const ciphertext = b64.decodeSync(ciphertextB64);

    const opts: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE,   value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,  value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING,    value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
      ],
      inData: ciphertext,
    };

    const session = await huks.initSession(HUKS_ALIAS, opts);
    const result = await huks.finishSession(session.handle, opts);
    return new util.TextDecoder().decodeWithStream(new Uint8Array(result.outData!));
  }
}

export const CredentialStore = new CredentialStoreImpl();
