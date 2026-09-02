// 仅供 `npm test` 使用的 ESM resolve 钩子。
//
// miniprogram/ 下的 .ts 互相 import 时不带扩展名（WeChat DevTools 的 TS 编译按这个约定解析），
// 但 Node 原生跑 .ts（type stripping）不会自动补扩展名，裸的相对 import 会
// ERR_MODULE_NOT_FOUND。这里在解析失败时补一次 `.ts` 重试，只影响本进程的测试运行，
// 不改 miniprogram/ 源码，也不影响 WeChat DevTools 的编译。
import { register } from 'node:module'

register(import.meta.url, import.meta.url)

export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context)
  } catch (err) {
    if (err && err.code === 'ERR_MODULE_NOT_FOUND' && specifier.startsWith('.')) {
      return nextResolve(`${specifier}.ts`, context)
    }
    throw err
  }
}
