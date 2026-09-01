#!/usr/bin/env python3
"""上架前那几项 deliver 管不到的 App Store Connect 设置。

fastlane 的 upload_to_app_store 负责二进制、文案、截图；剩下这些它要么没有
对应参数、要么参数形状跟不上 Apple 2026 年改版后的问卷，只能直接打 API：

  rating        年龄分级问卷（全部答「无」）
  contentrights 内容版权声明（不含第三方内容）
  price         价格表设为免费
  availability  上架区域（国际版排除中国大陆，大陆版只留中国大陆）
  status        只读：把提审前的必填项逐条列出来，缺哪项一目了然

用法（凭据从 fastlane/.env 读，见 5-Tech/EXTERNAL_SERVICES.md §6）：

    set -a; . fastlane/.env; set +a
    .venv/bin/python scripts/asc-listing.py status intl
    .venv/bin/python scripts/asc-listing.py rating cn

年龄分级的字段类型 Apple 改过不止一次（2026 版把 messagingAndChat、gambling
等一批从枚举改成了布尔）。这里不写死类型表：先一律按枚举 "NONE" 提交，拿
ENTITY_ERROR.ATTRIBUTE.TYPE 的报错把该改布尔的挑出来再提交一次。Apple 下次
再改，这段不用跟着改。
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import jwt

BASE = "https://api.appstoreconnect.apple.com/v1"
BASE_V2 = "https://api.appstoreconnect.apple.com/v2"

APPS = {
    # 国际版：真善美承澤（香港，Team X9B97KVA84）
    "intl": {"app_id": "6802233845", "env": ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH")},
    # 大陆版：北京京微资易（Team 8WKHZVR2W8）
    "cn": {"app_id": "6803309103", "env": ("ASC_CN_KEY_ID", "ASC_CN_ISSUER_ID", "ASC_CN_KEY_PATH")},
}

# 年龄分级问卷。这个 App 没有任何一项受限内容，全答「无」。
# 值只是初始猜测，布尔字段会被下面的类型协商自动改成 False。
RATING_FIELDS = [
    "advertising", "alcoholTobaccoOrDrugUseOrReferences", "contests", "gambling",
    "gamblingSimulated", "gunsOrOtherWeapons", "healthOrWellnessTopics", "lootBox",
    "medicalOrTreatmentInformation", "messagingAndChat", "parentalControls",
    "profanityOrCrudeHumor", "ageAssurance", "sexualContentGraphicAndNudity",
    "sexualContentOrNudity", "socialMedia", "socialMediaAgeRestricted",
    "horrorOrFearThemes", "matureOrSuggestiveThemes", "unrestrictedWebAccess",
    "userGeneratedContent", "violenceCartoonOrFantasy",
    "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic",
]


def token(kid, iss, key_path):
    key = open(os.path.expanduser(key_path)).read()
    payload = {"iss": iss, "iat": int(time.time()), "exp": int(time.time()) + 1200,
               "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def token_for(flavor):
    keys = APPS[flavor]["env"]
    missing = [k for k in keys if not os.environ.get(k)]
    if missing:
        sys.exit(f"缺少环境变量 {', '.join(missing)}——先 `set -a; . fastlane/.env; set +a`")
    return token(*(os.environ[k] for k in keys))


def call(tok, method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(
        url, method=method,
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        raw = urllib.request.urlopen(req).read()
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return {"ERROR": e.code, "body": json.loads(raw)}
        except ValueError:
            return {"ERROR": e.code, "body": raw.decode()[:500]}


def errors_of(resp):
    if "ERROR" not in resp:
        return []
    body = resp["body"]
    return body.get("errors", []) if isinstance(body, dict) else []


def die_on_error(resp, what):
    for e in errors_of(resp):
        print(f"  ! {e.get('code')} {e.get('detail')}", file=sys.stderr)
    if "ERROR" in resp:
        sys.exit(f"{what} 失败（HTTP {resp['ERROR']}）")
    return resp


# ---------------------------------------------------------------- 读取

def app_info_id(tok, app_id):
    r = call(tok, "GET", f"/apps/{app_id}/appInfos")
    die_on_error(r, "读取 appInfos")
    return r["data"][0]["id"]


def version(tok, app_id):
    """当前那条可编辑的版本记录。已提审/已上架的版本不在这里改。"""
    r = call(tok, "GET", f"/apps/{app_id}/appStoreVersions?limit=10")
    die_on_error(r, "读取 appStoreVersions")
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                "METADATA_REJECTED", "INVALID_BINARY"}
    for v in r["data"]:
        if v["attributes"]["appStoreState"] in editable:
            return v
    return r["data"][0] if r["data"] else None


# ---------------------------------------------------------------- 动作

def cmd_rating(tok, app_id):
    decl_id = app_info_id(tok, app_id)   # ageRatingDeclaration 与 appInfo 同 id
    attrs = {f: "NONE" for f in RATING_FIELDS}

    for attempt in range(3):
        body = {"data": {"type": "ageRatingDeclarations", "id": decl_id, "attributes": attrs}}
        r = call(tok, "PATCH", f"/ageRatingDeclarations/{decl_id}", body)
        if "ERROR" not in r:
            print(f"年龄分级已提交（{len(attrs)} 项全部为「无」）")
            return
        # 只把类型报错吃掉，其余照常抛出——静默吞错会让人以为设成功了
        flipped = False
        for e in errors_of(r):
            if e.get("code") != "ENTITY_ERROR.ATTRIBUTE.TYPE":
                continue
            m = re.search(r"/data/attributes/([A-Za-z]+)", e.get("source", {}).get("pointer", ""))
            if m and "BOOLEAN" in e.get("detail", ""):
                attrs[m.group(1)] = False
                flipped = True
        if not flipped:
            die_on_error(r, "设置年龄分级")
    sys.exit("年龄分级：类型协商三轮仍未通过，去网页填")


def cmd_contentrights(tok, app_id):
    body = {"data": {"type": "apps", "id": app_id,
                     "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}
    die_on_error(call(tok, "PATCH", f"/apps/{app_id}", body), "设置内容版权声明")
    print("内容版权声明已设为「不含第三方内容」")


def cmd_price(tok, app_id):
    """免费。价格表要挑一个 CUSTOMER_PRICE 为 0 的价位点。"""
    r = call(tok, "GET", f"/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=200")
    die_on_error(r, "读取价位点")
    free = [p for p in r.get("data", [])
            if str(p["attributes"].get("customerPrice")) in ("0", "0.0", "0.00")]
    if not free:
        sys.exit("没找到 0 元价位点——去网页设免费")
    body = {"data": {"type": "appPriceSchedules",
                     "relationships": {
                         "app": {"data": {"type": "apps", "id": app_id}},
                         "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                         "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]}}},
            "included": [{"type": "appPrices", "id": "${price1}",
                          "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {
                              "data": {"type": "appPricePoints", "id": free[0]["id"]}}}}]}
    die_on_error(call(tok, "POST", "/appPriceSchedules", body), "设置免费定价")
    print("价格已设为免费")


def cmd_availability(tok, app_id, flavor):
    """上架区域。

    大陆版只上中国大陆，国际版上其余全部区域——两个 App 是同一个产品的两份
    发行，重叠上架等于在同一个区里放两个一样的东西。国际版本来也进不了中国
    大陆：没有 ICP 备案号，那个区直接不可选。

    v2 的 appAvailabilities 不接受「只报要开的区」：**所有区都得列全**，
    每个区自己带 available 真假。少一个就 409 报那个区没被 included。
    """
    r = call(tok, "GET", "/territories?limit=200")
    die_on_error(r, "读取区域列表")
    territories = [t["id"] for t in r["data"]]
    if "CHN" not in territories:
        sys.exit("区域列表里没有 CHN，别往下走")

    want_cn_only = flavor == "cn"
    refs, included = [], []
    for t in territories:
        available = (t == "CHN") if want_cn_only else (t != "CHN")
        key = f"t-{t}"
        refs.append({"type": "territoryAvailabilities", "id": "${" + key + "}"})
        included.append({
            "type": "territoryAvailabilities", "id": "${" + key + "}",
            "attributes": {"available": available},
            "relationships": {"territory": {"data": {"type": "territories", "id": t}}}})

    body = {"data": {"type": "appAvailabilities",
                     # 新开的区不自动跟进：大陆版永远只该有一个区，国际版新增区
                     # 由人决定要不要上，别让区域清单自己长。
                     "attributes": {"availableInNewTerritories": False},
                     "relationships": {
                         "app": {"data": {"type": "apps", "id": app_id}},
                         "territoryAvailabilities": {"data": refs}}},
            "included": included}
    resp = call(tok, "POST", BASE_V2 + "/appAvailabilities", body)
    die_on_error(resp, "设置上架区域")
    on = sum(1 for i in included if i["attributes"]["available"])
    print(f"上架区域已设置：{on}/{len(territories)} 个区可用"
          f"（{'仅中国大陆' if want_cn_only else '中国大陆除外'}）")


def cmd_status(tok, app_id, flavor):
    """提审前必填项体检。只读，不改任何东西。"""
    app = call(tok, "GET", f"/apps/{app_id}")
    die_on_error(app, "读取 app")
    a = app["data"]["attributes"]
    v = version(tok, app_id)
    info = call(tok, "GET", f"/apps/{app_id}/appInfos")
    ia = info["data"][0]["attributes"]
    rating = call(tok, "GET", f"/appInfos/{info['data'][0]['id']}/ageRatingDeclaration")
    ra = rating.get("data", {}).get("attributes", {})

    print(f"== {flavor} / {a['name']} / {a['bundleId']} ==")
    print(f"版本            {v['attributes']['versionString']}  {v['attributes']['appStoreState']}")
    print(f"内容版权声明    {a.get('contentRightsDeclaration') or '未填'}")
    print(f"年龄分级        {ia.get('appStoreAgeRating') or '未填'}")
    # 只看问卷本身：ageRatingOverride 这类字段建记录时就有值，拿它判断会永远显示「已答」
    answered = sum(1 for f in RATING_FIELDS if ra.get(f) is not None)
    print(f"分级问卷        {answered}/{len(RATING_FIELDS)} 项已答")

    locs = call(tok, "GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=20")
    have = [l["attributes"]["locale"] for l in locs.get("data", [])]
    print(f"版本文案语言    {', '.join(have) if have else '无'}")
    for loc in locs.get("data", []):
        la = loc["attributes"]
        shots = call(tok, "GET",
                     f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=20")
        n = len(shots.get("data", []))
        print(f"  {la['locale']:<8} 描述{'有' if la.get('description') else '缺'} "
              f"关键词{'有' if la.get('keywords') else '缺'} "
              f"支持URL{'有' if la.get('supportUrl') else '缺'} 截图组 {n}")

    build = call(tok, "GET", f"/appStoreVersions/{v['id']}/build")
    b = build.get("data") if "ERROR" not in build else None
    print(f"已挂构建        {b['id'] if b else '未挂'}")
    review = call(tok, "GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail")
    rdata = review.get("data") if "ERROR" not in review else None
    rd = rdata.get("attributes") if rdata else None
    print(f"审核联系信息    {'已填' if rd and rd.get('contactEmail') else '未填'}")
    print(f"演示账号        {'已填' if rd and rd.get('demoAccountName') else '未填'}")
    if flavor == "cn":
        print("ICP 备案号      API 不开放，去网页「App 信息」核对（京ICP备2024096997号-13A）")
    print("隐私营养标签    API 未在本脚本覆盖，去网页「App 隐私」核对")


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in APPS:
        sys.exit(__doc__)
    cmd, flavor = sys.argv[1], sys.argv[2]
    tok = token_for(flavor)
    app_id = APPS[flavor]["app_id"]
    if cmd == "rating":
        cmd_rating(tok, app_id)
    elif cmd == "contentrights":
        cmd_contentrights(tok, app_id)
    elif cmd == "price":
        cmd_price(tok, app_id)
    elif cmd == "availability":
        cmd_availability(tok, app_id, flavor)
    elif cmd == "status":
        cmd_status(tok, app_id, flavor)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
