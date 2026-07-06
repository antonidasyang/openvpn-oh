import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

import { OvpnEngine } from '../service/OvpnEngine';
import { ProfileStore } from '../model/ProfileStore';
import { Profile, newProfileId } from '../model/Profile';
import { logger } from '../util/Logger';

const log = logger('ImportConfig');

@Entry
@Component
struct ImportConfig {
  @State private configText: string = '';
  @State private displayName: string = '';
  @State private evalError: string = '';
  @State private parsedHost: string = '';
  @State private parsedPort: string = '';
  @State private parsedProto: string = '';
  @State private autologin: boolean = true;
  @State private pkPwdRequired: boolean = false;
  @State private saving: boolean = false;

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 16 }) {
          this.PickerRow()
          this.DisplayNameField()
          this.ConfigArea()
          this.SummaryCard()
          this.ActionRow()
        }
        .padding(16)
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.surface_dim'))
  }

  @Builder
  private TopBar() {
    Row() {
      Button('<')
        .width(40).height(40)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.on_surface'))
        .onClick((): void => { this.getUIContext().getRouter().back(); })
      Text($r('app.string.title_import'))
        .fontSize(18).fontWeight(FontWeight.Bold)
        .margin({ left: 8 })
        .fontColor($r('app.color.on_surface'))
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  private PickerRow() {
    Row({ space: 12 }) {
      Button($r('app.string.action_import_file'))
        .layoutWeight(1)
        .backgroundColor($r('app.color.brand_primary'))
        .onClick(() => this.pickFile())
    }
    .width('100%')
  }

  @Builder
  private DisplayNameField() {
    Column({ space: 6 }) {
      Text('Name')
        .fontSize(13).fontColor($r('app.color.on_surface_dim'))
      TextInput({ placeholder: 'Office VPN', text: this.displayName })
        .onChange(v => { this.displayName = v; })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .padding(12)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private ConfigArea() {
    Column({ space: 6 }) {
      Text($r('app.string.action_import_paste'))
        .fontSize(13).fontColor($r('app.color.on_surface_dim'))
      TextArea({ placeholder: 'client\ndev tun\nproto udp\nremote vpn.example.com 1194\n...', text: this.configText })
        .onChange(v => {
          this.configText = v;
          this.evaluate();
        })
        .height(220)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .padding(12)
        .fontFamily('HarmonyOS Sans Mono')
        .fontSize(13)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private SummaryCard() {
    if (this.configText) {
      Column({ space: 8 }) {
        if (this.evalError) {
          Text(this.evalError)
            .fontSize(13).fontColor($r('app.color.status_error'))
        } else {
          this.KV($r('app.string.label_remote'),   `${this.parsedHost}:${this.parsedPort}`)
          this.KV($r('app.string.label_protocol'), this.parsedProto || 'udp')
          this.KV($r('app.string.label_username'), this.autologin ? '— (cert auth)' : 'required')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .width('100%')
    }
  }

  @Builder
  private KV(label: Resource, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.on_surface_dim')).layoutWeight(1)
      Text(value).fontSize(14).fontColor($r('app.color.on_surface'))
    }
    .width('100%')
  }

  @Builder
  private ActionRow() {
    Row({ space: 12 }) {
      Button($r('app.string.action_cancel'))
        .layoutWeight(1)
        .backgroundColor($r('app.color.surface'))
        .fontColor($r('app.color.on_surface'))
        .onClick((): void => { this.getUIContext().getRouter().back(); })
      Button($r('app.string.action_save'))
        .layoutWeight(1)
        .enabled(!!this.configText && !this.evalError && !this.saving)
        .backgroundColor($r('app.color.brand_primary'))
        .onClick(() => this.save())
    }
    .width('100%').margin({ top: 8 })
  }

  // ----- Logic -----

  // Opened via the system "打开方式" on a .ovpn file: Index routes here with the
  // file uri as a param; read + pre-fill it for review.
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    const uri: string = params ? ((params['importUri'] as string) ?? '') : '';
    if (uri.length > 0) {
      this.loadFromUri(uri);
    }
  }

  private async pickFile(): Promise<void> {
    try {
      const opts = new picker.DocumentSelectOptions();
      opts.fileSuffixFilters = ['.ovpn', '.conf'];
      const docPicker = new picker.DocumentViewPicker();
      const uris = await docPicker.select(opts);
      if (!uris || uris.length === 0) return;
      await this.loadFromUri(uris[0]);
    } catch (e) {
      log.error('pickFile failed', e as Object);
      this.evalError = (e as Error).message ?? String(e);
    }
  }

  // Read an .ovpn file from a uri (from the picker or a file-open want) and
  // pre-fill the form.
  private async loadFromUri(uri: string): Promise<void> {
    try {
      const fd = fs.openSync(uri, fs.OpenMode.READ_ONLY).fd;
      const stat = fs.statSync(fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(fd, buf);
      fs.closeSync(fd);
      this.configText = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      if (!this.displayName) {
        const slash = uri.lastIndexOf('/');
        const base = uri.substring(slash + 1).replace(/\.(ovpn|conf)$/i, '');
        this.displayName = base;
      }
      this.evaluate();
    } catch (e) {
      log.error('loadFromUri failed', e as Object);
      this.evalError = (e as Error).message ?? String(e);
    }
  }

  private evaluate(): void {
    if (!this.configText) {
      this.evalError = '';
      this.parsedHost = ''; this.parsedPort = ''; this.parsedProto = '';
      return;
    }
    const engine = new OvpnEngine();
    try {
      const r = engine.evalConfig(this.configText);
      if (r.error) {
        this.evalError = r.message;
        return;
      }
      this.evalError = '';
      this.parsedHost = r.remoteHost;
      this.parsedPort = r.remotePort;
      this.parsedProto = r.remoteProto;
      this.autologin = r.autologin;
      this.pkPwdRequired = r.privateKeyPasswordRequired;
      if (!this.displayName && r.profileName) this.displayName = r.profileName;
    } finally {
      engine.dispose();
    }
  }

  private async save(): Promise<void> {
    this.saving = true;
    try {
      const profile: Profile = {
        id: newProfileId(),
        displayName: this.displayName || this.parsedHost || 'OVPN',
        configText: this.configText,
        remoteHost: this.parsedHost,
        remotePort: this.parsedPort,
        remoteProto: this.parsedProto || 'udp',
        autologin: this.autologin,
        privateKeyPasswordRequired: this.pkPwdRequired,
        staticChallenge: '',
        staticChallengeEcho: false,
        externalPki: false,
        createdAt: Date.now(),
        lastConnectedAt: 0,
      };
      await ProfileStore.upsert(profile);
      this.getUIContext().getRouter().back();
    } catch (e) {
      log.error('save failed', e as Object);
      this.evalError = (e as Error).message ?? String(e);
    } finally {
      this.saving = false;
    }
  }
}
