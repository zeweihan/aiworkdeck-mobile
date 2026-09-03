/**
 * 查看器要看哪一段。
 *
 * `NavPathInfo.param` 是 `unknown`，ArkTS 里没法安全地把一个条目数组塞进去再取出来
 * （无 `any`、无类型查询），所以打开查看器要看的**那一段的 id 与起点**放在这里，
 * 由 Library 写、Viewer 读。传 id 而不是条目本身：查看器再按 id 去 `AppModel.items`
 * 取当前的那一份，中途被删掉或状态变了都跟着变，不会拿着一份过期快照显示。
 */
export class ViewerRequest {
  static ids: string[] = []
  static index: number = 0
}
