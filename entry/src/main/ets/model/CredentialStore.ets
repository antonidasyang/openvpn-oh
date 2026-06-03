import { huks } from '@kit.UniversalKeystoreKit';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { logger } from '../util/Logger';

const log = logger('CredentialStore');
const STORE = 'ovpn_credentials';
const HUKS_ALIAS = 'ovpn.cred.master.v1';

// Stores per-profile username/password. Passwords are encrypted with an
// AES-256-GCM key held by HUKS so they never live on disk in cleartext.

interface SealedCred {
  username: string;
  ciphertext: string;  // base64
  iv: string;          // base64
  cachePassword: boolean;
}

export interface LoadedCred {
  username: string;
  password: string;
  cached: boolean;
}

interface SealedBlob {
  ciphertext: string;
  iv: string;
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
      const stub: SealedCred = {
        username,
        ciphertext: '',
        iv: '',
        cachePassword: false,
      };
      await this.store!.put(profileId, JSON.stringify(stub));
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

  async load(profileId: string): Promise<LoadedCred | null> {
    const raw = await this.store!.get(profileId, '') as string;
    if (!raw) return null;
    try {
      const record = JSON.parse(raw) as SealedCred;
      if (!record.cachePassword || !record.ciphertext) {
        const out: LoadedCred = {
          username: record.username ?? '',
          password: '',
          cached: false,
        };
        return out;
      }
      const password = await this.unseal(record.ciphertext, record.iv);
      const out: LoadedCred = {
        username: record.username ?? '',
        password,
        cached: true,
      };
      return out;
    } catch (e) {
      log.error('failed to load credentials', e as Object);
      return null;
    }
  }

  async delete(profileId: string): Promise<void> {
    await this.store!.delete(profileId);
    await this.store!.delete(profileId + '.pk');
    await this.store!.flush();
  }

  // ----- Private-key password (separate from auth creds) -----

  async saveKeyPassword(profileId: string, keyPassword: string): Promise<void> {
    if (!keyPassword) {
      await this.store!.delete(profileId + '.pk');
      await this.store!.flush();
      return;
    }
    const sealed = await this.seal(keyPassword);
    await this.store!.put(profileId + '.pk', JSON.stringify(sealed));
    await this.store!.flush();
  }

  async loadKeyPassword(profileId: string): Promise<string> {
    const raw = await this.store!.get(profileId + '.pk', '') as string;
    if (!raw) return '';
    try {
      const blob = JSON.parse(raw) as SealedBlob;
      return await this.unseal(blob.ciphertext, blob.iv);
    } catch (e) {
      log.error('failed to load key password', e as Object);
      return '';
    }
  }

  // ----- HUKS plumbing -----

  private async ensureMasterKey(): Promise<void> {
    if (this.keyReady) return;
    let exists = false;
    try {
      exists = await huks.isKeyItemExist(HUKS_ALIAS, this.keyParams());
    } catch (e) {
      exists = false;
    }
    if (!exists) {
      await huks.generateKeyItem(HUKS_ALIAS, this.keyParams());
    }
    this.keyReady = true;
  }

  private keyParams(): huks.HuksOptions {
    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,  value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING,    value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    ];
    const opts: huks.HuksOptions = { properties: props };
    return opts;
  }

  private async seal(plaintext: string): Promise<SealedBlob> {
    const iv = new Uint8Array(12);
    for (let i = 0; i < iv.length; i++) iv[i] = Math.floor(Math.random() * 256);

    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,   value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,  value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING,    value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
    ];
    const opts: huks.HuksOptions = {
      properties: props,
      inData: new util.TextEncoder().encodeInto(plaintext),
    };

    const session = await huks.initSession(HUKS_ALIAS, opts);
    const result = await huks.finishSession(session.handle, opts);
    const ciphertext = result.outData!;
    const out: SealedBlob = {
      ciphertext: new util.Base64Helper().encodeToStringSync(new Uint8Array(ciphertext)),
      iv:         new util.Base64Helper().encodeToStringSync(iv),
    };
    return out;
  }

  private async unseal(ciphertextB64: string, ivB64: string): Promise<string> {
    const b64 = new util.Base64Helper();
    const iv   = b64.decodeSync(ivB64);
    // HUKS AES-GCM encrypt output is ciphertext followed by the 16-byte AEAD
    // tag. Decryption must pass that tag via HUKS_TAG_AE_TAG and feed only the
    // ciphertext as inData. Missing this made every unseal fail, so cached
    // passwords were never actually restored.
    const full = b64.decodeSync(ciphertextB64);
    const TAG_LEN = 16;
    const ct  = full.slice(0, full.length - TAG_LEN);
    const tag = full.slice(full.length - TAG_LEN);

    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,   value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,  value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING,    value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
      { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag },
    ];
    const opts: huks.HuksOptions = {
      properties: props,
      inData: ct,
    };

    const session = await huks.initSession(HUKS_ALIAS, opts);
    const result = await huks.finishSession(session.handle, opts);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(result.outData!));
  }
}

export const CredentialStore = new CredentialStoreImpl();
