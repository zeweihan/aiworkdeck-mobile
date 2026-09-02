import { myProjects, setSelectedProject, logout } from '../../utils/api'
import type { ApiError, RelayProject } from '../../utils/api'
import type { Metrics } from '../../utils/layout'
import { Icon } from '../../utils/icons'
import { t } from '../../utils/i18n'

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
  },

  onPageScroll(e: { scrollTop: number }) {
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) {
      this.setData({ scrollTop: e.scrollTop })
    }
  },

  onPullDownRefresh() {
    this.loadProjects(() => wx.stopPullDownRefresh())
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
