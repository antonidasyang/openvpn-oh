import hilog from '@ohos.hilog';

const DOMAIN = 0xD002F00;

// Strict ArkTS rejects parameter-property shorthand, so we declare the field
// and assign it in the constructor body.
export class Logger {
  private readonly tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  info(msg: string, ...args: Object[]): void {
    hilog.info(DOMAIN, this.tag, '%{public}s', this.fmt(msg, args));
  }
  warn(msg: string, ...args: Object[]): void {
    hilog.warn(DOMAIN, this.tag, '%{public}s', this.fmt(msg, args));
  }
  error(msg: string, ...args: Object[]): void {
    hilog.error(DOMAIN, this.tag, '%{public}s', this.fmt(msg, args));
  }
  debug(msg: string, ...args: Object[]): void {
    hilog.debug(DOMAIN, this.tag, '%{public}s', this.fmt(msg, args));
  }

  private fmt(msg: string, args: Object[]): string {
    if (args.length === 0) return msg;
    const parts: string[] = [];
    for (const a of args) {
      if (typeof a === 'string') {
        parts.push(a);
      } else {
        try {
          parts.push(JSON.stringify(a));
        } catch (e) {
          parts.push(String(a));
        }
      }
    }
    return msg + ' ' + parts.join(' ');
  }
}

export function logger(tag: string): Logger {
  return new Logger(tag);
}
