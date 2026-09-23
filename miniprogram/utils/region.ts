import { DEGRADED_NOTICE } from './contract/capabilities'
import { t, type Locale } from './i18n'

/** 登录页的账号区域（dev-board#839）。大陆版是默认，行为与改前的登录页一致。 */
export type LoginRegion = 'cn' | 'intl'

export interface RegionView {
  /** 一键登录 / 短信表单是否可用 */
  showLogin: boolean
  /** 不能登录时给的说明；可登录时为空串 */
  notice: string
}

/** 语言跟随区域：大陆版中文，海外版英文。 */
export function localeFor(region: LoginRegion): Locale {
  return region === 'intl' ? 'en' : 'zh-Hans'
}

/**
 * 区域 → 登录页该显示什么。能力开关 intlAccount 由调用方传 CAPS.intlAccount，
 * 不在这里写死：小程序因请求域名须 ICP 备案（workdeck.ai 备不了）当前为 false。
 * notice 按调用时的语言取词，调用方先 setLocale(localeFor(region)) 再调本函数。
 */
export function regionView(region: LoginRegion, intlAccount: boolean): RegionView {
  if (region === 'intl' && !intlAccount) {
    return { showLogin: false, notice: t(DEGRADED_NOTICE.intlAccount) }
  }
  return { showLogin: true, notice: '' }
}
