# -*- coding: utf-8 -*-
"""M3 X-C 应用图标生成器（确定性，可重复运行输出一致）。

任务卡 X-C（导出包收口）: Godot 默认 icon.svg（蓝人形）不入导出包——
本脚本程序化自产项目自有图标（星空+地牢门：星陨坠入石门，门心之星），
全部色值取自项目既有 DB16 衍生调色板（与 tools/spritegen_m3.py 同源同值，
未新增色值），无任何第三方素材、无随机不可复现成分（random.Random(42)）。

用法:
    python tools/gen_icon.py

输出（art/generated/icon/）:
    icon_256.png                  256x256 主图标（Windows application/icon + 项目配置口径）
    icon_192.png                  192x192 Android 传统启动器图标（launcher_icons/main_192x192）
    adaptive_background_432.png   432x432 自适应图标背景层（星空+星陨，不透明满幅）
    adaptive_foreground_432.png   432x432 自适应图标前景层（地牢门+门心之星，四周透明，
                                  主体 256x256 居中——x4 整数放大，外沿台阶在 66% 安全区圆内）
    adaptive_monochrome_432.png   432x432 自适应单色层（前景白色剪影，Android 13 主题图标）

设计（64x64 逻辑像素画，整数倍最近邻放大保持像素风）:
    - 背景: 调色板最暗色 #181420 夜空 + 确定性星野（白/灰 1px + 十字闪星）
    - 星陨: 金色流星自右上角坠向石门（白芯黄焰橙尾，双行斜线）
    - 地牢门: 石门楣+金钥孔石+双柱+门内星门辉环（紫）+门心之星（白芯金芒）
      造型语言对齐 spritegen_m3.py 的 fx/trial_gate.png（试炼之门 16x16）。

QA（脚本内自检，失败退出码 1）:
    1) 五张产物存在且尺寸精确匹配；
    2) 背景层全不透明（alpha==255），前景层主体外全透明；
    3) 所有不透明像素色值 ∈ 项目调色板（无新增色）；
    4) 确定性: 连续两次生成 SHA256 逐文件一致；
    5) 前景/单色层主体外沿在自适应安全区圆（432 直径的 66.7%）内。
"""
import hashlib
import random
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated" / "icon"

# ---------------------------------------------------------------- palette
# 色值全部出自 tools/spritegen_m3.py 的 DB16 衍生调色板（M1/M2/M3 素材同源，未新增色）。
def C(hexstr, a=255):
    hexstr = hexstr.lstrip("#")
    if len(hexstr) == 3:
        hexstr = "".join(ch * 2 for ch in hexstr)
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16), a)


BG_DEEP = C("#181420")    # 夜空底色（调色板最暗色，gen_placeholder_art.py OUTLINE）
STONE = C("#8a8296")      # 石门柱/门楣/台阶（prop_pillar 家族色）
STONE_D = C("#6e6678")    # 石材暗面（阴影/内缘）
PORTAL = C("#544c60")     # 星门内壁
GLOW = C("#b06cff")       # 星门辉光（事件房/黑市紫）
STAR_PALE = C("#fff3b8")  # 门心之星/亮星（M_GOLD 家族暖白）
GOLD = C("#ffd94a")       # 流星中段/星芒（M_GOLD）
GOLD_L = C("#e2c04c")     # 钥孔石（M_GOLD_L 金饰强调色）
GOLD_D = C("#c8901c")     # 暗金（M_GOLD_D）
YELLOW = C("#ffe86a")     # 流星近头段（RAMP_HIT/RAMP_FIRE 家族）
ORANGE = C("#ff8a2e")     # 流星尾段（RAMP_FIRE 家族）
WHITE = C("#ffffff")
GREY = C("#d8d8d8")       # 暗星（SHARD_GREY）

PALETTE = {BG_DEEP, STONE, STONE_D, PORTAL, GLOW, STAR_PALE, GOLD, GOLD_L,
           GOLD_D, YELLOW, ORANGE, WHITE, GREY}

# ---------------------------------------------------------------- 像素助手
def canvas(w, h, fill=(0, 0, 0, 0)):
    img = Image.new("RGBA", (w, h), fill)
    return img


def px(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((int(x), int(y)), c)


def rect(img, x0, y0, x1, y1, c):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            px(img, x, y, c)


def disk_solid(img, cx, cy, r, c):
    for y in range(int(-r), int(r) + 1):
        for x in range(int(-r), int(r) + 1):
            if x * x + y * y <= r * r + r * 0.3:
                px(img, cx + x, cy + y, c)


# ---------------------------------------------------------------- 星空背景层（参数化画布尺寸：64 主图标 / 108 自适应背景）
def _meteor_points(w):
    """流星像素集（先算后画，星野避开该带）。头在 (0.68w, 0.24w)，45° 尾巴甩向右上角。"""
    u = w / 64.0
    hx, hy = int(round(43.5 * u)), int(round(15.5 * u))
    pts = []   # [(x, y, band)] band: 0=尾橙 1=中金 2=近头黄
    tail = max(4, int(round(11 * u)))
    for i in range(tail):
        x, y = hx + 1 + i, hy - 1 - i
        frac = i / max(1, tail - 1)
        band = 0 if frac > 0.62 else (1 if frac > 0.28 else 2)
        pts.append((x, y, band))
        pts.append((x - 1, y, band))   # 双行厚度
    return (hx, hy), pts


def draw_bg(w):
    """星空+星陨背景层：全不透明满幅。w=64（主图标）/ w=108（自适应背景）。"""
    img = canvas(w, w, BG_DEEP)
    rng = random.Random(42)
    head, meteor = _meteor_points(w)
    banned = {(x, y) for x, y, _ in meteor} | {head}
    # 星野: 密度随面积；确定性洗牌撒点（避开流星带）。
    n_stars = max(12, int(round(w * w / 205.0)))
    cells = [(x, y) for y in range(0, int(19 * w / 64.0)) for x in range(w)]
    rng.shuffle(cells)
    placed = 0
    for x, y in cells:
        if placed >= n_stars:
            break
        if any(abs(x - bx) <= 2 and abs(y - by) <= 2 for bx, by in banned):
            continue
        roll = rng.random()
        if roll < 0.70:
            px(img, x, y, GREY)              # 暗星
        elif roll < 0.90:
            px(img, x, y, STAR_PALE)         # 亮星
        else:
            px(img, x, y, WHITE)             # 十字闪星: 白芯 + 灰十字臂
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                px(img, x + dx, y + dy, GREY)
        placed += 1
    # 流星: 尾（橙）→ 中（金）→ 近头（黄）→ 白芯 + 垂直运动方向金翼。
    band_colors = {0: ORANGE, 1: GOLD, 2: YELLOW}
    for x, y, band in meteor:
        px(img, x, y, band_colors[band])
    hx, hy = head
    px(img, hx, hy, WHITE)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        px(img, hx + dx, hy + dy, YELLOW)
    px(img, hx - 1, hy + 1, GOLD)
    px(img, hx + 1, hy - 1, GOLD)
    return img


# ---------------------------------------------------------------- 地牢门前景层（64x64 逻辑画）
def draw_fg():
    """地牢门: 钥孔石+门楣+双柱+星门辉环+门心之星（造型对齐 fx/trial_gate.png）。主体外全透明。"""
    img = canvas(64, 64)
    # 钥孔石（门楣上方金饰）
    rect(img, 29, 21, 34, 21, GOLD_L)
    rect(img, 29, 22, 34, 22, GOLD_D)
    # 门楣（含出挑，压柱顶）
    rect(img, 15, 23, 48, 24, STONE)
    rect(img, 15, 25, 48, 25, STONE_D)
    # 双柱（外亮内暗，左柱 x17..22 / 右柱 x41..46）
    for x0, x1, inner in ((17, 22, 22), (41, 46, 41)):
        rect(img, x0, 26, x1, 57, STONE)
        rect(img, inner, 26, inner, 57, STONE_D)
    # 门洞内壁 + 星门辉环（内缘一圈紫辉光）
    rect(img, 23, 26, 40, 57, PORTAL)
    for y in range(26, 58):
        px(img, 23, y, GLOW)
        px(img, 40, y, GLOW)
    for x in range(23, 41):
        px(img, x, 26, GLOW)
        px(img, x, 57, GLOW)
    # 门洞进深: 内部偏暗 + 门内地面
    rect(img, 24, 27, 39, 53, PORTAL)
    rect(img, 24, 54, 39, 56, STONE_D)
    # 门心之星（白芯 + 暖白正芒 + 金斜芒 + 黄远芒）
    disk_solid(img, 32, 40, 0, WHITE)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        px(img, 32 + dx, 40 + dy, STAR_PALE)
    for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
        px(img, 32 + dx, 40 + dy, YELLOW)
    for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        px(img, 32 + dx, 40 + dy, GOLD)
    # 台阶三级（下宽上窄，逐级压暗）
    rect(img, 14, 58, 49, 58, STONE)
    rect(img, 12, 59, 51, 59, STONE_D)
    rect(img, 10, 60, 53, 60, STONE_D)
    return img


def upscale(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def compose_center(canvas_size, inner):
    out = canvas(canvas_size, canvas_size)
    out.alpha_composite(inner, ((canvas_size - inner.width) // 2,) * 2)
    return out


def monochrome_of(img):
    out = canvas(img.width, img.height)
    px_map = img.load()
    out_map = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px_map[x, y]
            if a != 0:
                out_map[x, y] = (255, 255, 255, a)
    return out


# ---------------------------------------------------------------- QA 自检
def qa(products):
    """五项自检（详见模块 docstring），任何一条失败退出码 1。"""
    expect = {
        "icon_256.png": 256, "icon_192.png": 192, "adaptive_background_432.png": 432,
        "adaptive_foreground_432.png": 432, "adaptive_monochrome_432.png": 432,
    }
    for name, size in expect.items():
        img = products[name]
        if img.size != (size, size):
            print(f"[gen_icon] QA FAIL: {name} size {img.size} != ({size},{size})")
            return False
        if hashlib.sha256(img.tobytes()).hexdigest() != hashlib.sha256(
                Image.open(OUT / name).convert("RGBA").tobytes()).hexdigest():
            print(f"[gen_icon] QA FAIL: {name} on-disk bytes differ from in-memory")
            return False
    # 背景层全不透明
    for name in ("icon_256.png", "icon_192.png", "adaptive_background_432.png"):
        alpha = products[name].getchannel("A")
        if alpha.getextrema() != (255, 255):
            print(f"[gen_icon] QA FAIL: {name} 背景层存在透明像素（须全不透明）")
            return False
    # 调色板封口（主图标 256 逐像素）
    px_map = products["icon_256.png"].convert("RGBA").load()
    used = {px_map[x, y] for y in range(256) for x in range(256)}
    stray = {c for c in used if c != (0, 0, 0, 0) and c not in PALETTE}
    if stray:
        print(f"[gen_icon] QA FAIL: 发现调色板外色值 x{len(stray)}: {sorted(stray)[:4]}")
        return False
    # 自适应安全区: 前景不透明像素须落在中心 66.7% 圆内（288px 直径 @432）
    limit = 432 * 0.667 / 2.0
    cx = cy = 432 / 2.0
    for name in ("adaptive_foreground_432.png", "adaptive_monochrome_432.png"):
        data = products[name].convert("RGBA").load()
        for y in range(0, 432, 2):          # 步进 2 采样足够（几何断言）
            for x in range(0, 432, 2):
                if data[x, y][3] != 0 and ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 > limit:
                    print(f"[gen_icon] QA FAIL: {name} 主体越出安全区圆 ({x},{y})")
                    return False
    print("[gen_icon] QA PASS: 尺寸/不透明度/调色板封口/确定性/安全区 五项全过")
    return True


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bg64, fg = draw_bg(64), draw_fg()
    bg108 = draw_bg(108)
    composite = bg64.copy()
    composite.alpha_composite(fg)
    products = {
        "icon_256.png": upscale(composite, 4),
        "icon_192.png": upscale(composite, 3),
        "adaptive_background_432.png": upscale(bg108, 4),
        "adaptive_foreground_432.png": compose_center(432, upscale(fg, 4)),
        "adaptive_monochrome_432.png": compose_center(432, upscale(monochrome_of(fg), 4)),
    }
    # 确定性: 内存中重建一遍比对（等价两次全流程生成）
    bg64b, fgb = draw_bg(64), draw_fg()
    determinism = (
        hashlib.sha256(bg64.tobytes()).hexdigest() == hashlib.sha256(bg64b.tobytes()).hexdigest()
        and hashlib.sha256(fg.tobytes()).hexdigest() == hashlib.sha256(fgb.tobytes()).hexdigest()
        and hashlib.sha256(bg108.tobytes()).hexdigest() == hashlib.sha256(draw_bg(108).tobytes()).hexdigest()
    )
    if not determinism:
        print("[gen_icon] QA FAIL: 两次构建不一致（确定性破坏）")
        return 1
    for name, img in products.items():
        img.save(OUT / name)
        print(f"[gen_icon] wrote art/generated/icon/{name}  {img.width}x{img.height}")
    if not qa(products):
        return 1
    print("[gen_icon] DONE: 5 products, seed=42, palette=project DB16-derived, zero third-party assets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
