// 仅供 `npm test` 使用的 ESM resolve / load 钩子。
//
// ① miniprogram/ 下的 .ts 互相 import 时不带扩展名（WeChat DevTools 的 TS 编译按这个约定解析），
//    但 Node 原生跑 .ts（type stripping）不会自动补扩展名，裸的相对 import 会
//    ERR_MODULE_NOT_FOUND。这里在解析失败时补一次 `.ts`、再补一次 `.ets` 重试。
// ② 鸿蒙领域层是 .ets：Node 不认这个扩展名，用 typescript.transpileModule 转成 ESM 再交给 Node。
//    ArkTS 是 TS 的子集，纯逻辑文件（不引 @ohos/@kit）这样就能在 Node 里跑契约夹具。
// ③ 裸说明符 `contract` 映射到 harmony/contract/Index.ets，与 entry 模块里的 HAR 依赖同名。
//
// 只影响本进程的测试运行，不改各端源码，也不影响 DevEco / WeChat DevTools 的编译。
import { register } from 'node:module'
import { readFileSync } from 'node:fs'
import ts from 'typescript'

register(import.meta.url, import.meta.url)

const ROOT = new URL('../', import.meta.url)

export async function resolve(specifier, context, nextResolve) {
  if (specifier === 'contract') {
    return { url: new URL('harmony/contract/Index.ets', ROOT).href, shortCircuit: true }
  }
  try {
    return await nextResolve(specifier, context)
  } catch (err) {
    if (err && err.code === 'ERR_MODULE_NOT_FOUND' && specifier.startsWith('.')) {
      try {
        return await nextResolve(`${specifier}.ts`, context)
      } catch {
        return nextResolve(`${specifier}.ets`, context)
      }
    }
    throw err
  }
}

export async function load(url, context, nextLoad) {
  if (!url.endsWith('.ets')) return nextLoad(url, context)
  const src = readFileSync(new URL(url), 'utf8')
  const out = ts.transpileModule(src, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  })
  return { format: 'module', source: out.outputText, shortCircuit: true }
}
