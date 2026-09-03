import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppModel } from '../AppModel';
import { ServiceLocator } from '../services/ServiceLocator';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 装配在这里而不是页面里：后台上传任务与录音服务（Task 5）都要拿同一批实例，
    // 装配两遍就等于两条互不知情的队列。
    ServiceLocator.init(this.context);
    hilog.info(DOMAIN, 'workdeck', '%{public}s', 'EntryAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'workdeck', '%{public}s', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Root', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'workdeck', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'workdeck', '%{public}s', 'EntryAbility onWindowStageDestroy');
  }

  /** 回到前台：磁盘可能被后台上传任务改过，队列也可能停在半路（AppModel 自己判断有没有启动过）。 */
  onForeground(): void {
    AppModel.shared.onForeground();
    hilog.info(DOMAIN, 'workdeck', '%{public}s', 'EntryAbility onForeground');
  }

  /**
   * 退到后台。**不停录音**——录音靠 AUDIO_RECORDING 长时任务在后台继续，这正是 #407 要的。
   * 相机与录像的停止是 Task 6 的事（摄像头在后台留不住）。
   */
  onBackground(): void {
    hilog.info(DOMAIN, 'workdeck', '%{public}s', 'EntryAbility onBackground');
  }
}
