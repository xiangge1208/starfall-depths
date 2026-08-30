# -*- coding: utf-8 -*-
"""M3 Juice v2 特效素材生成器（M3-P0-4）：确定性生成 + 三重 QA 自检 + 专属清单。

用法:
    python tools/spritegen_m3.py

交付（全部落盘于 art/generated/fx/，不触碰 M1/M2 既有素材与 MANIFEST.md）:
    spark_hit_strip4.png / spark_crit_strip4.png / spark_fire_strip4.png /
    spark_ice_strip4.png / spark_poison_strip4.png / spark_shock_strip4.png /
    muzzle_v2_strip3.png / kill_shard_strip6.png / trial_gate.png / trial_medal.png
    MANIFEST_M3.md

流程: build_all() 两遍 → PNG 字节 SHA-256 逐文件比对（不一致退出码 2）
→ 三重 QA（对比度/剪影/帧序列，任一不过退出码 3，且**不落盘交付**）
→ 写 PNG + MANIFEST_M3.md → 退出码 0（幂等：重跑产出逐字节一致）。

命名偏差: Juice v2 规格（docs/superpowers/specs/2026-08-30-m3-juice-v2-spec.md §3）
写作 spark_elec_strip4；代码中电元素为 core/combat/elements.gd 的
Elements.Id.SHOCK（NAMES id 串 "shock"），故实际文件名为 spark_shock_strip4.png，
对照说明见 MANIFEST_M3.md。禁止在本脚本之外修改任何文件；不跑 godot（.import
sidecar 由编排者统一生成）。
"""
import hashlib
import io
import math
import random
import statistics
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated" / "fx"
SEED = 42  # 沿用 tools/gen_placeholder_art.py 的确定性随机种子惯例

# ---------------------------------------------------------------- palette
# palette copied from tools/gen_placeholder_art.py (M2-owned; do not edit there)
# —— DB16 衍生 32 色系中本包用到的色值，与 M1/M2 素材同源同值，保证观感统一。
def C(hexstr, a=255):
    hexstr = hexstr.lstrip("#")
    if len(hexstr) == 3:
        hexstr = "".join(ch * 2 for ch in hexstr)
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16), a)


BG = C("#181420")   # gen_placeholder_art.py 的 OUTLINE（调色板最暗色）→ QA 底色近似

# 火花色阶 (core, hi, mid, edge)——由热到冷；取值均出自 M1/M2 素材已用色。
RAMP_HIT = (C("#ffffff"), C("#fff3b8"), C("#ffe86a"), C("#f4f4f0"))   # 白/浅黄: fx_muzzle/fx_puff 家族
RAMP_CRIT = (C("#ffffff"), C("#ffe86a"), C("#ffd94a"), C("#ffb03a"))  # 金色: 更大更亮（暴击）
RAMP_FIRE = (C("#ffffff"), C("#ffe86a"), C("#ff8a2e"), C("#ff4a1e"))  # 红橙: fx_explosion/elem_fire
RAMP_ICE = (C("#ffffff"), C("#e2f4ff"), C("#b8ecff"), C("#8ae8ff"))   # 青白: elem_ice
RAMP_POISON = (C("#ffffff"), C("#d2f4a0"), C("#a8e84a"), C("#6ee86e"))  # 绿: elem_poison
RAMP_SHOCK = (C("#ffffff"), C("#f4ecff"), C("#e0b0ff"), C("#c888ff"))   # 亮紫: elem_shock（锯齿芒）
RAMP_MUZZLE = (C("#ffffff"), C("#fff3b8"), C("#ffe86a"), C("#ff8a2e"))  # 枪口焰: 白芯黄焰橙缘

SHARD_PALE = C("#f4f4f0")
SHARD_GREY = C("#d8d8d8")
SHARD_WHITE = C("#ffffff")
G_STONE = C("#8a8296")    # 石门柱（prop_pillar 家族色）
G_STONE_D = C("#6e6678")
G_PORTAL = C("#544c60")   # 星门内壁
G_GLOW = C("#b06cff")     # 星门辉光（事件房/黑市紫）
G_STAR = C("#fff3b8")     # 门心之星
M_GOLD = C("#ffd94a")     # 徽章金
M_GOLD_D = C("#c8901c")
M_GOLD_L = C("#e2c04c")   # 金饰强调色（ICON_ACC 家族）
M_RIBBON = C("#e83a4a")   # 绶带红（heart/red 家族）
M_STAR = C("#fff3b8")


# ---------------------------------------------------------------- 像素助手（复制自 tools/gen_placeholder_art.py 的公共画法）
def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def px(img, x, y, c, a=255):
    if 0 <= x < img.width and 0 <= y < img.height:
        alpha = a if a != 255 else (c[3] if len(c) > 3 else 255)
        img.putpixel((int(x), int(y)), (c[0], c[1], c[2], alpha))


def rect(img, x0, y0, x1, y1, c, a=255):
    col = (c[0], c[1], c[2], a)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(img, x, y, col)


def hline(img, x0, x1, y, c, a=255):
    col = (c[0], c[1], c[2], a)
    for x in range(x0, x1 + 1):
        px(img, x, y, col)


def disk(img, cx, cy, r, c):
    for y in range(-r, r + 1):
        for x in range(-r, r + 1):
            if x * x + y * y <= r * r + r * 0.3:
                px(img, cx + x, cy + y, c)


ORTH = ((1, 0), (-1, 0), (0, 1), (0, -1))
DIAG = ((1, 1), (1, -1), (-1, 1), (-1, -1))
DIRS8 = ORTH + DIAG


def ray(img, cx, cy, d, r0, r1, c, a=255):
    """直线光芒: 从 r0 到 r1 逐格步进（与核心保持 8-连通）。"""
    col = (c[0], c[1], c[2], a)
    for r in range(r0, r1 + 1):
        px(img, cx + d[0] * r, cy + d[1] * r, col)


WOBBLE = (0, 1, 0, -1)


def zray(img, cx, cy, d, r0, r1, c, a=255):
    """锯齿光芒（电元素专用）: 每 1~2 步沿垂直向抖动 ±1px，步进间保持 8-连通。

    仅用于正交方向（对角方向 + 垂直抖动会产生 (0,±2) 跳步裂缝，故对角芒一律走直线 ray）。
    """
    col = (c[0], c[1], c[2], a)
    perp = (-d[1], d[0])
    for k, r in enumerate(range(r0, r1 + 1)):
        w = WOBBLE[k % 4]
        px(img, cx + d[0] * r + perp[0] * w, cy + d[1] * r + perp[1] * w, col)


def ring_conn(img, cx, cy, r, c, a=255):
    """1px 圆环（按 1° 步进描点，保证 8-连通，避免半径带栅格化裂缝）。"""
    col = (c[0], c[1], c[2], a)
    for deg in range(360):
        rad = math.radians(deg)
        px(img, int(round(cx + r * math.cos(rad))),
           int(round(cy + r * math.sin(rad))), col)


def dir_pos(d, dist):
    """8 方向在欧氏半径 dist 处的落点（斜向按 √2 归一，保证贴住圆环）。"""
    if d[0] == 0 or d[1] == 0:
        return (8 + d[0] * dist, 8 + d[1] * dist)
    return (int(round(8 + d[0] * dist * 0.70710678)),
            int(round(8 + d[1] * dist * 0.70710678)))


def strip(frames):
    """横向帧条带: 每帧 16x16 槽位居中拼接。"""
    img = Image.new("RGBA", (16 * len(frames), 16), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        img.paste(f, (i * 16, 0))
    return img


# ---------------------------------------------------------------- 画师
def spark_frames(rng, ramp, crit=False, zig=False):
    """命中火花 4 帧: 迸射 → 展开 → 消散 → 残星（帧间芒长/核心尺寸单调演进）。

    crit=True 时核心+1、芒更长（更大更亮）；zig=True 时正交芒走锯齿（电元素）。
    """
    core, hi, mid, edge = ramp
    L = 1 if crit else 0
    r_disk = 3 if crit else 2
    frames = []
    for st in range(4):
        img = canvas(16, 16)
        if st == 0:      # 迸射: 紧凑核心 + 短芒
            disk(img, 8, 8, r_disk, mid)
            if crit:
                disk(img, 8, 8, 2, hi)
            px(img, 8, 8, core)
            for d in ORTH:
                (zray if zig else ray)(img, 8, 8, d, r_disk + 1, r_disk + 2 + L, hi)
            for d in DIAG:
                ray(img, 8, 8, d, r_disk, r_disk + 1 + L, mid)
        elif st == 1:    # 展开: 芒伸长、尖端增亮
            disk(img, 8, 8, r_disk, mid)
            px(img, 8, 8, core)
            tip = min(r_disk + 4 + L, 7)
            for d in ORTH:
                (zray if zig else ray)(img, 8, 8, d, r_disk + 1, tip - 1, mid)
                px(img, 8 + d[0] * tip, 8 + d[1] * tip,
                   core if rng.random() < 0.2 else hi)
            for d in DIAG:
                ray(img, 8, 8, d, r_disk, r_disk + 1 + L, edge)
        elif st == 2:    # 消散: 芒变细后退、透明度回落
            disk(img, 8, 8, 1, mid)
            px(img, 8, 8, core)
            for d in ORTH:
                (zray if zig else ray)(img, 8, 8, d, 2, 5 + L, edge, 230)
            for d in DIAG:
                ray(img, 8, 8, d, 1, 3 + L, mid, 230)
        else:            # 残星: 余烬菱点渐隐
            px(img, 8, 8, core, 210)
            for d in ORTH:
                px(img, 8 + d[0], 8 + d[1], hi, 200)
            for d in DIAG:
                px(img, 8 + d[0], 8 + d[1], edge, 170)
        frames.append(img)
    return frames


def muzzle_frames():
    """枪口焰 3 帧: 绽放 → 峰值 → 消散（水平为主，朝右 0°，运行时可旋转/tint）。"""
    core, hi, mid, edge = RAMP_MUZZLE
    out = []
    # f0 绽放
    img = canvas(16, 16)
    disk(img, 8, 8, 1, hi)
    px(img, 8, 8, core)
    for d in ((1, 0), (-1, 0)):
        ray(img, 8, 8, d, 2, 3, mid)
    for d in ((0, 1), (0, -1)):
        ray(img, 8, 8, d, 2, 2, mid)
    for d in DIAG:
        px(img, 8 + d[0], 8 + d[1], mid, 220)
    out.append(img)
    # f1 峰值: 长芒全开
    img = canvas(16, 16)
    disk(img, 8, 8, 2, hi)
    px(img, 8, 8, core)
    for d in ((1, 0), (-1, 0)):
        ray(img, 8, 8, d, 3, 6, mid)
        px(img, 8 + d[0] * 7, 8, edge)
    for d in ((0, 1), (0, -1)):
        ray(img, 8, 8, d, 3, 4, mid)
        px(img, 8, 8 + d[1] * 5, edge)
    for d in DIAG:
        ray(img, 8, 8, d, 2, 4, mid)
    out.append(img)
    # f2 消散: 芒变细、整体回落
    img = canvas(16, 16)
    px(img, 8, 8, hi, 210)
    for d in ((1, 0), (-1, 0)):
        ray(img, 8, 8, d, 1, 5, mid, 190)
        px(img, 8 + d[0] * 6, 8, edge, 160)
    for d in ((0, 1), (0, -1)):
        ray(img, 8, 8, d, 1, 2, mid, 180)
    for d in DIAG:
        px(img, 8 + d[0], 8 + d[1], mid, 170)
    out.append(img)
    return out


def kill_shard_frames():
    """击杀碎片环 6 帧: 白闪核心 → 碎片随扩张环外抛 → 环与碎片同步渐隐。

    半径 3→6 单调扩张；碎片 2x2 → 1x2 → 1px 递减；后两帧靠 alpha 回落表现渐隐。
    环按 1° 步进保证连通，碎片落点经 dir_pos 贴环（整帧单一连通域）。
    """
    ring_a = (235, 220, 205, 190, 175, 160)
    shard_a = (255, 255, 230, 210, 180, 150)
    frames = []
    for i in range(6):
        img = canvas(16, 16)
        r = 3 + min(i, 3)
        ring_conn(img, 8, 8, r, SHARD_GREY, ring_a[i])
        if i == 0:
            disk(img, 8, 8, 2, SHARD_WHITE)
        elif i == 1:
            px(img, 8, 8, SHARD_WHITE, 220)
        for d in DIRS8:
            x, y = dir_pos(d, r + 1)
            if i == 0:
                rect(img, x, y, x + 1, y + 1, SHARD_PALE)
            elif i == 1:
                rect(img, x, y, x + 1, y, SHARD_PALE)
            else:
                px(img, x, y, SHARD_PALE if i < 4 else SHARD_GREY, shard_a[i])
        frames.append(img)
    return frames


def trial_gate():
    """试炼之门 16x16: 石门框 + 星门辉环 + 门心之星（主菜单试炼入口图标）。"""
    img = canvas(16, 16)
    rect(img, 3, 2, 4, 12, G_STONE)            # 左柱
    rect(img, 11, 2, 12, 12, G_STONE)          # 右柱
    hline(img, 3, 12, 2, G_STONE)              # 顶梁
    hline(img, 3, 12, 3, G_STONE_D)
    rect(img, 5, 4, 10, 11, G_PORTAL)          # 门内空间
    for x in range(5, 11):                     # 星门辉环（门框内缘）
        px(img, x, 4, G_GLOW)
        px(img, x, 11, G_GLOW)
    for y in range(4, 12):
        px(img, 5, y, G_GLOW)
        px(img, 10, y, G_GLOW)
    px(img, 8, 7, G_STAR)                      # 门心之星（菱形）
    px(img, 7, 7, G_GLOW)
    px(img, 9, 7, G_GLOW)
    px(img, 8, 6, G_GLOW)
    px(img, 8, 8, G_GLOW)
    hline(img, 4, 11, 13, G_STONE_D)           # 台阶
    hline(img, 3, 12, 14, G_STONE)
    return img


def trial_medal():
    """试炼徽章 12x12: 金盘 + 星芒 + 绶带（结算/排行榜徽标）。"""
    img = canvas(12, 12)
    disk(img, 6, 6, 4, M_GOLD_D)               # 暗金外缘
    disk(img, 6, 6, 3, M_GOLD)                 # 亮金盘面
    px(img, 6, 6, M_STAR)                      # 星芯
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        px(img, 6 + dx, 6 + dy, M_GOLD_L)      # 星芒
    px(img, 4, 4, M_STAR)                      # 高光
    rect(img, 4, 0, 5, 2, M_RIBBON)            # 绶带（压过盘顶）
    rect(img, 6, 0, 7, 2, M_RIBBON)
    return img


def build_all():
    """确定性构建全部素材（每次调用独立 rng，种子固定 42）。"""
    rng = random.Random(SEED)
    imgs = {}
    imgs["spark_hit_strip4.png"] = strip(spark_frames(rng, RAMP_HIT))
    imgs["spark_crit_strip4.png"] = strip(spark_frames(rng, RAMP_CRIT, crit=True))
    imgs["spark_fire_strip4.png"] = strip(spark_frames(rng, RAMP_FIRE))
    imgs["spark_ice_strip4.png"] = strip(spark_frames(rng, RAMP_ICE))
    imgs["spark_poison_strip4.png"] = strip(spark_frames(rng, RAMP_POISON))
    imgs["spark_shock_strip4.png"] = strip(spark_frames(rng, RAMP_SHOCK, zig=True))
    imgs["muzzle_v2_strip3.png"] = strip(muzzle_frames())
    imgs["kill_shard_strip6.png"] = strip(kill_shard_frames())
    imgs["trial_gate.png"] = trial_gate()
    imgs["trial_medal.png"] = trial_medal()
    return imgs


# ---------------------------------------------------------------- QA（三重）
# 对比度: 前景(a>0)平均亮度(0~100) − 底色亮度(0~100) ≥ 30（底色取调色板最暗色 #181420）
# 剪影:   亮度压至 30% 后阈值重建 mask 与可见 mask 的 IoU ≥ 0.85；主连通域(8-conn)占比 ≥ 0.85
# 帧序列: 尺寸/帧数正确、每帧非空、单帧颜色数(RGB 种类) ≤ 6
CONTRAST_MIN = 30.0
IOU_MIN = 0.85
SHARE_MIN = 0.85
COLOR_MAX = 6
DIM_FACTOR = 0.3      # 剪影检查: 亮度压至 30%
THR_FRAC = 0.25       # 重建阈值: 底色→前景中位亮度距离的 25%（保证渐隐像素不误删）
VIS_DELTA = 8.0       # 可见像素: 合成到底色后亮度差 ≥8/255（≈贴底色的描边不计入剪影）


def _lum255(rgb):
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]


BG_LUM = _lum255(BG[:3])            # ≈22.6 / 255
BG_LUM100 = BG_LUM / 255.0 * 100.0  # ≈8.9 / 100


def _components(pxset):
    """8-连通域划分（确定性遍历）。"""
    seen = set()
    comps = []
    for p in sorted(pxset):
        if p in seen:
            continue
        seen.add(p)
        stack = [p]
        comp = [p]
        while stack:
            x, y = stack.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    q = (x + dx, y + dy)
                    if q in pxset and q not in seen:
                        seen.add(q)
                        stack.append(q)
                        comp.append(q)
        comps.append(comp)
    return comps


def qa_frame(img):
    w, h = img.size
    im = img.load()
    fg = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = im[x, y]
            if a > 0:
                fg[(x, y)] = (r, g, b, a)
    nonempty = bool(fg)
    ncolors = len({(r, g, b) for (r, g, b, _a) in fg.values()})
    contrast = (sum((_lum255(rgb[:3]) / 255.0 * 100.0 for rgb in fg.values())) / len(fg)
                - BG_LUM100) if fg else 0.0
    # 可见像素: 合成到底色后与底色亮度差足够（贴底色的像素不参与剪影判定）
    comp = {p: rgb[3] / 255.0 * _lum255(rgb[:3]) + (1 - rgb[3] / 255.0) * BG_LUM
            for p, rgb in fg.items()}
    vis = {p for p, cl in comp.items() if cl - BG_LUM >= VIS_DELTA}
    comps = _components(vis)
    share = (max(len(c) for c in comps) / len(vis)) if vis else 0.0
    # 剪影: 压暗至 30% 后按阈值重建 mask，与可见 mask 求 IoU
    bg_dim = BG_LUM * DIM_FACTOR
    med = statistics.median(sorted(comp[p] * DIM_FACTOR for p in vis)) if vis else 0.0
    thr = bg_dim + max(1.0, (med - bg_dim) * THR_FRAC)
    mask2 = {p for p in vis if comp[p] * DIM_FACTOR >= thr}
    union = vis | mask2
    iou = (len(vis & mask2) / len(union)) if union else 1.0
    # 周长/紧凑度（报告值）: 周长 = 有 4-邻域落在可见域外的像素数
    per = sum(1 for (x, y) in vis
              if any((x + dx, y + dy) not in vis
                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))))
    area = len(vis)
    compact = (4.0 * math.pi * area / (per * per)) if per else 0.0
    return {
        "nonempty": nonempty, "ncolors": ncolors, "contrast": contrast,
        "iou": iou, "share": share, "comps": len(comps),
        "area": area, "perimeter": per, "compact": compact,
    }


def qa_sprite(img, exp_w, exp_h, exp_frames):
    """单素材 QA: 返回 (逐帧结果列表, 失败项列表)。"""
    fails = []
    w, h = img.size
    if (w, h) != (exp_w, exp_h):
        fails.append(f"尺寸 {(w, h)} != ({exp_w}, {exp_h})")
    if h == 16 and w % 16 == 0:
        frames = [img.crop((i * 16, 0, (i + 1) * 16, 16)) for i in range(w // 16)]
    else:
        frames = [img]
    if len(frames) != exp_frames:
        fails.append(f"帧数 {len(frames)} != {exp_frames}")
    per_frame = []
    for i, f in enumerate(frames):
        q = qa_frame(f)
        per_frame.append(q)
        tag = f"f{i}"
        if not q["nonempty"]:
            fails.append(f"{tag} 空帧")
        if q["ncolors"] > COLOR_MAX:
            fails.append(f"{tag} 颜色数 {q['ncolors']} > {COLOR_MAX}")
        if q["contrast"] < CONTRAST_MIN:
            fails.append(f"{tag} 对比度 {q['contrast']:.1f} < {CONTRAST_MIN}")
        if q["iou"] < IOU_MIN:
            fails.append(f"{tag} 剪影 IoU {q['iou']:.3f} < {IOU_MIN}")
        if q["share"] < SHARE_MIN:
            fails.append(f"{tag} 主连通域占比 {q['share']:.3f} < {SHARE_MIN}")
    return per_frame, fails


# ---------------------------------------------------------------- 交付描述
USAGE = {
    "spark_hit_strip4.png": "Juice v2 **J3 命中表现 v2**: 通用命中火花（白/浅黄），替代 v1 色块粒子；暴击/元素命中换专用条带",
    "spark_crit_strip4.png": "J3: 暴击火花（金色，更大更亮，运行时 1.3× 缩放）",
    "spark_fire_strip4.png": "J3: 火元素命中火花（红橙，对齐 fx.gd ELEMENT_COLORS[FIRE]）",
    "spark_ice_strip4.png": "J3: 冰元素命中火花（青白，对齐 ELEMENT_COLORS[ICE]）",
    "spark_poison_strip4.png": "J3: 毒元素命中火花（绿，对齐 ELEMENT_COLORS[POISON]）",
    "spark_shock_strip4.png": "J3: 电元素命中火花（亮紫锯齿芒，对齐 ELEMENT_COLORS[SHOCK]；规格名 elec→代码名 shock）",
    "muzzle_v2_strip3.png": "J3: 枪口焰 3 帧（绽放-峰值-消散；朝右 0°，运行时按武器类别 tint）",
    "kill_shard_strip6.png": "J3 击杀爆散 + **J7 Boss 死亡演出链**: 6 帧碎片环（扩散渐隐）",
    "trial_gate.png": "M3-P0-4 补件（试炼 UI）: 试炼模式入口图标（主菜单，R-B trial_panel/入口按钮）",
    "trial_medal.png": "M3-P0-4 补件（试炼 UI）: 试炼徽章（结算/排行榜徽标，R-B trial_records）",
}
PARAMS = {
    "spark_hit_strip4.png": "spark_frames(RAMP_HIT) 白/浅黄色阶",
    "spark_crit_strip4.png": "spark_frames(RAMP_CRIT, crit=True) 金色阶（核心+1/芒+1）",
    "spark_fire_strip4.png": "spark_frames(RAMP_FIRE) 红橙色阶",
    "spark_ice_strip4.png": "spark_frames(RAMP_ICE) 青白色阶",
    "spark_poison_strip4.png": "spark_frames(RAMP_POISON) 绿色阶",
    "spark_shock_strip4.png": "spark_frames(RAMP_SHOCK, zig=True) 亮紫色阶 + 锯齿正交芒",
    "muzzle_v2_strip3.png": "muzzle_frames() 白芯黄焰橙缘，水平长芒",
    "kill_shard_strip6.png": "kill_shard_frames() 环半径 3→6、碎片 2x2→1px、alpha 235→160",
    "trial_gate.png": "trial_gate() 石门框+星门辉环+门心之星",
    "trial_medal.png": "trial_medal() 金盘+星芒+绶带",
}
EXPECT = {
    "spark_hit_strip4.png": (64, 16, 4),
    "spark_crit_strip4.png": (64, 16, 4),
    "spark_fire_strip4.png": (64, 16, 4),
    "spark_ice_strip4.png": (64, 16, 4),
    "spark_poison_strip4.png": (64, 16, 4),
    "spark_shock_strip4.png": (64, 16, 4),
    "muzzle_v2_strip3.png": (48, 16, 3),
    "kill_shard_strip6.png": (96, 16, 6),
    "trial_gate.png": (16, 16, 1),
    "trial_medal.png": (12, 12, 1),
}
ORDER = list(EXPECT.keys())


# ---------------------------------------------------------------- 清单
def write_manifest(results, hashes):
    lines = [
        "# M3 特效素材清单（art/generated/fx · Juice v2 素材包）",
        "",
        "> 本清单由 `tools/spritegen_m3.py` 自动生成并维护（任务卡 **M3-P0-4**）。",
        "> **所有权**: 本文件与本包 10 个 PNG 归 M3 所有；`art/generated/MANIFEST.md` 及该目录",
        "> 既有 12 个 fx PNG（fx_muzzle/fx_explosion/fx_puff 等）归 M1/M2 所有——互不写入、互不覆盖。",
        "> **接线**: ArtLookup 注册 + 池化消费在 M3 执行卡 **J-C** 落地；届时向",
        "> `tests/unit/test_art_lookup.gd` 追加存在性断言（沿用 M2-T28 模式）。",
        "> **导入**: .import sidecar 由编排者统一生成（本任务禁跑 godot）；像素材质需 nearest 过滤。",
        "> **确定性**: seed=42，同参数重跑逐字节一致；脚本内置两遍构建 + SHA-256 自证（不一致退出码非 0）。",
        "> **QA 口径**（三重，程序化判定，全过才交付）:",
        "> 1. 对比度 = 前景（alpha>0）平均亮度(0~100) − 底色亮度（调色板最暗色 #181420 ≈ 8.9），阈值 ≥30；",
        "> 2. 剪影 = 亮度压至 30% 后按阈值（底色→前景中位亮度距离的 25%）重建 mask 与可见 mask 的 IoU ≥0.85，",
        ">    且主连通域（8-conn）占比 ≥0.85；周长/紧凑度为报告值；",
        "> 3. 帧序列 = 条带尺寸与帧数正确、每帧非空、单帧颜色数（RGB 种类）≤6。",
        "",
        "## 规格偏差对照（元素命名以代码为准）",
        "",
        "| Juice v2 规格 §3 | 实际交付 | 依据 |",
        "|---|---|---|",
        ("| `spark_elec_strip4` | `fx/spark_shock_strip4.png` | "
         "`core/combat/elements.gd` `enum Id {NONE, FIRE, ICE, POISON, SHOCK}`（NAMES id 串 \"shock\"）；"
         "`autoload/fx.gd` `ELEMENT_COLORS[SHOCK]`；M1 既有 `projectiles/elem_shock.png` 同名 |"),
        "",
        "其余 9 个文件名与规格一致。",
        "",
        "## QA 总表（最差帧口径）",
        "",
        "| 文件 | 尺寸 | 帧数 | 对比度↓(≥30) | 剪影 IoU↓(≥0.85) | 主连通域占比↓(≥0.85) | 单帧颜色数↑(≤6) | sha256-16 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for name in ORDER:
        per = results[name]
        w, h, n = EXPECT[name]
        lines.append(
            f"| `{name}` | {w}x{h} | {n} | {min(q['contrast'] for q in per):.1f} "
            f"| {min(q['iou'] for q in per):.3f} | {min(q['share'] for q in per):.3f} "
            f"| {max(q['ncolors'] for q in per)} | {hashes[name][:16]} |")
    lines += [
        "",
        "## 各文件明细",
        "",
    ]
    for name in ORDER:
        per = results[name]
        w, h, n = EXPECT[name]
        lines.append(f"### `fx/{name}`（{w}x{h} · {n} 帧）")
        lines.append(f"- 用途: {USAGE[name]}。")
        if n > 1:
            lines.append("- 帧演进: " + {
                "spark_hit_strip4.png": "迸射（紧凑核心+短芒）→ 展开（芒伸长、尖端增亮）→ 消散（芒变细后退）→ 残星（余烬菱点）",
                "spark_crit_strip4.png": "同通用火花，核心+1/芒+1（更大更亮）",
                "spark_fire_strip4.png": "同通用火花几何，红橙色阶",
                "spark_ice_strip4.png": "同通用火花几何，青白色阶",
                "spark_poison_strip4.png": "同通用火花几何，绿色阶",
                "spark_shock_strip4.png": "同通用火花几何，正交芒为锯齿折线（zray）",
                "muzzle_v2_strip3.png": "绽放（小十字星）→ 峰值（长芒全开）→ 消散（芒细、alpha 回落）",
                "kill_shard_strip6.png": "白闪核心 → 环 r3→6 扩张、碎片 2x2→1px 外抛 → 环与碎片同步渐隐（alpha 235→160）",
            }[name] + "。")
        else:
            lines.append("- 单帧静态图标。")
        frame_txt = " | ".join(
            f"f{i} 对比度 {q['contrast']:.1f} · IoU {q['iou']:.3f} · "
            f"主连通域 {q['share']:.3f}（{q['comps']} 域）· 颜色 {q['ncolors']} · "
            f"周长 {q['perimeter']}px/面积 {q['area']}px（紧凑度 {q['compact']:.2f}）"
            for i, q in enumerate(per))
        lines.append(f"- QA（逐帧）: {frame_txt}")
        lines.append(f"- 生成参数: seed {SEED} · {PARAMS[name]}。")
        lines.append("")
    lines += [
        "## 消费对照（Juice v2 规格 §2/§3 → M3 执行卡 J-C）",
        "",
        "| 素材 | 规格依赖项 | 运行时消费点（J-C 落地） |",
        "|---|---|---|",
        "| `spark_{hit,crit,fire,ice,poison,shock}_strip4` | J3 命中火花 4 帧条带（暴击 1.3× 缩放） | fx 粒子池 AnimatedSprite2D，按命中类型选条带 |",
        "| `muzzle_v2_strip3` | J3 枪口焰 3 帧（按武器类别 tint） | weapon_rig 枪口挂点（muzzle=8px 处） |",
        "| `kill_shard_strip6` | J3 击杀爆散 / J7 Boss 死亡演出链（0.3× 慢速段复用） | fx 粒子池 |",
        "| `trial_gate` / `trial_medal` | 试炼 UI（M3-P0-4 任务卡补件，非 Juice §3 项） | R-B trial_panel / trial_records 排行榜 |",
        "",
        "## 预算与降级（对齐规格红线）",
        "",
        "- 全部条带为 16px 槽位横向帧序列，单帧 ≤6 色、像素数 ≤256，适合池化零分配消费；",
        "- 超预算降级路径（规格 §2 J3）: 关帧动画退化为单帧贴图——每条带首帧可独立作为降级帧使用。",
        "",
        f"（本清单由脚本自动写出，重跑 `python tools/spritegen_m3.py` 即再生；生成时间不写入以保持逐字节幂等。）",
    ]
    (OUT / "MANIFEST_M3.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------- 主流程
def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print(f"== M3-P0-4 spritegen == seed={SEED} out={OUT.relative_to(ROOT)}")

    # 1) 确定性自证: 独立构建两遍，逐文件比对 PNG 字节哈希
    imgs = build_all()                       # 第 1 遍（QA 与落盘均用它）
    b1 = {k: png_bytes(v) for k, v in imgs.items()}
    b2 = {k: png_bytes(v) for k, v in build_all().items()}  # 第 2 遍（仅比对）
    h1 = {k: hashlib.sha256(v).hexdigest() for k, v in b1.items()}
    h2 = {k: hashlib.sha256(v).hexdigest() for k, v in b2.items()}
    det_ok = h1 == h2
    for name in ORDER:
        mark = "OK" if h1[name] == h2[name] else "MISMATCH"
        print(f"  [det {mark}] {name}  sha256:{h1[name][:16]}")
    if not det_ok:
        print("FAIL: 两遍构建哈希不一致，确定性自证未通过。")
        return 2

    # 2) 三重 QA（内存产物上执行；不过则不落盘交付）
    results = {}
    all_fails = []
    for name in ORDER:
        w, h, n = EXPECT[name]
        per, fails = qa_sprite(imgs[name], w, h, n)
        results[name] = per
        all_fails += [f"{name}: {m}" for m in fails]
    if all_fails:
        print("FAIL: QA 未通过（不交付）:")
        for m in all_fails:
            print(f"  - {m}")
        return 3

    # 3) 落盘 + 复核（写入字节 == 内存字节，保证 QA 结论适用于磁盘文件）
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ORDER:
        p = OUT / name
        p.write_bytes(b1[name])
        if p.read_bytes() != b1[name]:
            print(f"FAIL: {name} 写盘复核不一致。")
            return 4
    write_manifest(results, h1)

    # 4) 汇总输出
    print("-- QA（最差帧口径: 对比度≥30 / IoU≥0.85 / 主连通域≥0.85 / 颜色≤6）--")
    for name in ORDER:
        per = results[name]
        w, h, n = EXPECT[name]
        print(f"  [qa PASS] {name}  {w}x{h} f{n}  contrast>={min(q['contrast'] for q in per):.1f}"
              f"  iou>={min(q['iou'] for q in per):.3f}"
              f"  share>={min(q['share'] for q in per):.3f}"
              f"  colors<={max(q['ncolors'] for q in per)}")
    print(f"OK: 交付 {len(ORDER)} 个 PNG + MANIFEST_M3.md（幂等，可重跑）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
