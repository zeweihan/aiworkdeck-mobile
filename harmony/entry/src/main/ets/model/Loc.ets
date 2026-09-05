/**
 * 拍摄时的定位信息，精度可能拿不到（例如室内）。
 *
 * 放在领域层而不是服务层：水印格式化要在 Node 里对拍（`tests/harmony/watermark.test.ts`），
 * 而领域层不许 import `@ohos.*`。
 */
export interface Loc {
  lat: number
  lon: number
  accuracy: number | null
}
