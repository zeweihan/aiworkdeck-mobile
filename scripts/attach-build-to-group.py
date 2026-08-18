#!/usr/bin/env python3
"""把最新构建挂进内部测试组。

**为什么需要这个脚本**：fastlane 的 upload_to_testflight 设了
`skip_waiting_for_build_processing: true` 就会传完即退，**不做任何后续动作，
包括分组**。结果是构建在 App Store Connect 里全都 VALID，但测试组里一个都没有，
手机上 TestFlight 只能看到最早那个手动关联过的版本——2026-08-18 实际踩过，
连发五版都没送到测试员手上。

不改成等待处理是因为那要多花 5-15 分钟；这里改成传完之后轮询 + 关联。
"""
import json, os, sys, time, urllib.request
import jwt

APP_ID = os.environ.get("ASC_APP_ID", "6802233845")
KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]

tok = jwt.encode(
    {"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 900,
     "aud": "appstoreconnect-v1"},
    open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(path, method="GET", payload=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(payload).encode() if payload else None,
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"},
        method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read()
            return json.loads(body) if body else {"ok": True}
    except Exception as e:
        return {"ERROR": e.read().decode()[:250] if hasattr(e, "read") else str(e)}


groups = call(f"/v1/apps/{APP_ID}/betaGroups?limit=10").get("data", [])
internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
if not internal:
    sys.exit("没有内部测试组，先在 App Store Connect 建一个")
gid = internal[0]["id"]
gname = internal[0]["attributes"].get("name")

# 刚传完的构建要几分钟才 VALID，PROCESSING 状态下关联会被拒
for attempt in range(30):
    builds = call(f"/v1/builds?filter[app]={APP_ID}&limit=1").get("data", [])
    if builds and builds[0]["attributes"].get("processingState") == "VALID":
        break
    print(f"  等待构建处理完成…（{attempt + 1}/30）")
    time.sleep(20)
else:
    sys.exit("构建 30 次轮询后仍未 VALID，稍后手动跑本脚本")

bid = builds[0]["id"]
ver = builds[0]["attributes"].get("version")
r = call(f"/v1/builds/{bid}/relationships/betaGroups", "POST",
         {"data": [{"type": "betaGroups", "id": gid}]})
if "ERROR" in r:
    sys.exit(f"关联失败: {r['ERROR']}")
print(f"  build {ver} 已挂进「{gname}」，TestFlight 里可见")
