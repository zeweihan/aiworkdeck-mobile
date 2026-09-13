#!/usr/bin/env python3
"""把 assets/scenes/ 的现场照片摊成一份「已经拍了一天」的应用私有目录。

产出（写进 --out 指定的暂存目录，由 capture-android.sh 用 run-as 推进沙盒）：

    prefs.xml                      SharedPreferences「prefs」：当前项目、存相册开关
    FieldEvidence/media/<id>.jpg   原件（照片直接拷场景图，录像用 ffmpeg 包一段静帧，录音是静音 m4a）
    FieldEvidence/manifest/<id>.json  StoredRow（与 EvidenceStore 的 kotlinx 序列化同形）

鸿蒙那边灌的是同一批内容，只是走应用内的 debug 种子路径（`--ps awdShots 1`），
所以这份表也是鸿蒙 SeedData.ets 的参照来源；改一处要顺手对齐另一处。

规格：docs/specs/2026-09-13-store-assets-design.md §2 §3。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
from html import escape

# 演示项目：主项目 + 选项目页另外两条（§3）
MAIN = {"deviceId": "dev-shots", "deviceName": "MacBook Pro", "key": "p-1", "name": "华创科技 A 轮尽调"}

# 归档日期 2026-09-12（§3）。时间从早到晚铺开，图集才有一整天的样子。
DAY = "2026-09-12"
TZ = "+08:00"

DEVICE = {"android": ("Pixel 7", "Android 16", "0.1.0"), "harmony": ("HUAWEI Pura 90 Pro", "HarmonyOS 7.0.0", "0.1.0")}

# (场景图序号, 类别, 状态, 时刻, 进度)
# 三种状态都要有样本；含一条录像与一条录音（任务书）。16 件是为了让队列页滚得动，
# 第 3 屏拍顶部（上传中/已暂存），第 7 屏拍滚到底（已落盘）。
ITEMS = [
    (1, "photo", "arrived", "09:12:04", 1.0),
    (2, "photo", "arrived", "09:18:37", 1.0),
    (3, "photo", "arrived", "09:41:12", 1.0),
    (4, "photo", "arrived", "10:02:55", 1.0),
    (5, "photo", "arrived", "10:26:31", 1.0),
    (6, "photo", "arrived", "10:58:09", 1.0),
    (7, "photo", "arrived", "11:20:44", 1.0),
    (8, "photo", "arrived", "11:47:18", 1.0),
    (1, "photo", "arrived", "13:05:22", 1.0),
    (2, "photo", "arrived", "13:39:50", 1.0),
    (3, "audio", "uploaded", "14:02:11", 1.0),
    (4, "photo", "uploaded", "14:31:06", 1.0),
    (5, "photo", "uploaded", "14:52:40", 1.0),
    (6, "video", "uploading", "15:10:27", 0.62),
    (7, "photo", "uploading", "15:14:03", 0.18),
    (8, "photo", "waiting", "15:16:49", 0.0),
]

EXT = {"photo": "jpg", "video": "mp4", "audio": "m4a"}


def stable_id(index: int) -> str:
    """固定 UUID 形状的 id：重跑脚本不产生新一批件，沙盒里也就不会越积越多。"""
    h = hashlib.sha1(f"awd-store-shot-{index}".encode()).hexdigest()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--end", default="android", choices=sorted(DEVICE))
    args = ap.parse_args()

    model, os_version, app_version = DEVICE[args.end]

    out: pathlib.Path = args.out
    if out.exists():
        shutil.rmtree(out)
    media = out / "FieldEvidence" / "media"
    manifests = out / "FieldEvidence" / "manifest"
    media.mkdir(parents=True)
    manifests.mkdir(parents=True)

    for index, (scene, kind, state, clock, progress) in enumerate(ITEMS):
        src = args.scenes / f"{scene:02d}.jpg"
        if not src.exists():
            print(f"缺现场照片 {src}", file=sys.stderr)
            return 1
        mid = stable_id(index)
        dst = media / f"{mid}.{EXT[kind]}"
        if kind == "photo":
            # 缩到 720 宽再灌：原图 1792×2400 一张 1.5 MB，16 件推进模拟器要好几十秒，
            # 而屏幕本身才 1080 宽，缩完看不出差别
            run(["magick", str(src), "-resize", "720x960", "-quality", "78", str(dst)])
        elif kind == "video":
            # 缩略图走 Coil / 图集的视频首帧解码，所以得是真能解的 mp4
            run(["ffmpeg", "-y", "-loop", "1", "-i", str(src), "-t", "3", "-r", "12",
                 "-vf", "scale=720:-2", "-pix_fmt", "yuv420p", "-c:v", "libx264", str(dst)])
        else:
            run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                 "-t", "8", "-c:a", "aac", str(dst)])

        captured = f"{DAY}T{clock}{TZ}"
        row = {
            "kind": kind,
            "state": state,
            "progress": progress,
            "manifest": {
                "clientMediaId": mid,
                "sha256": hashlib.sha256(dst.read_bytes()).hexdigest(),
                "capturedAt": captured,
                "latitude": 31.23041,
                "longitude": 121.4737,
                "horizontalAccuracy": 5.0,
                "deviceModel": model,
                "osVersion": os_version,
                "appVersion": app_version,
                "fromCamera": True,
            },
            "savedToAlbum": False,
            "project": MAIN,
        }
        if state == "arrived":
            row["manifest"]["serverReceivedAt"] = f"{DAY}T{clock}{TZ}"
        (manifests / f"{mid}.json").write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding="utf-8")

    # SharedPreferences「prefs」：当前项目 + 存相册关（截图里那一栏是关着的）
    project_json = escape(json.dumps(MAIN, ensure_ascii=False, separators=(",", ":")), quote=True)
    (out / "prefs.xml").write_text(
        "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
        "<map>\n"
        f'    <string name="selectedProject">{project_json}</string>\n'
        '    <boolean name="saveToAlbum" value="false" />\n'
        '    <string name="deviceId">dev-shots-emulator</string>\n'
        "</map>\n",
        encoding="utf-8",
    )
    # 第 8 屏（选项目页）用的那份：同样的偏好，但没有当前项目
    (out / "prefs-no-project.xml").write_text(
        "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
        "<map>\n"
        '    <boolean name="saveToAlbum" value="false" />\n'
        '    <string name="deviceId">dev-shots-emulator</string>\n'
        "</map>\n",
        encoding="utf-8",
    )

    print(f"种子已生成：{out}（{len(ITEMS)} 件）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
