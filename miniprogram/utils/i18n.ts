import { STRINGS } from './contract/strings'

/** 小程序只发大陆，固定 zh-Hans。缺键回显键名，便于走查时一眼看出没接契约。 */
export function t(key: string, vars: Record<string, string | number> = {}): string {
  const entry = STRINGS[key]
  let s = entry ? entry['zh-Hans'] : key
  for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v))
  return s
}
