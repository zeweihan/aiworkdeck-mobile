# AGC（AppGallery Connect）文案字段映射

来源：iOS `fastlane/metadata/zh-Hans/*.txt` 的定稿文案，按 AGC 上传应用时的
「可本地化基础信息」字段结构拆分落地。改动顺序照抄 iOS/安卓那份：先改 iOS
`fastlane/metadata/`，再回来同步这里——不要在这里单独改词。

## 字段映射与上限

| 文件 | AGC 字段 | 上限 | 本文件字数 | 上限来源 |
|---|---|---|---|---|
| `name.txt` | 应用名称 | 待核（安卓各商店 15-30 字符不等，AGC 具体值未查到官方数字） | 11 | 未查到 developer.huawei.com 官方页面标注的具体数字；上传表单会实时校验，以后台提示为准 |
| `short_description.txt` | 应用简介（一句话简介） | 待核——第三方资料冲突：ASO 机构 phiture.com 称「最多 80 字符」，另有 CSDN 教程称「5-15 字符」或「60 字符」 | 13 | phiture.com《Listing on AppGallery: A step-by-step guide》（查证日期 2026-09-13，URL: https://phiture.com/asostack/listing-on-appgallery-a-step-by-step-guide-and-a-glance-of-the-developer-console-4dcc6169a7c0/）；CSDN 教程类文章号称 5-15 或 60 字符，来源不一，两者均非 developer.huawei.com 官方文档，仅供参考。13 字符在两种说法的范围内均安全 |
| `full_description.txt` | 应用介绍 | 待核——第三方资料称「100-8000 字符」 | 约 490 | 同上 phiture.com 页面（查证日期 2026-09-13）；未找到官方页面明确数字 |
| `release_notes.txt` | 新版本特性 / 更新说明 | 待核——第三方资料称「最多 1000 字符」 | 约 90 | 同上 phiture.com 页面（查证日期 2026-09-13）；未找到官方页面明确数字 |

## 未验证说明

以上「上限」列均标注为**待核**：AGC 上传应用需要开发者账号登录后台才能看到实时字段
校验规则，本次调研只能查到第三方 ASO 博客与教程类文章给出的数字，彼此不完全一致，也
不是 `developer.huawei.com` 官方文档明确写出的规格页。正式提交前，请以 AGC 后台
「上传应用 → 可本地化基础信息」表单的实时字数提示/校验为准，本文件里的文案字数
（见上表「本文件字数」列）都刻意留有余量，即使按最严格的第三方说法（一句话简介
5-15 字符除外，本文件是 13 字符，仍在范围内）也能过。

`node scripts/store-shots/check-copy.mjs` 会用本表的「上限」列做校验；标「待核」的项
脚本按第三方资料给出的最严格数字（更保守的那个）校验，实际以 AGC 后台为准。
