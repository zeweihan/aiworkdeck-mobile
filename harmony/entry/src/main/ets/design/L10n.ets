import { ContractStrings } from 'contract'

export const LOCALE_ZH: string = 'zh-Hans'
export const LOCALE_EN: string = 'en'

/**
 * 界面语言的可观察副本放在 AppStorage 的这个键下（ServiceLocator.applyRegion 写入）。
 * 语言一变要当场重绘的页面（登录页）用 `@StorageProp('awdLocale')` 订阅并经 `trIn` 取文案；
 * 其余页面只在登录后才出现，那时语言已经定了，建页时直接 `tr` 即可。
 */
export const LOCALE_STORAGE_KEY: string = 'awdLocale'

/**
 * 当前界面语言（dev-board#837）：跟随账号区域，大陆版 zh-Hans、海外版 en。
 * 这里是纯 ArkTS（Node 侧单测直接跑），不碰 AppStorage；可观察那一半在 ServiceLocator。
 */
export class L10n {
  static locale: string = LOCALE_ZH
}

/**
 * 按指定语言查词典。缺该语言的译文回落 zh-Hans，整条缺键回显键名——现场看到键名比看到空白更容易报错。
 * 占位形如 {n}，按 vars 的键逐个替换。
 */
export function trIn(locale: string, key: string, vars?: Record<string, string | number>): string {
  const entry: Record<string, string> | undefined = ContractStrings[key]
  let s: string = key
  if (entry !== undefined) {
    const hit: string | undefined = entry[locale]
    s = hit !== undefined && hit.length > 0 ? hit : entry[LOCALE_ZH]
  }
  if (vars !== undefined) {
    const names: string[] = Object.keys(vars)
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i]
      s = s.split('{' + name + '}').join(`${vars[name]}`)
    }
  }
  return s
}

/** 按当前界面语言查词典。 */
export function tr(key: string, vars?: Record<string, string | number>): string {
  return trIn(L10n.locale, key, vars)
}
