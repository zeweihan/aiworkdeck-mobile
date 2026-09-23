import { STRINGS } from './contract/strings'

/**
 * 界面语言。默认 zh-Hans；登录页切到「海外版」时设为 en（dev-board#839），切回大陆版再设回。
 * 模块级变量不会自己触发重绘：调用方改完语言要把页面上绑定的文案重新 setData 一遍。
 */
export type Locale = 'zh-Hans' | 'en'

let locale: Locale = 'zh-Hans'

export function setLocale(next: Locale): void {
  locale = next
}

export function getLocale(): Locale {
  return locale
}

/** 按当前语言取词典。缺键回显键名，便于走查时一眼看出没接契约。 */
export function t(key: string, vars: Record<string, string | number> = {}): string {
  const entry = STRINGS[key]
  let s = entry ? entry[locale] : key
  for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v))
  return s
}
