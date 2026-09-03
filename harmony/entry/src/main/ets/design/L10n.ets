import { ContractStrings } from 'contract'

/**
 * 界面文案。语言固定 zh-Hans（首版不做英文 UI，spec H12）。
 * 缺键回显键名——现场看到键名比看到空白更容易报错。
 * 占位形如 {n}，按 vars 的键逐个替换。
 */
export function tr(key: string, vars?: Record<string, string | number>): string {
  const entry: Record<string, string> | undefined = ContractStrings[key]
  let s: string = entry !== undefined ? entry['zh-Hans'] : key
  if (vars !== undefined) {
    const names: string[] = Object.keys(vars)
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i]
      s = s.split('{' + name + '}').join(`${vars[name]}`)
    }
  }
  return s
}
