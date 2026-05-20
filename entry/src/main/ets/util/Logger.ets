import hilog from '@ohos.hilog';

const DOMAIN = 0xD002F00;

export class Logger {
  constructor(private readonly tag: string) {}

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
    return msg + ' ' + args.map(a => {
      try { return typeof a === 'string' ? a : JSON.stringify(a); }
      catch { return String(a); }
    }).join(' ');
  }
}

export function logger(tag: string): Logger {
  return new Logger(tag);
}
