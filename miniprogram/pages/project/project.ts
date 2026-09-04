import { myProjects, setSelectedProject, logout, billingBalance } from '../../utils/api'
import type { ApiError, RelayProject, BillingBalance } from '../../utils/api'
import type { Metrics } from '../../utils/layout'
import { Icon } from '../../utils/icons'
import { t } from '../../utils/i18n'
import { formatMoney, shouldHideBalanceRow } from '../../utils/money'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

interface ProjectGroup {
  deviceId: string
  deviceName: string
  items: RelayProject[]
}

/** 按 deviceId 分组，组内保持后端返回顺序；组头取 deviceName，取不到时兜底「桌面设备」。 */
function groupByDevice(list: RelayProject[]): ProjectGroup[] {
  const order: string[] = []
  const map = new Map<string, ProjectGroup>()
  for (const item of list) {
    let group = map.get(item.deviceId)
    if (!group) {
      group = { deviceId: item.deviceId, deviceName: item.deviceName || '桌面设备', items: [] }
      map.set(item.deviceId, group)
      order.push(item.deviceId)
    }
    group.items.push(item)
  }
  return order.map((id) => map.get(id)!)
}

/** 金额格式化按契约统一口径（contract/schema/billing.schema.json），不在这里重写。 */
function formatBalance(b: BillingBalance): string {
  return t('balance.amount', { amount: formatMoney(b.balanceCents, b.currency) })
}

Page({
  data: {
    Icon,
    emptyText: t('empty.projects'),
    navTitle: t('project.title'),
    retryText: t('project.retry'),
    signOutText: t('common.signOut'),
    metrics: {} as Metrics,
    showBack: false,
    scrollTop: 0,
    loading: true,
    errorMessage: '',
    groups: [] as ProjectGroup[],
    balanceTitle: t('balance.title'),
    // 未知态（还没拉到结果）不渲染，避免先出现空壳行再消失的首帧闪烁
    // （dev-board#425 二轮复审 N6）。balanceVisible 变 true 的唯一两处在 loadBalance()：
    // 拉成功，或拉到「会自己恢复」的失败态。
    balanceVisible: false,
    balanceText: '',
  },

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({
      metrics: app.globalData.metrics,
      // 从 index「切换项目」navigateTo 过来时页面栈里还有上一页，可以返回；
      // 登录后的守门 reLaunch 过来时本页是栈底，不给返回按钮。
      showBack: getCurrentPages().length > 1,
    })
  },

  onShow() {
    this.loadProjects()
    this.loadBalance()
  },

  onPageScroll(e: { scrollTop: number }) {
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) {
      this.setData({ scrollTop: e.scrollTop })
    }
  },

  onPullDownRefresh() {
    this.loadProjects(() => wx.stopPullDownRefresh())
    this.loadBalance()
  },

  loadProjects(done?: () => void) {
    this.setData({ loading: true, errorMessage: '' })
    myProjects()
      .then((list) => {
        this.setData({ loading: false, groups: groupByDevice(list) })
      })
      .catch((err: ApiError) => {
        this.setData({ loading: false, errorMessage: err.message })
      })
      .finally(() => done?.())
  },

  /** 独立于项目列表加载，读不到余额不拖垮整页。加载中保持不渲染（N6：未知态不是
   *  「显示占位再消失」，是压根不出现），落定后一律按 Envelope.kind 分支，不匹配
   *  message 措辞（contract/schema/billing.schema.json UI 映射，N2）：
   *  NOT_CONNECTED / DISABLED / REVIEW_ACCOUNT 是永远不会自己恢复的终态，整行不渲染；
   *  其余一切失败（含 kind 缺席，即非 billing 专有的失败走了通用 handler）→ 显示
   *  balance.unavailable，绝不能把上游故障说成没有账户。 */
  loadBalance() {
    // 刻意不在这里把 balanceVisible 置回 false：onShow 与下拉刷新都会重进这里，
    // 清空会让已经稳定显示的余额行先消失再出现。首帧不渲染靠 data 里的初值，
    // 落定后才由下面两条路径决定显隐（iOS 的 .task 与安卓的 LaunchedEffect(Unit)
    // 只在首次出现时跑一次，本端多跑几次也要保持同样的观感）。
    billingBalance()
      .then((b) => {
        this.setData({ balanceVisible: true, balanceText: formatBalance(b) })
      })
      .catch((err: ApiError) => {
        if (shouldHideBalanceRow(err.kind)) {
          this.setData({ balanceVisible: false })
          return
        }
        this.setData({ balanceVisible: true, balanceText: t('balance.unavailable') })
      })
  },

  onRetry() {
    this.loadProjects()
  },

  onRefresh() {
    this.loadProjects()
  },

  onSelectProject(e: { currentTarget: { dataset: { gi: number; ii: number } } }) {
    const { gi, ii } = e.currentTarget.dataset
    const project = this.data.groups[gi].items[ii]
    setSelectedProject(project)
    wx.reLaunch({ url: '/pages/index/index' })
  },

  onLogout() {
    wx.showModal({
      title: t('common.signOut'),
      content: '退出后需要重新用手机号登录。',
      confirmText: '退出',
      confirmColor: '#B91C1C',
      success: (res) => {
        if (res.confirm) {
          logout()
          wx.reLaunch({ url: '/pages/login/login' })
        }
      },
    })
  },
})
