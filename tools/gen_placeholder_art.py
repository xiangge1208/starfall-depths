# -*- coding: utf-8 -*-
"""占位像素素材生成器（可重复运行，输出确定性一致）。

用法:
    python tools/gen_placeholder_art.py                # 全量再生（先生成后清理陈旧，失败不毁库）
    python tools/gen_placeholder_art.py --hero-sheets  # m2-t17 定点：仅英雄行走帧表+MANIFEST 行

说明: 全量入口自 m2-t21 起恢复可用——M2 批次武器并集已改为 data/weapons.json
115 行数据驱动（旧 75 暂定 slug 废除），且 main() 时序由"先清空再生成"改为
"先生成后按 SPEC 清单清理"（生成失败时旧素材保持可用，绝无半空库窗口）。

输出:
    art/generated/<分类>/*.png   占位素材本体
    art/generated/MANIFEST.md    素材清单（含代码替换点映射，随生成自动更新）
    art/generated/_preview.png   全素材联络表（4x 放大，供人工检查）

说明: 当前项目全部画面为程序化纯色 Polygon2D（详见 MANIFEST「现状」列），
本脚本生成的像素图仅用于预先占位与风格锚定，尚未接入任何场景；
后续替换素材时按 MANIFEST 的「代码替换点」逐个接线即可。
"""
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated"
RNG = random.Random(42)

# 每个素材: (相对路径, 用途, 现状代码点, 替换指引)
SPEC = []  # [(path, purpose, current, note)]


def add(path, purpose, current, note):
    SPEC.append((path, purpose, current, note))


def C(hexstr, a=255):
    hexstr = hexstr.lstrip("#")
    if len(hexstr) == 3:
        hexstr = "".join(ch * 2 for ch in hexstr)
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16), a)


OUTLINE = C("#181420")


def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def px(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((int(x), int(y)), c)


def rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(img, x, y, c)


def hline(img, x0, x1, y, c):
    for x in range(x0, x1 + 1):
        px(img, x, y, c)


def vline(img, x, y0, y1, c):
    for y in range(y0, y1 + 1):
        px(img, x, y, c)


def disk(img, cx, cy, r, c):
    for y in range(-r, r + 1):
        for x in range(-r, r + 1):
            if x * x + y * y <= r * r + r * 0.3:
                px(img, cx + x, cy + y, c)


def ring(img, cx, cy, r, c, w=1):
    for y in range(-r - w, r + w + 1):
        for x in range(-r - w, r + w + 1):
            d = math.hypot(x, y)
            if r - 0.5 <= d <= r + w - 0.5:
                px(img, cx + x, cy + y, c)


def outline(img, c=OUTLINE):
    im = img.load()
    w, h = img.size
    src = img.copy().load()
    for y in range(h):
        for x in range(w):
            if im[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] != 0:
                    im[x, y] = c
                    break


def eyes(img, cx, cy, gap=2, white=C("#f4f4f0"), pupil=C("#20242c")):
    px(img, cx - gap, cy, white)
    px(img, cx + gap, cy, white)
    px(img, cx - gap, cy + 1, pupil)
    px(img, cx + gap, cy + 1, pupil)


def shade_top(img, c, rows=1):
    im = img.load()
    for x in range(img.width):
        for y in range(img.height):
            if im[x, y][3] != 0:
                for r in range(rows):
                    if im[x, y - r][3] != 0:
                        px(img, x, y - r, c)
                break


def noise(img, colors, density=0.08, region=None):
    x0, y0, x1, y1 = region or (0, 0, img.width - 1, img.height - 1)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if img.getpixel((x, y))[3] != 0 and RNG.random() < density:
                px(img, x, y, RNG.choice(colors))


def save(img, relpath, purpose, current, note):
    p = OUT / relpath
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p)
    add(relpath, purpose, current, note)


def tile_floor(base, alt, seam, size=16):
    img = canvas(size, size)
    rect(img, 0, 0, size - 1, size - 1, base)
    noise(img, [alt, seam], 0.16)
    # 细碎裂纹
    for _ in range(3):
        x, y = RNG.randint(1, 13), RNG.randint(1, 13)
        px(img, x, y, seam)
        px(img, x + 1, y, seam)
    # 无缝化: 边缘用 alt 打散
    for i in range(size):
        if i % 3 != 0:
            px(img, i, 0, alt)
            px(img, 0, i, alt)
    return img


def tile_wall(base, dark, light, size=16):
    img = canvas(size, size)
    rect(img, 0, 0, size - 1, size - 1, base)
    # 砖缝(错缝两层)
    for y in (0, 4, 8, 12):
        hline(img, 0, size - 1, y + 3, dark)
    for row, off in ((0, 3), (1, 11), (2, 3), (3, 11)):
        y = row * 4
        for yy in range(y, y + 3):
            px(img, off, yy, dark)
            px(img, (off + 8) % size, yy, dark)
    hline(img, 0, size - 1, 0, light)
    noise(img, [dark, light], 0.10)
    return img


# ---------------------------------------------------------------- characters
def hero_base(body, cloak, skin=C("#f2dfbe")):
    img = canvas(16, 16)
    # 腿
    rect(img, 5, 12, 6, 14, C("#3a3444"))
    rect(img, 9, 12, 10, 14, C("#3a3444"))
    # 身体(披风/铠甲)
    rect(img, 4, 7, 11, 12, body)
    rect(img, 4, 7, 11, 8, shade(body, 1.18))
    if cloak:
        rect(img, 4, 8, 5, 12, cloak)
        rect(img, 10, 8, 11, 12, cloak)
    # 头
    rect(img, 4, 1, 11, 7, skin)
    eyes(img, 8, 4, gap=2)
    return img


def shade(c, f):
    return (min(255, int(c[0] * f)), min(255, int(c[1] * f)), min(255, int(c[2] * f)), c[3])


def gen_hero_vanguard():
    img = hero_base(C("#9aa8bd"), cloak=C("#6d7c94"))
    # 头盔
    rect(img, 3, 0, 12, 3, C("#b8c6d8"))
    hline(img, 3, 12, 3, C("#e2c04c"))
    px(img, 7, 0, C("#d23b3b"))
    px(img, 8, 0, C("#d23b3b"))
    px(img, 7, 1, C("#a02a2a"))
    px(img, 8, 1, C("#a02a2a"))
    # 胸甲纹 + 盾(左手)
    vline(img, 7, 9, 12, C("#e2c04c"))
    rect(img, 1, 7, 3, 12, C("#8194ad"))
    rect(img, 1, 7, 3, 8, C("#a5b6cc"))
    px(img, 2, 9, C("#e2c04c"))
    # 剑柄(右手)
    px(img, 13, 9, C("#7a5230"))
    px(img, 13, 8, C("#cfd6e0"))
    outline(img)
    save(img, "characters/hero_vanguard.png", "英雄「骑士·凛」站立像（正面）",
         "core/player/player.tscn:27-29 Sprite=12x14 米色色块; autoload/fx.gd:197 受击白闪按节点名 Sprite 查找",
         "替换为四向行走 SpriteSheet（每向 idle+walk 2-4 帧），节点保留名 Sprite 以复用白闪")


def gen_hero_ranger():
    img = hero_base(C("#7a8a5a"), cloak=C("#4e5f3c"))
    # 兜帽
    rect(img, 3, 0, 12, 3, C("#5a7a44"))
    px(img, 4, 3, C("#5a7a44"))
    px(img, 11, 3, C("#5a7a44"))
    hline(img, 5, 10, 3, C("#3f5a30"))
    # 背弓
    vline(img, 12, 2, 8, C("#8a6a3c"))
    px(img, 11, 2, C("#cfd6e0"))
    px(img, 11, 5, C("#cfd6e0"))
    px(img, 11, 8, C("#cfd6e0"))
    # 腰带
    hline(img, 4, 11, 10, C("#5c4530"))
    px(img, 7, 10, C("#e2c04c"))
    outline(img)
    save(img, "characters/hero_ranger.png", "英雄「游侠·苇」站立像（正面）",
         "core/player/player.tscn:27-29 同上（两位英雄共用同一 Sprite 节点）",
         "同骑士·凛；另需影袭残影帧（半透明复制帧即可）")


# ---------------------------------------------------------------- hero walk sheets (m2-t17)
# 四向行走帧表：64x64 = 4 行(下/上/左/右) x 4 列(idle + walk x3)，16px/帧。
# 契约（消费端 core/player/player.gd ANIM_* 常量）：
#   frame = 方向行 * 4 + 列；idle=列0，行走循环=列1..3（8t/帧）。
# 纪律：本节**零共享 RNG**（纯确定性像素数学）——插入主流程不扰动其它子树字节。
HERO_WALK_SPEC = {
    # 配色/头饰与站立像（gen_hero_* / gen_heroes_m2）逐英雄对齐
    "vanguard": {"name": "骑士·凛", "body": "#9aa8bd", "cloak": "#6d7c94", "hat": "helm",
                 "hair": "#b8c6d8", "weapon": "sword", "shield": True},
    "ranger":   {"name": "游侠·苇", "body": "#7a8a5a", "cloak": "#4e5f3c", "hat": "hood",
                 "hood": "#5a7a44", "hair": "#4e5f3c", "weapon": "bow", "shield": False},
    "engineer": {"name": "工程师·铆", "body": "#c88a3c", "cloak": "#96682a", "hat": "goggles",
                 "hair": "#96682a", "weapon": "gun", "shield": False},
    "mage":     {"name": "法师·烬", "body": "#8a6ab8", "cloak": "#6a4a94", "hat": "wizard",
                 "hair": "#5c4530", "weapon": "staff", "shield": False},
    "assassin": {"name": "刺客·蝉", "body": "#4a4a5c", "cloak": "#33333f", "hat": "hood",
                 "hood": "#33333f", "hair": "#33333f", "weapon": "dagger", "shield": False},
    "guardian": {"name": "守护者·萄", "body": "#7a9ab8", "cloak": "#54748f", "hat": "halo",
                 "hair": "#d8b040", "weapon": "mace", "shield": False},
}


def _hero_walk_roster():
    """数据驱动英雄清单：data/heroes.json 全部行优先；数据行尚未落地的美术名录英雄
    （T11 mage / T13 assassin+guardian）按 HERO_WALK_SPEC 兜底补齐——新英雄进数据表后
    重跑生成器即自动覆盖（并集去重，与顺序无关，字节稳定）。"""
    heroes = json.load(open(ROOT / "data" / "heroes.json", encoding="utf-8"))
    roster = [(hid, str(row.get("name", hid))) for hid, row in heroes.items()]
    known = set(heroes.keys())
    for hid, spec in HERO_WALK_SPEC.items():
        if hid not in known:
            roster.append((hid, spec["name"]))
    return roster


def _hero_legs(img, d, phase):
    """腿部四相位：0=并立(idle) 1=左/后腿抬 2=passing(双腿收拢+下沉) 3=右/前腿抬。"""
    leg = C("#3a3444")
    if d in (0, 1):                       # 正/背面：左右腿交替抬落
        if phase == 0:
            rect(img, 5, 12, 6, 14, leg)
            rect(img, 9, 12, 10, 14, leg)
        elif phase == 1:
            rect(img, 5, 11, 6, 12, leg)  # 左腿抬起（短）
            rect(img, 9, 12, 10, 14, leg)
        elif phase == 2:
            rect(img, 5, 12, 6, 13, leg)  # 双腿微收（配合躯干下沉）
            rect(img, 9, 12, 10, 13, leg)
        else:
            rect(img, 5, 12, 6, 14, leg)
            rect(img, 9, 11, 10, 12, leg) # 右腿抬起
    else:                                 # 侧面：前后腿跨步（朝向前腿在行进侧）
        if d == 3:                        # 朝右：前腿 +x / 后腿 -x
            fx0, fx1, ftoe, bx0, bx1, btoe = 9, 10, 11, 6, 7, 5
        else:                             # 朝左：前腿 -x / 后腿 +x
            fx0, fx1, ftoe, bx0, bx1, btoe = 6, 7, 5, 9, 10, 11
        if phase == 0:
            rect(img, 7, 12, 8, 14, leg)
            rect(img, 9, 12, 10, 14, leg)
        elif phase == 1:
            rect(img, bx0, 12, bx1, 13, leg)        # 后腿抬
            rect(img, fx0, 12, fx1, 14, leg)        # 前腿撑地
            px(img, ftoe, 14, leg)                  # 前脚尖
        elif phase == 2:
            rect(img, 7, 12, 8, 13, leg)
            rect(img, 9, 12, 10, 13, leg)
        else:
            rect(img, fx0, 12, fx1, 13, leg)        # 前腿抬
            rect(img, bx0, 12, bx1, 14, leg)        # 后腿撑地
            px(img, btoe, 14, leg)                  # 后脚尖
    return leg


def _hero_hat(img, spec, d, y):
    """头饰四向。d: 0=down 1=up 2=left 3=right；y 为本相位头部纵向偏移。"""
    kind = spec["hat"]
    cloak = C(spec["cloak"])
    if kind == "helm":
        helm = C("#b8c6d8")
        if d == 0:                        # 盔体+金沿+红翎正面
            rect(img, 3, y, 12, 3 + y, helm)
            hline(img, 3, 12, 3 + y, C("#e2c04c"))
            rect(img, 7, y, 8, 1 + y, C("#d23b3b"))
            rect(img, 7, 1 + y, 8, 1 + y, C("#a02a2a"))
        elif d == 1:                      # 背面盔体+红翎
            rect(img, 3, y, 12, 3 + y, helm)
            rect(img, 7, y, 8, 1 + y, C("#d23b3b"))
            hline(img, 3, 12, 3 + y, C("#8194ad"))
        else:                             # 侧面盔体+纵贯红翎条
            rect(img, 4, y, 11, 3 + y, helm)
            hline(img, 5, 10, y, C("#d23b3b"))
            hline(img, 5, 10, 1 + y, C("#a02a2a"))
            hline(img, 4, 11, 3 + y, C("#e2c04c"))
    elif kind == "hood":
        hc = C(spec.get("hood", spec["cloak"]))
        if d == 0:
            rect(img, 3, y, 12, 3 + y, hc)
            px(img, 4, 3 + y, hc)
            px(img, 11, 3 + y, hc)
            hline(img, 5, 10, 3 + y, shade(C(spec["body"]), 0.6))
            if spec["weapon"] == "dagger":           # 刺客兜帽红眼光
                px(img, 6, 3 + y, C("#e83a4a"))
                px(img, 9, 3 + y, C("#e83a4a"))
        elif d == 1:
            rect(img, 3, y, 12, 4 + y, hc)
            hline(img, 4, 11, 4 + y, shade(hc, 0.7))
        else:
            rect(img, 4, y, 11, 3 + y, hc)
            px(img, 3 if d == 2 else 12, 1 + y, hc)  # 兜帽尖角在后侧
            hline(img, 5, 10, 3 + y, shade(C(spec["body"]), 0.6))
    elif kind == "wizard":
        light = shade(cloak, 1.25)
        if d == 0:
            rect(img, 2, y, 13, 1 + y, cloak)        # 帽檐
            rect(img, 4, 1 + y, 11, 2 + y, cloak)
            rect(img, 6, 2 + y, 9, 3 + y, light)
            px(img, 13, y, C("#ffd94a"))
        elif d == 1:
            rect(img, 2, 1 + y, 13, 2 + y, cloak)
            rect(img, 5, y, 10, 1 + y, cloak)
            rect(img, 7, y, 9, 1 + y, light)
        else:
            rect(img, 4, 1 + y, 12, 2 + y, cloak)
            rect(img, 6, y, 10, 1 + y, cloak)
            rect(img, 7, y, 10, 1 + y, light)
    elif kind == "goggles":
        cap = C("#c8d0dc")
        if d == 0:
            rect(img, 3, 2 + y, 12, 4 + y, cap)
            rect(img, 4, 3 + y, 6, 4 + y, C("#5ab0ff"))
            rect(img, 9, 3 + y, 11, 4 + y, C("#5ab0ff"))
            px(img, 13, 1 + y, C("#e2c04c"))
        elif d == 1:
            rect(img, 3, 1 + y, 12, 3 + y, cap)
            hline(img, 3, 12, 3 + y, shade(cap, 0.8))
        else:
            rect(img, 4, 1 + y, 11, 3 + y, cap)
            rect(img, 9 if d == 3 else 4, 2 + y, 11 if d == 3 else 6, 3 + y, C("#5ab0ff"))
    elif kind == "halo":
        hline(img, 5, 10, y, C("#ffe86a"))
        hline(img, 4, 11, 2 + y, C("#e2c04c"))


def _hero_weapon(img, spec, d, y):
    """武器剪影：侧面=持握朝向；正/背面=身侧配件（与站立像一致）。"""
    kind = spec["weapon"]
    blade = C("#d7dee8")
    wood = C("#7a5230")
    if d in (2, 3):
        if d == 2:                        # 朝左：全部镜像到左侧
            def hh(x0, x1, yy, c):
                hline(img, 15 - x1, 15 - x0, yy, c)

            def vv(x, y0, y1, c):
                vline(img, 15 - x, y0, y1, c)

            def rr(x0, y0, x1, y1, c):
                rect(img, 15 - x1, y0, 15 - x0, y1, c)
        else:
            def hh(x0, x1, yy, c):
                hline(img, x0, x1, yy, c)

            def vv(x, y0, y1, c):
                vline(img, x, y0, y1, c)

            def rr(x0, y0, x1, y1, c):
                rect(img, x0, y0, x1, y1, c)
        if kind == "sword":
            hh(11, 14, 8 + y, blade)
            hh(11, 14, 9 + y, shade(blade, 0.8))
            px(img, 11 if d == 3 else 4, 9 + y, C("#e2c04c"))
            hh(10, 10, 8 + y, wood)
        elif kind == "bow":
            vv(13, 3 + y, 11 + y, wood)
            vv(14, 4 + y, 10 + y, C("#e8e4da"))
            px(img, 12, 3 + y, wood)
            px(img, 12, 11 + y, wood)
        elif kind == "staff":
            vv(13, 3 + y, 12 + y, wood)
            disk(img, 13 if d == 3 else 2, 2 + y, 1, C("#8ae8ff"))
        elif kind == "dagger":
            hh(11, 12, 8 + y, blade)
            px(img, 11 if d == 3 else 4, 9 + y, C("#e2c04c"))
        elif kind == "gun":
            rr(11, 8 + y, 13, 9 + y, C("#5c4530"))
            px(img, 14 if d == 3 else 1, 8 + y, C("#3a3444"))
        elif kind == "mace":
            vv(13, 6 + y, 10 + y, wood)
            disk(img, 13 if d == 3 else 2, 5 + y, 1, C("#c8d0dc"))
    else:
        if spec.get("shield") and d == 0:
            rect(img, 1, 7 + y, 3, 12 + y, C("#8194ad"))
            rect(img, 1, 7 + y, 3, 8 + y, C("#a5b6cc"))
            px(img, 2, 9 + y, C("#e2c04c"))
            px(img, 13, 9 + y, wood)                  # 剑柄露头
            px(img, 13, 8 + y, blade)
        elif spec.get("shield") and d == 1:
            rect(img, 12, 8 + y, 14, 12 + y, C("#8194ad"))   # 背面盾背在身后
            px(img, 13, 10 + y, C("#e2c04c"))
        else:
            rect(img, 13, 9 + y, 14, 12 + y, wood if kind != "staff" else C("#7a5230"))
            if kind == "staff" and d == 1:
                disk(img, 13, 8 + y, 1, C("#8ae8ff"))
            if kind == "bow":
                vline(img, 13, 3 + y, 10 + y, wood)   # 背弓露出肩侧


def _paint_hero_frame(spec, d, phase):
    """单帧 16x16。d: 0=down 1=up 2=left 3=right；phase: 0=idle 1..3=walk。"""
    img = canvas(16, 16)
    body = C(spec["body"])
    cloak = C(spec["cloak"])
    skin = C("#f2dfbe")
    y = 1 if phase == 2 else 0            # passing 相位躯干下沉 1px（步幅顶点恢复）
    _hero_legs(img, d, phase)
    if d in (0, 1):                       # 正/背面躯干
        rect(img, 4, 7 + y, 11, 12 + y, body)
        rect(img, 4, 7 + y, 11, 8 + y, shade(body, 1.18))
        if d == 0:
            rect(img, 4, 8 + y, 5, 12 + y, cloak)    # 侧披
            rect(img, 10, 8 + y, 11, 12 + y, cloak)
        else:
            rect(img, 4, 8 + y, 11, 12 + y, cloak)   # 背面整片披风
        rect(img, 4, 1 + y, 11, 7 + y, skin if d == 0 else C(spec["hair"]))
        if d == 0:
            eyes(img, 8, 4 + y, gap=2)
    else:                                 # 侧面躯干（窄身）
        rect(img, 6, 7 + y, 9, 12 + y, body)
        rect(img, 6, 7 + y, 9, 8 + y, shade(body, 1.18))
        bx = 6 if d == 3 else 8                     # 披风在后侧
        rect(img, bx, 8 + y, bx + 1, 12 + y, cloak)
        rect(img, 5, 1 + y, 10, 6 + y, skin)
        ex = 9 if d == 3 else 6                     # 单眼朝向边缘
        px(img, ex, 4 + y, C("#f4f4f0"))
        px(img, ex, 5 + y, C("#20242c"))
        px(img, 11 if d == 3 else 4, 5 + y, shade(skin, 0.85))  # 鼻尖
    _hero_hat(img, spec, d, y)
    _hero_weapon(img, spec, d, y)
    return img


def gen_hero_walk_sheets():
    for hid, name in _hero_walk_roster():
        spec = HERO_WALK_SPEC.get(hid)
        if spec is None:
            print(f"[walk] 跳过 {hid}（HERO_WALK_SPEC 无视觉规格，待补表重跑）")
            continue
        sheet = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for d in range(4):
            for ph in range(4):
                frame = _paint_hero_frame(spec, d, ph)
                outline(frame)
                sheet.paste(frame, (ph * 16, d * 16))
        save(sheet, f"characters/hero_{hid}_sheet.png",
             f"英雄「{name}」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧）",
             "core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4",
             "m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变）")


MANIFEST_SHEET_ANCHOR = "| `characters/hero_ranger.png` |"
MANIFEST_SHEET_MARK = "`characters/hero_vanguard_sheet.png`"
MANIFEST_GAP_OLD = "| 四向行走动画 | 占位图只有 1 帧站立 | 每英雄 4 向 x (idle+walk2) 帧，16x16/帧；可由本占位图做连锁重绘基底 |"
MANIFEST_GAP_NEW = "| 四向行走动画 | **m2-t17 已程序化交付**：`characters/hero_<id>_sheet.png`（4 向 x idle+walk×3, 16px/帧），player.gd 移动方向自动切换 | 正式素材可按此帧表布局连锁重绘；敌人 2 帧动画见 T21 |"


def _manifest_splice_hero_sheets():
    """把 SPEC 内帧表行定点拼接进既有 MANIFEST（幂等；锚点=hero_ranger 行）。
    m2-t21 全量入口恢复后 main() 会整表重写（帧表行随 SPEC 自然入表）；
    本拼接保留给 --hero-sheets 窄通道（只重做 characters 帧表时同步清单）。"""
    p = OUT / "MANIFEST.md"
    text = p.read_text(encoding="utf-8")
    if MANIFEST_SHEET_MARK in text:
        return                          # 幂等：已拼接（重跑零字节漂移）
    out = []
    inserted = False
    for line in text.split("\n"):
        out.append(line)
        if line.startswith(MANIFEST_SHEET_ANCHOR):
            for rel, purpose, current, note in SPEC:
                img = Image.open(OUT / rel)
                out.append(f"| `{rel}` | {img.width}x{img.height} | {purpose} | {current} | "
                           f"{note if note else '—'} |")
            inserted = True
    if not inserted:
        raise RuntimeError("MANIFEST 锚点行缺失: " + MANIFEST_SHEET_ANCHOR)
    text = "\n".join(out)
    if MANIFEST_GAP_OLD in text:
        text = text.replace(MANIFEST_GAP_OLD, MANIFEST_GAP_NEW)
    p.write_text(text, encoding="utf-8")


def gen_hero_sheets_scoped():
    """m2-t17 定点再生入口：仅重写 characters/hero_*_sheet.png + 拼接 MANIFEST 行。
    不清空、不触碰其它子树（全量再生用 main()，m2-t21 起已恢复可用）。"""
    SPEC.clear()
    gen_hero_walk_sheets()
    _manifest_splice_hero_sheets()
    print(f"[scoped] 英雄行走帧表 {len(SPEC)} 张 -> {OUT / 'characters'}（MANIFEST 已同步）")


ENEMY_SPRITES = {
    "kuli_bug": ("苦力虫（自爆虫）", "data/enemies.json id=kuli_bug; 现为 room_combat.gd:191-197 按 ARCHETYPE_COLORS.suicide 0.4,0.8,0.35 纯色块",
                 "原型:绿色圆虫+引信触角+大眼；死亡闪烁接 fuse_ticks"),
    "cave_bat": ("穴蝠", "同上, archetype=orbiter 0.45,0.42,0.55",
                 "原型:灰紫蝙蝠,展开双翼,红眼獠牙；飞行做 2 帧扑翼"),
    "crossbowman": ("弩兵", "同上, archetype=shooter 0.5,0.6,0.85",
                    "原型:蓝衣弩手+弩；蓄力(windup 30t)需抬弩帧"),
    "vine_charger": ("藤蔓冲锋者", "同上, archetype=charger 0.7,0.4,0.8",
                     "原型:紫甲冲撞兽,前倾冲锋蓄力帧+冲锋帧"),
    "mushroom_spore": ("蘑菇孢子手", "同上, archetype=mushroom_spore 0.58,0.82,0.46",
                       "原型:绿斑蘑菇,喷孢子；攻击时伞盖压缩帧"),
}


# m4-a1：锚点后移至暴击帧前一行（elem_shock_enemy）——新缺行拼接位置与 SPEC
# 顺序一致（暴击帧在元素敌方变体之后、laser_seg 之前），窄通道与全量重写行序一致。
MANIFEST_PROJ_ANCHOR = "| `projectiles/elem_shock_enemy.png` |"


def _manifest_splice_missing_rows():
    """把 SPEC 中 MANIFEST 尚缺的行定点拼接进既有清单（幂等，逐行查重）。
    供 --projectiles 窄通道同步清单（全量再生走 main() 整表重写，不经此处）。"""
    p = OUT / "MANIFEST.md"
    text = p.read_text(encoding="utf-8")
    rows = []
    for rel, purpose, current, note in SPEC:
        if f"`{rel}`" not in text:
            img = Image.open(OUT / rel)
            rows.append(f"| `{rel}` | {img.width}x{img.height} | {purpose} | {current} | "
                        f"{note if note else '—'} |")
    if not rows:
        return                          # 幂等：无缺失行（重跑零字节漂移）
    out = []
    inserted = False
    for line in text.split("\n"):
        out.append(line)
        if line.startswith(MANIFEST_PROJ_ANCHOR):
            out.extend(rows)
            inserted = True
    if not inserted:
        raise RuntimeError("MANIFEST 锚点行缺失: " + MANIFEST_PROJ_ANCHOR)
    p.write_text("\n".join(out), encoding="utf-8")


def gen_projectiles_scoped():
    """m2-t27 定点再生入口：仅重写 projectiles/*.png + 拼接 MANIFEST 缺行。
    不清空、不触碰其它子树（全量再生用 main()）。"""
    SPEC.clear()
    gen_projectiles()
    _manifest_splice_missing_rows()
    print(f"[scoped] 弹丸素材 {len(SPEC)} 张 -> {OUT / 'projectiles'}（MANIFEST 已同步）")


def gen_enemy(id_, name, current, note, painter):
    img = painter()
    outline(img)
    save(img, f"enemies/{id_}.png", f"敌人「{name}」", current, note)


def paint_kuli():
    img = canvas(16, 16)
    disk(img, 8, 10, 5, C("#57b13f"))
    disk(img, 8, 10, 3, C("#7ed05c"))
    hline(img, 6, 10, 8, C("#a7e88a"))
    eyes(img, 8, 9, gap=2, pupil=C("#1c2a14"))
    vline(img, 8, 3, 5, C("#3f8a2e"))
    px(img, 7, 2, C("#ffd94a"))
    px(img, 9, 2, C("#ffd94a"))
    for x in (5, 11):
        px(img, x, 14, C("#3f8a2e"))
        px(img, x, 15, C("#2e6b21"))
    return img


def paint_bat():
    img = canvas(16, 16)
    # 翼
    for s in (-1, 1):
        for i in range(5):
            px(img, 8 + s * (2 + i), 7 + (1 if i > 2 else 0), C("#6f6382"))
            px(img, 8 + s * (2 + i), 8, C("#574d68"))
        px(img, 8 + s * 3, 10, C("#574d68"))
        px(img, 8 + s * 5, 9, C("#574d68"))
    # 身体+耳
    disk(img, 8, 8, 3, C("#7b6f92"))
    px(img, 6, 4, C("#7b6f92"))
    px(img, 10, 4, C("#7b6f92"))
    px(img, 6, 3, C("#574d68"))
    px(img, 10, 3, C("#574d68"))
    eyes(img, 8, 8, gap=1, white=C("#ff5a4a"), pupil=C("#701c14"))
    px(img, 7, 11, C("#f4f4f0"))
    px(img, 9, 11, C("#f4f4f0"))
    return img


def paint_crossbow():
    img = hero_base(C("#5b7ec2"), cloak=None)
    rect(img, 3, 0, 12, 2, C("#8a97ad"))
    hline(img, 4, 11, 2, C("#6a768a"))
    # 弩(横持)
    hline(img, 9, 15, 8, C("#7a5230"))
    vline(img, 12, 6, 10, C("#7a5230"))
    px(img, 12, 8, C("#cfd6e0"))
    rect(img, 10, 12, 11, 14, C("#3a3444"))
    return img


def paint_charger(body=C("#8a56b0"), light=C("#a873cc"), dark=C("#4e2f66"), horn=C("#e8def4")):
    img = canvas(16, 16)
    # 前倾的冲撞兽
    rect(img, 3, 5, 12, 12, body)
    rect(img, 3, 5, 12, 6, light)
    rect(img, 10, 2, 14, 7, body)
    px(img, 10, 1, horn)
    px(img, 13, 1, horn)
    eyes(img, 12, 4, gap=1, pupil=C("#2a1038"))
    # 蹄
    for x in (4, 7, 10):
        rect(img, x, 13, x + 1, 14, dark)
    vline(img, 2, 8, 10, dark)
    return img


def paint_mushroom():
    img = canvas(16, 16)
    rect(img, 6, 9, 9, 14, C("#e8dcc0"))
    rect(img, 3, 4, 12, 9, C("#5aa848"))
    hline(img, 3, 12, 4, C("#7ec463"))
    px(img, 5, 6, C("#cfe8b8"))
    px(img, 9, 5, C("#cfe8b8"))
    px(img, 10, 7, C("#cfe8b8"))
    eyes(img, 8, 11, gap=1)
    px(img, 7, 13, C("#c9a88a"))
    px(img, 9, 13, C("#c9a88a"))
    return img


def paint_lizard():
    img = canvas(20, 20)
    rect(img, 6, 13, 8, 18, C("#3f6b46"))
    rect(img, 11, 13, 13, 18, C("#3f6b46"))
    rect(img, 5, 6, 14, 13, C("#5c9a66"))
    rect(img, 5, 6, 14, 7, C("#79bd83"))
    # 头
    rect(img, 6, 1, 13, 6, C("#5c9a66"))
    eyes(img, 10, 3, gap=2, pupil=C("#122415"))
    px(img, 8, 5, C("#2e4a33"))
    px(img, 11, 5, C("#2e4a33"))
    # 双刀
    for s in (-1, 1):
        x = 16 if s > 0 else 3
        vline(img, x, 5, 12, C("#d7dee8"))
        px(img, x, 13, C("#e2c04c"))
    vline(img, 9, 8, 12, C("#e2c04c"))
    return img


def paint_wangchong():
    img = canvas(20, 20)
    disk(img, 10, 12, 6, C("#c2482e"))
    disk(img, 10, 12, 4, C("#e06a3a"))
    hline(img, 7, 13, 10, C("#f2b25c"))
    hline(img, 8, 12, 13, C("#f2b25c"))
    eyes(img, 10, 11, gap=2, pupil=C("#33110a"))
    vline(img, 10, 3, 5, C("#6b2a1c"))
    px(img, 10, 2, C("#ffd94a"))
    rect(img, 3, 17, 5, 18, C("#6b2a1c"))
    rect(img, 15, 17, 17, 18, C("#6b2a1c"))
    return img


def paint_colossus():
    img = canvas(32, 32)
    # 树干躯干
    rect(img, 10, 8, 21, 26, C("#6b4a30"))
    rect(img, 10, 8, 21, 11, C("#83603f"))
    vline(img, 14, 12, 24, C("#543a26"))
    vline(img, 19, 12, 24, C("#543a26"))
    # 树冠
    disk(img, 16, 7, 7, C("#3f7a3a"))
    disk(img, 11, 10, 4, C("#4f9347"))
    disk(img, 21, 10, 4, C("#4f9347"))
    px(img, 13, 5, C("#69b35a"))
    px(img, 19, 4, C("#69b35a"))
    # 发光眼+核心
    rect(img, 13, 15, 14, 17, C("#7dff5a"))
    rect(img, 18, 15, 19, 17, C("#7dff5a"))
    disk(img, 16, 21, 2, C("#7dff5a"))
    px(img, 16, 21, C("#d2ffb8"))
    # 根足与藤臂
    rect(img, 9, 27, 13, 30, C("#543a26"))
    rect(img, 19, 27, 23, 30, C("#543a26"))
    for s in (-1, 1):
        for i in range(4):
            px(img, 16 + s * (7 + i), 14 + i, C("#4f9347"))
    return img


# ---------------------------------------------------------------- projectiles
def bullet(core, mid, edge, size=8, border=None):
    """圆形弹丸（8x8 默认）。border 非 None 时最外圈改画暗色描边（m2-t27 敌方元素弹
    变体示敌）；纯几何无随机项，输出确定（全局 RNG 流零消耗，不动其它素材确定性）。"""
    img = canvas(size, size)
    r = size // 2 - 1
    disk(img, size // 2, size // 2, r, border if border is not None else edge)
    if border is not None:
        disk(img, size // 2, size // 2, max(1, r - 1), edge)
    disk(img, size // 2, size // 2, max(1, r - 2), mid)
    px(img, size // 2 - 1, size // 2 - 1, core)
    return img


ELEM_ENEMY_BORDER = OUTLINE   # 敌方元素弹暗边框色（同全局描边深色 #181420）


def save_elem_bullet(elem, hexes, variant="player"):
    """元素弹按 variant 出图（m2-t27 阵营分化）：player=基础图 / enemy=暗边框变体。
    文件名 elem_<elem>.png 与 elem_<elem>_<variant>.png；同色系+暗圈示敌。"""
    border = ELEM_ENEMY_BORDER if variant == "enemy" else None
    img = bullet(C("#ffffff"), C(hexes[0]), C(hexes[1]), border=border)
    suffix = "" if variant == "player" else "_%s" % variant
    purpose = f"{elem} 元素弹" if variant == "player" else f"{elem} 元素弹（敌方变体·暗边框）"
    save(img, f"projectiles/elem_{elem}{suffix}.png", purpose,
         "autoload/fx.gd:18-21 元素色表（火/冰/毒/电）", "元素异常命中粒子同色系")


CRIT_RIM = C("#ffd94a")   # m4-a1 暴击弹金描边（亮金，与基础弹 #e8a020 暗金边区分）


def save_crit_bullet(variant="player"):
    """暴击弹专用帧（m4-a1，复刻 m2-t27 元素弹管线）：金描边 + 强化发光变体。
    player=金圈+亮金光晕芯+白热芯；enemy=金圈+赤芯+白热芯（阵营身份由内圈色承载，
    同 m2-t27 敌方变体口径）。纯几何无随机项，输出确定（全局 RNG 流零消耗）。"""
    img = canvas(8, 8)
    disk(img, 4, 4, 3, CRIT_RIM)                  # 金色描边圈（外缘，强化发光观感）
    disk(img, 4, 4, 2, C("#fff3b8") if variant == "player" else C("#ff6a55"))
    px(img, 3, 3, C("#ffffff"))                   # 白热芯（强化发光）
    px(img, 4, 4, C("#ffffff"))
    purpose = ("玩家暴击弹（金描边·强化发光）" if variant == "player"
               else "敌方暴击弹（金描边·赤芯）")
    save(img, f"projectiles/bullet_{variant}_crit.png", purpose,
         "room_combat.gd _sync_bullet_visuals 必暴窗（CombatSystem.forced_crit_until 只读）切换",
         "m4-a1 表现层专用帧：暴击判定（DamageCalc 唯一随机乘区）零影响")


def gen_projectiles():
    img = bullet(C("#ffffff"), C("#ffe86a"), C("#e8a020"))
    save(img, "projectiles/bullet_player.png", "玩家子弹（radius≈3px）",
         "floor_scene.gd:61 / room_combat.gd:37 PLAYER_BULLET_COLOR 纯色方块 Polygon2D",
         "元素弹可用 modulate 调色或换 elem_* 专用图")
    img = bullet(C("#ffd9d0"), C("#ff6a55"), C("#a8281c"))
    save(img, "projectiles/bullet_enemy.png", "敌方子弹",
         "floor_scene.gd:62 / room_combat.gd:38 ENEMY_BULLET_COLOR 纯色方块",
         "同上")
    for elem, hexes in {
        "fire": ("#ff4a1e", "#ffb03a"), "ice": ("#8ae8ff", "#3a86c8"),
        "poison": ("#a8e84a", "#4a8a2e"), "shock": ("#e0b0ff", "#8040c8"),
    }.items():
        save_elem_bullet(elem, hexes)
        save_elem_bullet(elem, hexes, variant="enemy")   # m2-t27 敌方暗边框变体
    save_crit_bullet()                                   # m4-a1 暴击弹专用帧（玩家/敌两套）
    save_crit_bullet(variant="enemy")
    img = canvas(16, 6)
    rect(img, 0, 2, 15, 3, C("#ffe0b0", 200))
    rect(img, 2, 1, 13, 4, C("#ff9a3a", 150))
    save(img, "projectiles/laser_seg.png", "激光束段（16x6 可平铺）",
         "data/weapons.json category=laser（熔断激光/冰晶射线）暂无表现", "水平旋转 90° 得竖直束")


# ---------------------------------------------------------------- pickups
def gen_pickups():
    img = canvas(8, 8)
    disk(img, 4, 4, 3, C("#c8901c"))
    disk(img, 4, 4, 2, C("#ffd94a"))
    px(img, 4, 3, C("#fff3b8"))
    save(img, "pickups/coin.png", "金币掉落",
         "core/rooms/pickup.gd:7-23 coin 色块 Polygon2D", "")
    img = canvas(8, 8)
    for i, y in enumerate(range(1, 7)):
        w = (3, 5, 7, 7, 5, 3)[i]
        hline(img, 4 - w // 2, 4 - w // 2 + w - 1, y, C("#5aa0ff"))
    px(img, 4, 3, C("#c8e0ff"))
    save(img, "pickups/energy.png", "蓝能拾取", "pickup.gd energy 0.3,0.6,1.0 色块", "")
    img = canvas(8, 8)
    for y, (a, b) in enumerate(((1, 3), (0, 7), (0, 7), (1, 6), (2, 5), (3, 4))):
        hline(img, a, b, y + 1, C("#e83a4a"))
    px(img, 1, 2, C("#ff8a94"))
    save(img, "pickups/heart.png", "红心（回血）", "pickup.gd heart 1.0,0.3,0.4 色块", "")
    img = canvas(12, 12)
    rect(img, 1, 3, 10, 10, C("#8a6a3c"))
    rect(img, 1, 3, 10, 5, C("#a8854e"))
    hline(img, 1, 10, 6, C("#5c4530"))
    rect(img, 5, 5, 6, 8, C("#e2c04c"))
    save(img, "pickups/weapon_crate.png", "武器掉落箱（drops=weapon）",
         "核心/rooms/pickup.gd 尚无武器拾取表现", "开启后接武器图标气泡")


# ---------------------------------------------------------------- tiles
def gen_tiles():
    floors = {
        "floor_cave": ("#241f2e", "#2c2638", "#1b1724", "洞穴(普通房) 地板 16x16 可平铺",
                       "floor_scene.gd:223/230 tint 0.17,0.15,0.2; room_combat.gd:368"),
        "floor_garden": ("#1e2a20", "#263428", "#161f18", "庭院(出生/起点房) 地板",
                         "floor_scene.gd:225 tint 0.14,0.16,0.15; inter_floor.gd:85; training_room.gd:217"),
        "floor_boss": ("#2e1a22", "#381f2a", "#20131a", "Boss 房 地板",
                       "floor_scene.gd:227 tint 0.2,0.13,0.16"),
    }
    for name, (b, a, s, purpose, cur) in floors.items():
        img = tile_floor(C(b), C(a), C(s))
        save(img, f"tiles/{name}.png", purpose, cur, "替换需保持 16x16 无缝")
    walls = {
        "wall_cave": ("#4a4054", "#332b3c", "#5e5270", "洞穴墙体（墙厚 16px=1 tile）",
                      "floor_scene.gd:235-236/1159/1185 0.36,0.3,0.28 色块"),
        "wall_garden": ("#4e4638", "#37311f", "#635a48", "庭院墙体", "同上（当前不分生物群系）"),
        "wall_boss": ("#4a3440", "#33232c", "#5f4452", "Boss 房墙体", "同上"),
    }
    for name, (b, d, l, purpose, cur) in walls.items():
        img = tile_wall(C(b), C(d), C(l))
        save(img, f"tiles/{name}.png", purpose, cur, "顶部 1px 亮色已内嵌")
    # 走廊
    img = tile_floor(C("#211d28"), C("#282231"), C("#181420"))
    save(img, "tiles/corridor_floor.png", "房间连接走廊地板",
         "floor_scene.gd:355-357 0.13,0.12,0.16 色块", "")
    # 门
    img = canvas(16, 16)
    rect(img, 0, 0, 15, 15, C("#8a6a3c"))
    for x in (3, 7, 11):
        vline(img, x, 0, 15, C("#6b5029"))
    rect(img, 1, 1, 2, 14, C("#a8854e"))
    px(img, 13, 8, C("#e2c04c"))
    outline(img)
    save(img, "tiles/door_closed.png", "房间木门（16px 厚墙体上的门洞盖板）",
         "floor_scene.gd:378-382/862 与 room_combat.gd:374-379 0.62,0.4,0.22 色块",
         "开门动画可滑动+淡出")
    img = canvas(16, 16)
    rect(img, 0, 0, 15, 15, C("#5c4530"))
    for x in (3, 7, 11):
        vline(img, x, 0, 15, C("#453322"))
    rect(img, 5, 6, 10, 11, C("#e2c04c"))
    rect(img, 7, 9, 8, 11, C("#5c4530"))
    disk(img, 8, 8, 1, C("#5c4530"))
    outline(img)
    save(img, "tiles/door_locked.png", "锁定门（通关条件未满足）",
         "floor_scene.gd:862 locked → 0.7,0.2,0.2 红色块", "锁牌换红色更醒目")
    # 陈设
    img = canvas(16, 16)
    rect(img, 3, 2, 12, 13, C("#6e6678"))
    rect(img, 3, 2, 12, 3, C("#8a8296"))
    rect(img, 5, 5, 10, 6, C("#544c60"))
    rect(img, 5, 9, 10, 10, C("#544c60"))
    outline(img)
    save(img, "tiles/prop_pillar.png", "石柱（实体阻挡 16x16）",
         "floor_scene.gd:284 0.5,0.48,0.52 色块", "")
    img = canvas(16, 16)
    rect(img, 2, 4, 13, 13, C("#8a6a3c"))
    hline(img, 2, 13, 8, C("#6b5029"))
    vline(img, 7, 4, 13, C("#6b5029"))
    rect(img, 2, 4, 13, 5, C("#a8854e"))
    outline(img)
    save(img, "tiles/prop_crate.png", "木箱（实体阻挡）", "floor_scene.gd:286 0.55,0.4,0.24 色块", "")
    img = canvas(16, 16)
    disk(img, 8, 10, 5, C("#2e5a2a"))
    disk(img, 6, 8, 3, C("#3f7a38"))
    disk(img, 11, 9, 3, C("#3f7a38"))
    px(img, 6, 6, C("#5aa84e"))
    px(img, 11, 7, C("#5aa84e"))
    save(img, "tiles/prop_bush.png", "灌木（纯视觉）", "floor_scene.gd:288 0.25,0.42,0.24 色块", "")
    # 藤蔓减速带
    img = canvas(32, 32)
    for _ in range(10):
        x, y = RNG.randint(2, 29), RNG.randint(2, 29)
        px(img, x, y, C("#4f9347", 150))
        px(img, x + 1, y, C("#3f7a3a", 150))
        px(img, x, y + 1, C("#3f7a3a", 150))
        if RNG.random() < 0.5:
            px(img, x + 1, y + 1, C("#69b35a", 150))
    save(img, "tiles/hazard_vine.png", "藤蔓减速带（32x32 半透明，可平铺）",
         "floor_scene.gd:291-303 半径 24 圆形 0.3,0.55,0.3 alpha0.18", "整圆贴图亦可(需含 alpha)")
    # 宝箱
    img = canvas(16, 16)
    rect(img, 2, 7, 13, 13, C("#8a6a3c"))
    rect(img, 2, 4, 13, 7, C("#a8854e"))
    hline(img, 2, 13, 7, C("#5c4530"))
    rect(img, 6, 6, 9, 9, C("#e2c04c"))
    px(img, 7, 8, C("#5c4530"))
    vline(img, 2, 4, 13, C("#e2c04c"))
    vline(img, 13, 4, 13, C("#e2c04c"))
    outline(img)
    save(img, "tiles/chest_closed.png", "宝箱（宝物房）",
         "当前宝物房无箱体表现（m1-05 证据图）", "开箱动画 2 帧即可")
    # 出口水晶
    img = canvas(12, 18)
    for i, (a, b) in enumerate(((5, 6), (4, 7), (3, 8), (3, 8), (4, 7), (5, 6))):
        hline(img, a, b, 4 + i, C("#5ab8ff"))
    px(img, 4, 6, C("#b8ecff"))
    vline(img, 5, 0, 1, C("#3a3444"))
    save(img, "tiles/exit_crystal.png", "层间出口水晶",
         "run_root.gd:150-157 marker 0.08,0.16,0.24 + crystal 0.35,0.75,1.0 色块", "可做上下浮动+发光")
    # 喷泉
    for suffix, water in (("full", "#3a86c8"), ("used", "#2a4a5c")):
        img = canvas(16, 16)
        rect(img, 2, 6, 13, 12, C("#6e6678"))
        rect(img, 3, 7, 12, 11, C(water))
        rect(img, 6, 2, 9, 6, C("#6e6678"))
        rect(img, 4, 12, 11, 13, C("#544c60"))
        if suffix == "full":
            px(img, 7, 8, C("#b8ecff"))
            px(img, 9, 9, C("#b8ecff"))
        outline(img)
        save(img, f"tiles/fountain_{suffix}.png", f"层间喷泉（{'可饮用' if suffix=='full' else '已用尽'}）",
             "inter_floor.gd:100-102/183 0.3,0.6,0.9 → 用尽 0.25,0.4,0.5", "")
    # 交互物
    img = canvas(16, 18)
    rect(img, 4, 4, 11, 12, C("#c8a03c"))
    rect(img, 5, 2, 10, 4, C("#e2c04c"))
    rect(img, 6, 6, 9, 8, C("#8a6a1c"))
    rect(img, 2, 13, 13, 15, C("#6b5029"))
    outline(img)
    save(img, "tiles/shrine.png", "雕像（许愿/强化交互）",
         "floor_scene.gd:888-895 0.75,0.58,0.2 → 用尽 0.4,0.34,0.16 色块", "用尽态换灰色 modulate")
    img = canvas(16, 18)
    rect(img, 3, 1, 12, 15, C("#3a7a96"))
    rect(img, 3, 1, 12, 2, C("#5ab0d8"))
    rect(img, 5, 4, 10, 9, C("#1c3a4a"))
    rect(img, 5, 11, 10, 12, C("#5ab0d8"))
    px(img, 7, 13, C("#e2c04c"))
    outline(img)
    save(img, "tiles/drink_machine.png", "饮料机",
         "floor_scene.gd:914-916 0.3,0.6,0.75 色块; core/interact/drink_machine.gd UI 面板", "")
    img = canvas(16, 18)
    rect(img, 4, 3, 11, 14, C("#565a72"))
    rect(img, 4, 3, 11, 4, C("#767c96"))
    disk(img, 7, 8, 2, C("#b06cff"))
    px(img, 12, 7, C("#e83a4a"))
    rect(img, 3, 15, 12, 16, C("#3a3444"))
    outline(img)
    save(img, "tiles/event_device.png", "事件装置",
         "floor_scene.gd:932-934 0.35,0.35,0.45 色块", "")


# ---------------------------------------------------------------- fx
def gen_fx():
    img = canvas(16, 16)
    ring(img, 8, 8, 5, C("#f4f4f0", 230), 2)
    for a in range(0, 360, 45):
        x = 8 + int(math.cos(math.radians(a)) * 5)
        y = 8 + int(math.sin(math.radians(a)) * 5)
        px(img, x, y, C("#ffffff"))
    save(img, "fx/fx_slash.png", "近战挥砍弧光",
         "core/player/melee.gd 目前无独立视觉（仅结算）", "旋转 0/90/180/270 覆盖四向")
    img = canvas(24, 24)
    for r, c in ((10, C("#e83a1e", 120)), (7, C("#ff8a2e", 200)), (4, C("#ffe86a"))):
        disk(img, 12, 12, r, c)
    for a in range(0, 360, 30):
        x = 12 + int(math.cos(math.radians(a)) * 10)
        y = 12 + int(math.sin(math.radians(a)) * 10)
        px(img, x, y, C("#ff8a2e", 180))
    save(img, "fx/fx_explosion.png", "爆炸爆云（自爆/死亡爆/熔火）",
         "autoload/fx.gd:116 _puff 0.9,0.33,0.14 12 粒", "可改 4 帧序列图")
    img = canvas(8, 8)
    ring(img, 4, 4, 3, C("#d8d8d8", 170), 1)
    px(img, 4, 2, C("#f4f4f0", 220))
    save(img, "fx/fx_puff.png", "命中/翻滚烟尘粒子", "autoload/fx.gd:88 _puff 0.85 白 6 粒", "")
    img = canvas(8, 8)
    for a in range(0, 360, 90):
        x, y = 4, 4
        for r in range(1, 4):
            px(img, x + int(math.cos(math.radians(a)) * r),
               y + int(math.sin(math.radians(a)) * r), C("#ffe86a", 240 - r * 40))
    px(img, 4, 4, C("#ffffff"))
    save(img, "fx/fx_muzzle.png", "枪口闪光", "当前无表现（weapon_rig.gd）", "")
    img = canvas(32, 32)
    ring(img, 16, 16, 13, C("#ff3a2e", 200), 2)
    disk(img, 16, 16, 11, C("#ff3a2e", 46))
    save(img, "fx/telegraph_circle.png", "圆形危险预警（Boss 拍击/爆炸范围）",
         "vine_colossus.gd:145 _fx_wedge 1.0,0.16,0.12 a0.35; delayed_blast.gd 延迟爆亦无预警(用 fuse_zone)", "运行时按半径缩放")
    img = canvas(32, 16)
    rect(img, 0, 0, 31, 15, C("#ff3a2e", 40))
    for x in range(0, 32, 4):
        vline(img, x, 0, 15, C("#ff3a2e", 110))
    save(img, "fx/telegraph_rect.png", "矩形危险预警（横扫/弹雨区）",
         "vine_colossus.gd:152/156 _fx_rect 1.0,0.16,0.12 a0.15-0.2", "运行时九宫格/平铺缩放")
    img = canvas(32, 32)
    disk(img, 16, 16, 12, C("#3fbf5a", 40))
    ring(img, 16, 16, 12, C("#3fbf5a", 200), 2)
    save(img, "fx/safe_zone.png", "Boss 安全区绿圈", "vine_colossus.gd:377 0.3,0.9,0.35 a0.4", "")
    for name, (cols, purpose) in {
        "cloud_blaze": ((C("#ff8a2e", 200), C("#ffe86a", 230), C("#e83a1e", 160)), "灼烧云（BLAZE 共鸣）"),
        "cloud_spore": ((C("#8ad84a", 190), C("#c8e88a", 210), C("#4a8a2e", 150)), "毒孢子云（蘑菇手/毒共鸣）"),
    }.items():
        img = canvas(16, 16)
        RNG2 = random.Random(7 if name.endswith("blaze") else 9)
        for _ in range(7):
            x, y = RNG2.randint(3, 12), RNG2.randint(3, 12)
            disk(img, x, y, RNG2.choice((2, 3)), RNG2.choice(cols))
        save(img, f"fx/{name}.png", purpose,
             "combat.spawn_blaze_cloud / status 组件（program 无贴图）", "")


# ---------------------------------------------------------------- ui
RARITY = {"common": "#cfd2d6", "uncommon": "#6ee86e", "rare": "#5ab0ff",
          "epic": "#b06cff", "legend": "#ffa64d"}


def gen_ui_frames():
    img = canvas(24, 24)
    rect(img, 0, 0, 23, 23, C("#12141ae0"))
    for i in range(24):
        px(img, i, 0, C("#5ab0ff"))
        px(img, i, 23, C("#5ab0ff"))
        px(img, 0, i, C("#5ab0ff"))
        px(img, 23, i, C("#5ab0ff"))
    for i in range(1, 23):
        px(img, i, 1, C("#2a3444"))
        px(img, i, 22, C("#2a3444"))
        px(img, 1, i, C("#2a3444"))
        px(img, 22, i, C("#2a3444"))
    save(img, "ui/panel_dark.png", "UI 深色面板（24x24 九宫格:边 6px）",
         "shop.gd:15 / drink_machine.gd:19 / events.gd:22 PANEL_BG 0.07,0.08,0.1 色块", "NinePatchRect")
    for r, hexes in RARITY.items():
        img = canvas(16, 16)
        c = C(hexes)
        for i in range(16):
            px(img, i, 0, c), px(img, i, 15, c), px(img, 0, i, c), px(img, 15, i, c)
        px(img, 1, 1, shade(c, 1.2))
        save(img, f"ui/frame_rarity_{r}.png", f"{r} 品质边框（16x16 九宫格:边 2px）",
             "shop.gd:18-19 / buff_pick.gd:9 / hud.gd:28-30 RARITY_COLORS", "卡背内衬半透明")
    for hero, pid in (("vanguard", "骑士·凛"), ("ranger", "游侠·苇")):
        src = Image.open(OUT / f"characters/hero_{hero}.png")
        img = canvas(32, 32)
        img.paste(src.resize((24, 24), Image.NEAREST), (4, 2))
        for i in range(32):
            px(img, i, 31, C("#2a3444"))
            px(img, i, 0, C(RARITY["rare"] if hero == "ranger" else RARITY["epic"]))
        save(img, f"ui/portrait_{hero}.png", f"{pid} 选人头像 32x32",
             "ui/hero_select.gd:82-112 卡片纯文字无头像", "选人卡左侧 24x24 显示区")


def gen_ui_icons():
    # HUD 心/盾/能/币
    img = canvas(8, 8)
    for y, (a, b) in enumerate(((1, 3), (0, 7), (0, 7), (1, 6), (2, 5), (3, 4))):
        hline(img, a, b, y + 1, C("#d2202e"))
    px(img, 1, 2, C("#ff8a94"))
    save(img, "ui/icon_heart_full.png", "HUD 红心(满)", "hud.gd:17-18 HEART_FULL 0.85,0.16,0.16 色块", "empty 用同形暗色 modulate")
    img = canvas(8, 8)
    for y, (a, b) in enumerate(((1, 3), (0, 7), (0, 7), (1, 6), (2, 5), (3, 4))):
        hline(img, a, b, y + 1, C("#3a2428"))
    save(img, "ui/icon_heart_empty.png", "HUD 红心(空)", "hud.gd:18 HEART_EMPTY 0.24,0.1,0.1", "")
    img = canvas(8, 8)
    for y, (a, b) in enumerate(((2, 5), (1, 6), (1, 6), (2, 5))):
        hline(img, a, b, y + 2, C("#7cc4ff"))
    px(img, 3, 3, C("#e2f4ff"))
    outline(img)
    save(img, "ui/icon_shield.png", "HUD 护盾", "hud.gd:20 SHIELD_COLOR 0.5,0.8,1.0 色块", "")
    img = canvas(8, 8)
    hline(img, 2, 5, 2, C("#5aa0ff"))
    hline(img, 1, 6, 3, C("#5aa0ff"))
    vline(img, 4, 3, 5, C("#c8e0ff"))
    hline(img, 2, 5, 6, C("#5aa0ff"))
    save(img, "ui/icon_energy.png", "HUD 蓝能", "hud.gd:21 ENERGY_COLOR 0.3,0.45,1.0 色块", "闪电造型")
    img = canvas(8, 8)
    disk(img, 4, 4, 3, C("#ffd94a"))
    ring(img, 4, 4, 3, C("#c8901c"), 1)
    save(img, "ui/icon_coin.png", "HUD 金币", "hud.gd:22 COIN_COLOR 1.0,0.85,0.3 色块", "")
    # 技能图标
    img = canvas(16, 16)
    rect(img, 5, 3, 10, 11, C("#8194ad"))
    rect(img, 6, 4, 9, 6, C("#b8c6d8"))
    disk(img, 7, 8, 1, C("#e2c04c"))
    rect(img, 12, 6, 14, 8, C("#ff8a2e"))
    px(img, 13, 5, C("#ffd94a"))
    outline(img)
    save(img, "ui/skill_rampage.png", "技能「狂潮」(骑士·凛): 双持齐射",
         "hud.gd:355-372 技能冷却环(纯圆弧)", "冷却环扣图标显示")
    img = canvas(16, 16)
    rect(img, 5, 3, 8, 9, C("#8a9ab8", 170))
    rect(img, 8, 6, 11, 12, C("#5a6a88", 230))
    px(img, 6, 4, C("#e2f4ff"))
    px(img, 9, 7, C("#e2f4ff"))
    for x, y in ((3, 2), (12, 13), (2, 12), (13, 3)):
        px(img, x, y, C("#b06cff"))
    outline(img)
    save(img, "ui/skill_shadowstep.png", "技能「影袭」(游侠·苇): 瞬步+必暴",
         "同上", "")
    img = canvas(12, 12)
    ring(img, 6, 6, 4, C("#5ae88a"), 2)
    px(img, 11, 4, C("#5ae88a"))
    px(img, 11, 6, C("#5ae88a"))
    px(img, 10, 3, C("#5ae88a"))
    save(img, "ui/icon_roll.png", "翻滚 CD 指示点图标", "hud.gd:25-26 DOT_READY/DOT_DIM 色点", "")


def gen_buff_icons():
    painters = {}

    def g(name):
        def deco(fn):
            painters[name] = fn
            return fn
        return deco

    @g("fire_enchant")
    def _(img):
        for i, w in enumerate((3, 5, 7, 5, 3)):
            hline(img, 6 - w // 2, 6 - w // 2 + w - 1, 3 + i, C("#ff6a2e"))
        px(img, 6, 5, C("#ffe86a"))
        px(img, 5, 6, C("#ffe86a"))

    @g("ice_enchant")
    def _(img):
        vline(img, 6, 2, 10, C("#8ae8ff"))
        hline(img, 2, 10, 6, C("#8ae8ff"))
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            px(img, 6 + dx * 2, 6 + dy * 2, C("#c8f4ff"))
            px(img, 6 + dx * 3, 6 + dy * 3, C("#8ae8ff"))

    @g("poison_enchant")
    def _(img):
        disk(img, 6, 6, 3, C("#8ad84a"))
        px(img, 5, 4, C("#d2f4a0"))
        px(img, 8, 3, C("#8ad84a"))
        px(img, 7, 2, C("#c8e88a"))

    @g("shock_enchant")
    def _(img):
        px(img, 7, 2, C("#e0b0ff"))
        hline(img, 5, 7, 4, C("#e0b0ff"))
        hline(img, 4, 6, 6, C("#c888ff"))
        hline(img, 5, 7, 8, C("#c888ff"))
        px(img, 5, 10, C("#e0b0ff"))
        hline(img, 6, 8, 9, C("#e0b0ff"))

    @g("bullet_speed")
    def _(img):
        for i in range(7):
            hline(img, 2 + i, 2 + i, 6 - max(0, 3 - i), C("#ffd94a"))
            hline(img, 2 + i, 2 + i, 6 + max(0, i - 3), C("#ffd94a"))
        hline(img, 1, 3, 3, C("#fff3b8"))
        hline(img, 1, 3, 9, C("#fff3b8"))

    @g("precision")
    def _(img):
        ring(img, 6, 6, 4, C("#e83a4a"), 1)
        vline(img, 6, 1, 3, C("#e83a4a"))
        vline(img, 6, 9, 11, C("#e83a4a"))
        hline(img, 1, 3, 6, C("#e83a4a"))
        hline(img, 9, 11, 6, C("#e83a4a"))

    @g("vigor")
    def _(img):
        for y, (a, b) in enumerate(((2, 5), (0, 11), (0, 11), (2, 9), (4, 7))):
            hline(img, a, b, y + 3, C("#e83a4a"))
        px(img, 2, 5, C("#ff8a94"))

    @g("shield_tune")
    def _(img):
        vline(img, 6, 2, 9, C("#7cc4ff"))
        for i, w in enumerate((7, 9, 9, 7)):
            hline(img, 6 - w // 2, 6 - w // 2 + w - 1, 3 + i, C("#7cc4ff"))
        px(img, 6, 5, C("#e2f4ff"))

    @g("swift_trigger")
    def _(img):
        rect(img, 4, 2, 8, 9, C("#8a8296"))
        rect(img, 5, 3, 7, 5, C("#544c60"))
        px(img, 9, 3, C("#ffd94a"))
        px(img, 10, 4, C("#ffd94a"))

    @g("deadly")
    def _(img):
        rect(img, 3, 2, 9, 7, C("#e8e4da"))
        rect(img, 4, 8, 8, 10, C("#c8c4ba"))
        rect(img, 4, 4, 5, 5, C("#20242c"))
        rect(img, 7, 4, 8, 5, C("#20242c"))
        for x in (5, 7):
            px(img, x, 10, C("#20242c"))

    @g("status_erode")
    def _(img):
        hline(img, 3, 9, 3, C("#8ad84a"))
        for i in range(6):
            px(img, 4 + i, 4 + i, C("#8ad84a"))
        disk(img, 4, 8, 2, C("#8ad84a"))
        disk(img, 8, 9, 1, C("#c8e88a"))

    @g("quick_charge")
    def _(img):
        rect(img, 3, 3, 9, 10, C("#5aa0ff"))
        rect(img, 5, 1, 7, 2, C("#5aa0ff"))
        hline(img, 6, 6, 5, C("#fff"))
        hline(img, 5, 6, 6, C("#fff"))
        hline(img, 6, 6, 7, C("#fff"))

    @g("energy_max")
    def _(img):
        rect(img, 2, 3, 10, 10, C("#3a86c8"))
        rect(img, 4, 1, 8, 2, C("#3a86c8"))
        hline(img, 5, 6, 5, C("#fff"))
        hline(img, 4, 5, 6, C("#fff"))
        hline(img, 5, 6, 7, C("#fff"))
        px(img, 8, 7, C("#fff"))

    @g("roll_master")
    def _(img):
        ring(img, 6, 6, 4, C("#5ae88a"), 2)
        px(img, 10, 3, C("#5ae88a"))
        px(img, 11, 4, C("#5ae88a"))
        px(img, 11, 6, C("#5ae88a"))

    @g("extra_projectiles")
    def _(img):
        for x in (3, 6, 9):
            disk(img, x, 6, 2, C("#ffd94a"))
            px(img, x, 5, C("#fff3b8"))

    @g("crit_detonate")
    def _(img):
        for a in range(0, 360, 45):
            for r in range(2, 5):
                px(img, 6 + int(math.cos(math.radians(a)) * r),
                   6 + int(math.sin(math.radians(a)) * r),
                   C("#ff8a2e") if r < 4 else C("#ffd94a"))
        px(img, 6, 6, C("#fff3b8"))

    buffs = json.load(open(ROOT / "data" / "buffs.json", encoding="utf-8"))
    for bid, row in buffs.items():
        img = canvas(12, 12)
        fn = painters.get(bid)
        if fn:
            fn(img)
        outline(img, C("#181420"))
        save(img, f"ui/buffs/{bid}.png",
             f"Buff 图标「{row.get('name', bid)}」",
             "hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字",
             "12x12 显示, 24x24 网格可后期重绘")
    # 元素附魔共用色: 4 个附魔 buff 已覆盖; 其余全部有 painter


def gen_drink_icons():
    drinks = json.load(open(ROOT / "data" / "drinks.json", encoding="utf-8"))
    liquid = {
        "shengming_soda": "#e83a4a", "nengliang_qishui": "#3a86c8",
        "jifeng_bohe": "#5ae88a", "yingyan_kafei": "#c88a4a",
        "chongneng_keke": "#8a5a3c", "qingyu_qipao": "#d8e4ec",
        "xingsui_tete": "#b06cff", "shenmi_hunhe": "#4ad8c8",
    }
    for did, row in drinks.items():
        img = canvas(12, 12)
        col = C(liquid.get(did, "#cfd2d6"))
        rect(img, 4, 1, 7, 2, C("#e8b8c0"))
        rect(img, 3, 3, 8, 10, C("#cfd8e0", 150))
        rect(img, 3, 6, 8, 10, col)
        px(img, 4, 7, shade(col, 1.35))
        px(img, 4, 4, C("#ffffff", 90))
        outline(img)
        save(img, f"ui/drinks/{did}.png", f"饮料图标「{row.get('name', did)}」",
             "core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT）", "瓶身色=效果色，重绘时保留辨识度")


ELEM_COL = {"fire": "#ff6a2e", "ice": "#8ae8ff", "poison": "#8ad84a",
            "shock": "#e0b0ff", "none": "#8a97ad"}
ICON_METAL, ICON_DARK, ICON_WOOD, ICON_ACC = C("#c8d0dc"), C("#7a8496"), C("#8a6a3c"), C("#e2c04c")


def _icon_sword(img, blade):
    for i in range(9):
        hline(img, 8 - i // 3, 12, 2 + i, blade)
    vline(img, 12, 3, 8, shade(blade, 1.25))
    hline(img, 2, 8, 11, ICON_ACC)
    rect(img, 3, 12, 4, 14, ICON_WOOD)


def _icon_gun_body(img, long_barrel, thick, scope):
    rect(img, 2, 8, 6, 13, ICON_WOOD)
    h = 8 if thick else 9
    rect(img, 5, h, 14 if long_barrel else 12, h + 1, ICON_METAL)
    rect(img, 5, h, 14 if long_barrel else 12, h, shade(ICON_METAL, 1.2))
    rect(img, 3, 7, 6, 9, ICON_DARK)
    if scope:
        rect(img, 7, 5, 10, 6, ICON_DARK)
        px(img, 7, 5, C("#8ad84a"))


ICON_TEMPLATES = {
    "pistol": lambda img, b: (_icon_gun_body(img, False, True, False), px(img, 13, 8, b)),
    "smg": lambda img, b: (_icon_gun_body(img, False, True, False),
                           rect(img, 7, 10, 8, 13, ICON_DARK), px(img, 13, 8, b)),
    "rifle": lambda img, b: (_icon_gun_body(img, True, False, True), px(img, 15, 8, b)),
    "shotgun": lambda img, b: (_icon_gun_body(img, True, True, False),
                               hline(img, 9, 11, 10, ICON_DARK), px(img, 15, 8, b)),
    "laser": lambda img, b: (_icon_gun_body(img, True, False, True),
                             rect(img, 12, 6, 13, 11, b), px(img, 15, 8, b)),
    "bow": lambda img, b: (vline(img, 5, 2, 13, C("#8a6a3c")),
                           px(img, 4, 3, C("#8a6a3c")), px(img, 6, 3, C("#8a6a3c")),
                           px(img, 4, 12, C("#8a6a3c")), px(img, 6, 12, C("#8a6a3c")),
                           vline(img, 5, 3, 12, C("#e8e4da")),
                           hline(img, 6, 12, 7, b), px(img, 12, 7, b)),
    "staff": lambda img, b: (vline(img, 4, 4, 14, ICON_WOOD),
                             px(img, 4, 3, ICON_WOOD),
                             disk(img, 10, 4, 2, b), px(img, 10, 3, shade(b, 1.4))),
    "melee": lambda img, b: _icon_sword(img, b),
}


# 注（m2-t21）：武器图标/手持图唯一出口已移 gen_placeholder_art_m2.gen_weapons_m2
# （data/weapons.json 115 行数据驱动）——本节 ICON_TEMPLATES 与 hh_* 画笔模板保留，
# 供 M2 批次经 base 注入复用；M1 侧不再单独出武器图（防同文件双写）。


HH_METAL, HH_DARK, HH_WOOD, HH_WOOD_L = C("#c8d0dc"), C("#7a8496"), C("#8a6a3c"), C("#a8854e")

def hh_pistol(img, elem, acc):
    rect(img, 4, 6, 12, 8, HH_METAL)
    hline(img, 4, 12, 6, shade(HH_METAL, 1.2))
    px(img, 13, 7, HH_DARK), px(img, 13, 8, HH_DARK)
    rect(img, 4, 9, 6, 12, HH_WOOD)
    px(img, 7, 9, HH_DARK)
    px(img, 11, 7, elem)
    px(img, 6, 7, acc)

def hh_smg(img, elem, acc):
    rect(img, 3, 6, 13, 9, HH_METAL)
    hline(img, 3, 13, 6, shade(HH_METAL, 1.2))
    rect(img, 13, 7, 14, 8, HH_DARK)
    rect(img, 7, 10, 8, 12, HH_DARK)
    rect(img, 4, 10, 5, 12, HH_WOOD)
    px(img, 2, 7, HH_DARK), px(img, 2, 8, HH_DARK)
    px(img, 12, 8, elem)
    px(img, 6, 7, acc)

def hh_rifle(img, elem, acc):
    rect(img, 1, 7, 3, 9, HH_WOOD)
    rect(img, 4, 6, 10, 9, HH_METAL)
    hline(img, 4, 10, 6, shade(HH_METAL, 1.2))
    rect(img, 10, 7, 15, 8, HH_DARK)
    rect(img, 6, 4, 9, 5, HH_DARK)
    px(img, 6, 4, acc)
    rect(img, 4, 10, 5, 12, HH_WOOD)
    px(img, 9, 7, elem)

def hh_shotgun(img, elem, acc):
    rect(img, 1, 7, 4, 9, HH_WOOD)
    rect(img, 4, 6, 15, 8, HH_METAL)
    hline(img, 4, 15, 6, shade(HH_METAL, 1.2))
    rect(img, 8, 9, 11, 10, HH_WOOD)
    px(img, 14, 7, elem)
    px(img, 6, 7, acc)

def hh_laser(img, elem, acc):
    rect(img, 1, 7, 3, 9, HH_DARK)
    rect(img, 4, 6, 10, 9, HH_METAL)
    rect(img, 11, 6, 13, 9, elem)
    px(img, 12, 7, shade(elem, 1.4))
    rect(img, 13, 7, 14, 8, shade(elem, 0.8))
    px(img, 15, 7, C("#ffffff"))
    px(img, 15, 8, C("#ffffff"))
    rect(img, 5, 10, 6, 12, HH_DARK)
    px(img, 6, 7, acc)

def hh_bow(img, elem, acc):
    # 握把在左(持握点)，弓臂向右上/右下张开，弦在右竖线，箭穿中线指向右
    rect(img, 3, 7, 5, 9, HH_WOOD)
    upper = [(5, 7), (6, 6), (8, 5), (10, 4), (12, 3)]
    for x, y in upper + [(x, 16 - y) for x, y in upper]:
        px(img, x, y, HH_WOOD_L)
        px(img, x, y + (1 if y < 8 else -1), HH_WOOD)
    vline(img, 12, 3, 13, C("#e8e4da"))
    hline(img, 5, 13, 8, C("#c8b08a"))
    px(img, 14, 8, elem)
    px(img, 4, 8, acc)

def hh_staff(img, elem, acc):
    hline(img, 3, 11, 8, HH_WOOD)
    px(img, 3, 8, shade(HH_WOOD, 1.2))
    disk(img, 13, 8, 2, elem)
    px(img, 12, 7, shade(elem, 1.4))
    ring(img, 13, 8, 2, shade(elem, 0.7), 1)
    px(img, 5, 7, ICON_ACC), px(img, 5, 9, ICON_ACC)
    px(img, 7, 8, acc)

def hh_sword(img, elem, acc):
    rect(img, 1, 7, 3, 9, HH_WOOD)
    hline(img, 3, 5, 6, ICON_ACC), hline(img, 3, 5, 10, ICON_ACC)
    vline(img, 4, 6, 10, ICON_ACC)
    blade = elem if elem != C(ELEM_COL["none"]) else HH_METAL
    rect(img, 5, 7, 13, 8, blade)
    hline(img, 5, 13, 7, shade(blade, 1.3))
    px(img, 14, 7, blade), px(img, 14, 8, shade(blade, 0.8))
    px(img, 2, 8, acc)

def hh_dagger(img, elem, acc):
    rect(img, 2, 7, 3, 9, HH_WOOD)
    vline(img, 4, 6, 10, ICON_ACC)
    blade = elem if elem != C(ELEM_COL["none"]) else HH_METAL
    rect(img, 5, 7, 10, 8, blade)
    hline(img, 5, 10, 7, shade(blade, 1.3))
    px(img, 11, 7, blade), px(img, 11, 8, shade(blade, 0.8))
    px(img, 3, 8, acc)

templates_hh = {
    "pistol": hh_pistol, "smg": hh_smg, "rifle": hh_rifle, "shotgun": hh_shotgun,
    "laser": hh_laser, "bow": hh_bow, "staff": hh_staff,
    "melee": hh_sword,  # 双匕按 is_melee+短刃特判
}

# 注（m2-t21）：手持武器外观同图标——唯一出口在 gen_placeholder_art_m2.gen_weapons_m2；
# 本节 templates_hh/hh_dagger/hh_pistol 画笔保留供 M2 批次注入复用。


def gen_batch2():
    """二次排查补漏（客人变体/护盾精灵/状态与词缀角标/Boss条/触屏/小地图/被动/升级技能/准星/应用图标）。"""
    # 客人变体：GUEST_COLORS elite(金)/miniboss(红) 染色 → 直接出变体图（或运行时 modulate）
    img = paint_charger(C("#c8a028"), C("#e2c04c"), C("#7a5c14"), C("#fff3b8"))
    outline(img)
    save(img, "enemies/vine_charger_elite.png", "客人「精英·藤蔓冲锋者」（金色变体）",
         "floor_scene.gd:52-56/622-624 GUEST_COLORS.elite 1.0,0.82,0.25 染色色块",
         "亦可直接用 base 图 + modulate 金色")
    img = paint_charger(C("#a83232"), C("#c85050"), C("#5c1a1a"), C("#f4d8d8"))
    outline(img)
    save(img, "enemies/vine_charger_miniboss.png", "客人「垒主·藤蔓冲锋者」（红色变体）",
         "floor_scene.gd:52-56/622-624 GUEST_COLORS.miniboss 0.85,0.25,0.2 染色色块", "")
    # 护盾精灵（当前完全隐形）
    img = canvas(16, 16)
    disk(img, 8, 8, 5, C("#8ac8ff", 220))
    disk(img, 8, 9, 3, C("#c8e8ff"))
    eyes(img, 8, 7, gap=2, pupil=C("#1c3a5c"))
    vline(img, 8, 2, 3, C("#c8e8ff"))
    ring(img, 8, 8, 5, C("#5aa8e8", 230), 1)
    save(img, "fx/shield_spirit.png", "护盾精灵（精灵像供奉物，跟随玩家拦弹 3 次）",
         "core/interact/shield_spirit.gd 纯 Node2D 无任何外观（隐形）; floor_scene.gd:437 挂载",
         "拦截瞬间可加白闪/缩放弹跳")
    # 敌人状态角标 8x8（当前状态无任何视觉表现）
    def badge(bg_hex):
        img = canvas(8, 8)
        disk(img, 4, 4, 3, C(bg_hex))
        return img
    img = badge("#5c2a1c")
    for i, w in enumerate((2, 4, 2, 4, 2)):
        hline(img, 4 - w // 2, 4 - w // 2 + w - 1, 2 + i, C("#ff8a2e") if i % 2 == 0 else C("#ffd94a"))
    save(img, "ui/status_burn.png", "敌人状态角标：灼烧", "core/combat/status_component.gd DoT 无视觉表现", "悬浮敌人头顶")
    img = badge("#1c3a5c")
    vline(img, 4, 1, 7, C("#b8ecff"))
    hline(img, 1, 7, 4, C("#b8ecff"))
    for dx, dy in ((2, 2), (-2, 2), (2, -2), (-2, -2)):
        px(img, 4 + dx, 4 + dy, C("#e2f4ff"))
    save(img, "ui/status_frozen.png", "敌人状态角标：冰冻", "status_component.gd is_frozen 无视觉", "")
    img = badge("#3c2a5c")
    px(img, 5, 1, C("#e0b0ff"))
    hline(img, 3, 5, 3, C("#e0b0ff"))
    hline(img, 2, 4, 5, C("#c888ff"))
    px(img, 4, 6, C("#e0b0ff"))
    save(img, "ui/status_shock.png", "敌人状态角标：麻痹", "status_component.gd SHOCK/眩晕 无视觉", "")
    img = badge("#2a4a1c")
    disk(img, 4, 5, 2, C("#8ad84a"))
    px(img, 4, 1, C("#c8e88a"))
    px(img, 4, 2, C("#c8e88a"))
    save(img, "ui/status_poison.png", "敌人状态角标：中毒", "status_component.gd 毒 DoT 无视觉", "")
    # 精英词缀角标 12x12（EliteAffix.AFFIXES 六种，无任何标识）
    def affix_base():
        img = canvas(12, 12)
        disk(img, 6, 6, 5, C("#20242c", 210))
        ring(img, 6, 6, 5, C("#e2c04c", 230), 1)
        return img
    img = affix_base()
    for dx in (-2, 1):
        for i in range(4):
            hline(img, 4 + dx + i, 4 + dx + i, 4 - i, C("#8ae86a"))
            hline(img, 4 + dx + i, 4 + dx + i, 4 + i, C("#8ae86a"))
            px(img, 4 + dx + i + 1, 4, C("#c8ffb0"))
    save(img, "ui/affix_swift.png", "词缀角标：迅捷(×1.3 速度)", "core/enemies/elites/elite_affix.gd:11 AFFIXES，全部无视觉标识", "悬浮血条旁")
    img = affix_base()
    rect(img, 4, 3, 8, 9, C("#8a97ad"))
    rect(img, 5, 4, 7, 5, C("#c8d0dc"))
    px(img, 6, 7, C("#5ab0ff"))
    save(img, "ui/affix_armored.png", "词缀角标：坚甲(HP×3)", "elite_affix.gd ARMORED_HP_MULT", "")
    img = affix_base()
    disk(img, 4, 6, 2, C("#6ee86e"))
    disk(img, 8, 6, 2, C("#6ee86e"))
    px(img, 6, 6, C("#c8ffc8"))
    save(img, "ui/affix_splitter.png", "词缀角标：分裂(死亡一分为二)", "elite_affix.gd split_on_death", "")
    img = affix_base()
    px(img, 4, 3, C("#f4f4f0"))
    px(img, 8, 3, C("#f4f4f0"))
    vline(img, 4, 4, 5, C("#f4f4f0"))
    vline(img, 8, 4, 5, C("#f4f4f0"))
    disk(img, 6, 8, 2, C("#c8283c"))
    save(img, "ui/affix_leech.png", "词缀角标：虹吸(接触吸血)", "elite_affix.gd leech", "")
    img = affix_base()
    for x in (3, 6, 9):
        for i in range(5):
            px(img, x, 9 - i, C("#ff8a2e") if i < 4 else C("#ffd94a"))
    save(img, "ui/affix_barrage.png", "词缀角标：弹幕(+1 弹)", "elite_affix.gd barrage_extra", "")
    img = affix_base()
    for a in range(0, 360, 60):
        for r in range(2, 5):
            px(img, 6 + int(math.cos(math.radians(a)) * r), 6 + int(math.sin(math.radians(a)) * r), C("#ff4a2e"))
    px(img, 6, 6, C("#ffd94a"))
    save(img, "ui/affix_berserk.png", "词缀角标：狂暴(<50% 血攻速×1.3)", "elite_affix.gd has_berserk / enemy_base.gd:231", "")
    # Boss 血条（当前游戏无 Boss 血条 UI）
    img = canvas(96, 12)
    rect(img, 0, 0, 95, 11, C("#12141ae0"))
    for i in range(96):
        px(img, i, 0, C("#e2c04c")), px(img, i, 11, C("#e2c04c"))
        px(img, 0, i % 12, C("#e2c04c")), px(img, 95, i % 12, C("#e2c04c"))
    save(img, "ui/boss_bar_frame.png", "Boss 血条框（96x12, 运行时缩放）",
         "无（游戏当前没有 Boss 血条，boss_base.gd 仅白闪）", "NinePatch/TextureProgressBar")
    img = canvas(96, 12)
    rect(img, 2, 2, 93, 9, C("#3fae4a"))
    rect(img, 2, 2, 93, 4, C("#6ee86e"))
    save(img, "ui/boss_bar_fill.png", "Boss 血条填充", "同上", "TextureProgressBar progress 贴图")
    # 触屏按钮图标（现为纯文字按钮）
    img = canvas(16, 16)
    for a in range(0, 360, 45):
        for r in range(2, 6):
            px(img, 8 + int(math.cos(math.radians(a)) * r), 8 + int(math.sin(math.radians(a)) * r),
               C("#b06cff") if r < 5 else C("#e0d0ff"))
    px(img, 8, 8, C("#f4ecff"))
    outline(img)
    save(img, "ui/btn_skill.png", "触屏按钮：技能", "ui/touch_controls.tscn:41-54 SkillButton 纯文字「技能」", "Button.icon")
    img = canvas(16, 16)
    ring(img, 8, 8, 5, C("#5ae88a"), 2)
    px(img, 13, 5, C("#5ae88a"))
    px(img, 14, 6, C("#5ae88a"))
    px(img, 13, 7, C("#5ae88a"))
    outline(img)
    save(img, "ui/btn_roll.png", "触屏按钮：翻滚", "touch_controls.tscn:56-69 RollButton 文字「翻滚」", "")
    img = canvas(16, 16)
    for y, c in ((3, C("#5ab0ff")), (11, C("#e2c04c"))):
        hline(img, 4, 11, y, c)
        px(img, 3, y + 1, c), px(img, 12, y + 1, c)
        px(img, 3, y + 2, c), px(img, 12, y + 2, c)
        hline(img, 4, 11, y + 3, c)
    px(img, 8, 5, C("#c8e0ff"))
    outline(img)
    save(img, "ui/btn_switch.png", "触屏按钮：切枪", "touch_controls.tscn:71-81 SwitchButton 文字「切枪」", "")
    img = canvas(16, 16)
    disk(img, 8, 7, 5, C("#ffd94a"))
    rect(img, 7, 4, 9, 8, C("#5c4514"))
    rect(img, 7, 10, 9, 11, C("#5c4514"))
    outline(img)
    save(img, "ui/btn_interact.png", "触屏按钮：交互", "touch_controls.tscn:83-93 InteractButton 文字「交互」", "叹号气泡造型")
    # 小地图房间图标（游戏暂无小地图，预留 8 类型）
    mm = {
        "combat": ("#8a97ad", "普通战斗房"), "start": ("#6ee86e", "出生房"),
        "boss": ("#e83a4a", "Boss 房"), "treasure": ("#e2c04c", "宝物房"),
        "shop": ("#ffa64d", "商店房"), "event": ("#b06cff", "事件房"),
        "elite": ("#ffd94a", "精英(嘉宾)房"), "miniboss": ("#c85050", "小 Boss 房"),
    }
    for t, (hexes, label) in mm.items():
        img = canvas(8, 8)
        rect(img, 1, 1, 6, 6, C(hexes))
        px(img, 1, 1, shade(C(hexes), 1.3))
        px(img, 6, 6, shade(C(hexes), 0.7))
        save(img, f"ui/minimap/{t}.png", f"小地图图标：{label}（暂无小地图，预留）",
             "floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集", "8x8, 间距 1px 显示")
    # 英雄被动图标
    img = canvas(12, 12)
    for i, w in enumerate((6, 8, 8, 6)):
        hline(img, 6 - w // 2, 6 - w // 2 + w - 1, 3 + i, C("#8194ad"))
    rect(img, 5, 2, 7, 3, C("#b8c6d8"))
    for a in (150, 210, 30, 330):
        px(img, 6 + int(math.cos(math.radians(a)) * 5), 6 + int(math.sin(math.radians(a)) * 5), C("#ffd94a"))
    outline(img)
    save(img, "ui/passive_defiance.png", "被动图标：坚守（骑士·凛, 破盾反伤）",
         "data/heroes.json passive_id=defiance; player.gd:167 _on_shield_broken", "选人卡/局内 HUD 预留")
    img = canvas(12, 12)
    disk(img, 6, 6, 4, C("#e2c04c"))
    disk(img, 6, 6, 2, C("#5c4514"))
    px(img, 6, 6, C("#f4f4f0"))
    px(img, 1, 1, C("#8ae8ff"))
    px(img, 11, 1, C("#8ae8ff"))
    outline(img)
    save(img, "ui/passive_hawkeye.png", "被动图标：鹰眼（游侠·苇）",
         "data/heroes.json passive_id=hawk_eye", "")
    # 技能升级版（金+角标）
    for base, plus in (("ui/skill_rampage.png", "ui/skill_rampage_plus.png"),
                       ("ui/skill_shadowstep.png", "ui/skill_shadowstep_plus.png")):
        img = Image.open(OUT / base).copy()
        rect(img, 10, 10, 15, 15, C("#e2c04c"))
        vline(img, 12, 11, 14, C("#5c4514"))
        hline(img, 11, 13, 12, C("#5c4514"))
        hline(img, 11, 13, 14, C("#5c4514"))
        save(img, plus, "技能升级版图标（" + ("狂潮+" if "rampage" in plus else "影袭+") + "）",
             "data/heroes.json upgraded 字段; player.gd:14 RAMPAGE_DR 狂潮(升级)减伤", "右下金+角标")
    # 准星（自动瞄准暂无表现）
    img = canvas(8, 8)
    vline(img, 4, 0, 2, C("#f4f4f0", 220))
    vline(img, 4, 5, 7, C("#f4f4f0", 220))
    hline(img, 0, 2, 4, C("#f4f4f0", 220))
    hline(img, 5, 7, 4, C("#f4f4f0", 220))
    px(img, 4, 4, C("#ff6a55"))
    save(img, "fx/reticle.png", "瞄准准星（自动瞄准/手柄瞄准表现预留）",
         "core/player/auto_aim.gd 纯逻辑无表现", "触屏/手柄模式下显示")
    # 像素版应用图标（icon.svg 已是自绘星形，此为像素风格备选）
    img = canvas(128, 128)
    p = 8  # 像素粒度
    def bigrect(x0, y0, x1, y1, c):
        rect(img, x0 * p, y0 * p, x1 * p + p - 1, y1 * p + p - 1, c)
    for y in range(16):
        for x in range(16):
            edge = x in (0, 15) or y in (0, 15)
            corner = (x in (0, 1) or x in (14, 15)) and (y in (0, 1) or y in (14, 15))
            if not corner:
                bigrect(x, y, x, y, C("#1a2030") if edge else C("#232c44"))
    star = [(7, 1), (8, 1), (7, 2), (8, 2), (3, 5), (4, 5), (5, 5), (6, 5), (9, 5), (10, 5), (11, 5), (12, 5),
            (2, 6), (13, 6), (2, 7), (13, 7), (4, 8), (5, 8), (6, 8), (9, 8), (10, 8), (11, 8),
            (4, 12), (5, 12), (6, 12), (9, 12), (10, 12), (11, 12), (7, 9), (8, 9), (7, 10), (8, 10),
            (7, 13), (8, 13), (7, 14), (8, 14)]
    for x, y in star:
        bigrect(x, y, x, y, C("#f2e0b0"))
    for x, y in [(7, 3), (8, 3), (7, 4), (8, 4), (6, 6), (9, 6), (7, 7), (8, 7)]:
        bigrect(x, y, x, y, C("#fff3c8"))
    # 流星
    for i, (x, y) in enumerate([(12, 2), (11, 3), (10, 4)]):
        bigrect(x, y, x, y, C("#8ae8ff", 255 - i * 60))
    save(img, "ui/icon_app.png", "应用图标（像素风备选; 根目录 icon.svg 为现有自绘星形版）",
         "icon.svg（项目窗口图标，已是自定义星形非 Godot 默认）", "替换时同步改 project.godot config/icon")


def gen_batch3():
    """三次排查补漏（M1 证据图复查）：雕像四属性变体/自爆引信圈/黑市标识与商贩。"""
    # 四尊雕像（shrine.gd:14-15 KINDS；floor_scene.gd:768-772 四尊同房）
    def shrine_variant(accent, glyph):
        img = canvas(16, 18)
        rect(img, 2, 13, 13, 15, C("#6b5029"))
        rect(img, 4, 4, 11, 12, C("#c8a03c"))
        rect(img, 5, 2, 10, 4, C("#e2c04c"))
        rect(img, 6, 6, 9, 8, C("#8a6a1c"))
        # 属性披肩/底座描边
        rect(img, 4, 9, 11, 12, accent)
        rect(img, 2, 15, 13, 15, shade(accent, 0.8))
        # 属性徽记（身部 4x4 区域内）
        for gx, gy in glyph:
            px(img, gx, gy, C("#fff3d8"))
        outline(img)
        return img
    save(shrine_variant(C("#c8283c"), [(7, 7), (8, 7), (7, 8), (8, 8)]),
         "tiles/shrine_zhanshen.png", "战神像（攻击力 +25% 10s）",
         "core/interact/shrine.gd:14 KINDS=zhanshen; floor_scene.gd:768-772 四尊同房均为金色色块",
         "披肩/底座=属性色, 身部白点=徽记")
    save(shrine_variant(C("#3a86c8"), [(6, 7), (9, 7), (6, 8), (9, 8), (7, 6), (8, 6), (7, 9), (8, 9)]),
         "tiles/shrine_jingling.png", "精灵像（召唤护盾精灵拦弹 3 次）",
         "shrine.gd jingling; core/interact/shield_spirit.gd", "")
    save(shrine_variant(C("#3fae4a"), [(7, 6), (8, 6), (6, 7), (9, 7), (7, 8), (8, 8)]),
         "tiles/shrine_fengshen.png", "风神像（攻速/移速 +30% 5s）", "shrine.gd fengshen", "")
    save(shrine_variant(C("#8a4ac8"), [(7, 5), (7, 9), (5, 7), (9, 7), (6, 6), (8, 8), (8, 6), (6, 8)]),
         "tiles/shrine_xingsui.png", "星髓像（武器临时元素附魔 60s）", "shrine.gd xingsui; weapon_rig.gd temporary_enchant", "")
    # 自爆引信预警圈（延迟爆目前完全无视觉）
    img = canvas(48, 48)
    disk(img, 24, 24, 21, C("#ff8a2e", 38))
    ring(img, 24, 24, 21, C("#ff8a2e", 190), 2)
    ring(img, 24, 24, 14, C("#ffd94a", 120), 1)
    for a in range(0, 360, 90):
        x = 24 + int(math.cos(math.radians(a)) * 17)
        y = 24 + int(math.sin(math.radians(a)) * 17)
        px(img, x, y, C("#ffd94a", 200))
    save(img, "fx/fuse_zone.png", "自爆引信预警圈（苦力虫 40px / 自爆王虫 72px，倒计时脉冲）",
         "core/enemies/elites/delayed_blast.gd 完全无视觉; enemy_base.gd:192 _spawn_delayed_blast",
         "运行时按 aoe_radius 缩放, 倒计时闪烁 modulate")
    # 黑市标识 + 商贩（黑市变体现在仅标题文字）
    img = canvas(16, 16)
    disk(img, 8, 8, 5, C("#2a2438"))
    ring(img, 8, 8, 5, C("#b06cff"), 1)
    px(img, 6, 6, C("#e2c04c")), px(img, 10, 6, C("#e2c04c"))
    rect(img, 6, 10, 10, 11, C("#e2c04c"))
    px(img, 8, 8, C("#b06cff"))
    save(img, "ui/icon_blackmarket.png", "黑市标识（武器价 ×1.8, UI 标题旁）",
         "core/interact/shop.gd:14/30 BLACK_TITLE 黑市商人(纯文字), floor_scene.gd BLACK_SHOP_CHANCE", "")
    img = canvas(16, 18)
    rect(img, 5, 12, 6, 14, C("#3a3444"))
    rect(img, 9, 12, 10, 14, C("#3a3444"))
    rect(img, 4, 6, 11, 12, C("#7a5230"))
    rect(img, 4, 6, 11, 7, C("#9a6a40"))
    rect(img, 4, 1, 11, 6, C("#e8dcc0"))
    rect(img, 3, 0, 12, 2, C("#8a6a3c"))
    eyes(img, 8, 3, gap=2)
    px(img, 8, 5, C("#c9a88a"))
    outline(img)
    save(img, "tiles/shopkeeper.png", "商人 NPC（商店房形象预留; 现商店仅弹 UI 面板）",
         "core/interact/shop.gd + shop.tscn（无世界内形象）", "黑市款换紫袍+兜帽")
    img = canvas(16, 18)
    rect(img, 5, 12, 6, 14, C("#2a2438"))
    rect(img, 9, 12, 10, 14, C("#2a2438"))
    rect(img, 4, 6, 11, 12, C("#4a3a6a"))
    rect(img, 4, 6, 11, 7, C("#5f4a88"))
    rect(img, 4, 1, 11, 6, C("#3a3444"))
    rect(img, 3, 0, 12, 2, C("#b06cff"))
    eyes(img, 8, 4, gap=2, white=C("#ffd94a"), pupil=C("#5c4514"))
    outline(img)
    save(img, "tiles/shopkeeper_black.png", "黑市商人 NPC（兜帽遮面）",
         "shop.gd black 变体（标题/价格区分, 无形象）", "")


def gen_misc():
    # 虚拟摇杆
    img = canvas(48, 48)
    disk(img, 24, 24, 21, C("#ffffff", 30))
    ring(img, 24, 24, 21, C("#ffffff", 90), 2)
    save(img, "ui/joystick_base.png", "虚拟摇杆底盘",
         "ui/virtual_joystick.gd:97-101 draw_circle a0.12 + arc a0.35", "")
    img = canvas(24, 24)
    disk(img, 12, 12, 9, C("#ffffff", 140))
    disk(img, 12, 12, 6, C("#ffffff", 200))
    save(img, "ui/joystick_nub.png", "虚拟摇杆摇杆头", "virtual_joystick.gd:101 a0.55 圆", "")
    # 低血 vignette
    img = canvas(96, 96)
    for y in range(96):
        for x in range(96):
            d = math.hypot(x - 48, y - 48) / 48.0
            a = int(max(0.0, d - 0.45) / 0.55 * 110)
            if a > 0:
                img.putpixel((x, y), (200, 10, 16, a))
    save(img, "ui/vignette_lowhp.png", "低血红屏 vignette（中心透明）",
         "hud.gd:184 vignette 0.75,0.05,0.05 a0.12 色块", "全屏拉伸, modulate 控制强度")
    # 标题 logo
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 40)
    except OSError:
        font = ImageFont.load_default()
    img = canvas(240, 64)
    d = ImageDraw.Draw(img)
    text = "星陨地牢"
    for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2), (-2, -2), (2, 2), (-2, 2), (2, -2)):
        d.text((120 + dx, 28 + dy), text, font=font, fill=(20, 14, 30, 255), anchor="mm")
    d.text((118, 26), text, font=font, fill=(242, 224, 176, 255), anchor="mm")
    for sx, sy in ((30, 12), (208, 46), (52, 50)):
        d.ellipse((sx - 2, sy - 2, sx + 2, sy + 2), fill=(255, 240, 180, 220))
    save(img, "ui/logo_title.png", "主菜单标题 LOGO 占位（系统字体渲染）",
         "ui/main_menu.tscn 标题为纯 Label", "正式版换像素字体 LOGO（见 MANIFEST 待采购项）")
    # 白像素工具图
    img = canvas(4, 4)
    rect(img, 0, 0, 3, 3, C("#ffffff"))
    save(img, "ui/white.png", "纯白 4x4 工具图（modulate 调色用）",
         "多处 ColorRect 临时替代", "")


def write_manifest():
    lines = [
        "# 占位素材清单（art/generated）",
        "",
        "> 由 `tools/gen_placeholder_art.py` 自动生成并维护，重跑脚本即整体再生（确定性随机种子 42）。",
        "> 当前项目**没有任何外部贴图**：全部画面为程序化纯色 Polygon2D/ColorRect（见各素材「现状」列）。",
        "> 本目录素材为**像素风占位**：①先让画面脱离纯色块 ②为外包/自绘提供尺寸与风格锚点。",
        "> 接线方式：把对应代码点的 Polygon2D 换成 `Sprite2D`（保留节点名 `Sprite`，受击白闪 fx.gd 按名查找），",
        "> 像素材质需在导入设置开 `filter=nearest`（或项目默认纹理过滤改 Nearest）。",
        "",
        "图例：尺寸为像素；「现状」= 当前程序化表现的代码位置。",
        "",
        "| 素材 | 尺寸 | 用途 | 现状（代码替换点） | 替换指引 |",
        "|---|---|---|---|---|",
    ]
    for rel, purpose, current, note in SPEC:
        p = OUT / rel
        size = f"{Image.open(p).width}x{Image.open(p).height}"
        note_col = note if note else "—"
        lines.append(f"| `{rel}` | {size} | {purpose} | {current} | {note_col} |")
    lines += [
        "",
        "## 缺口与待采购（无法程序生成，需外部获取/委托）",
        "",
        "| 项 | 说明 | 建议 |",
        "|---|---|---|",
        "| 像素中文字体 | 全 UI 伤害数字/菜单/对话用默认字体，无像素风格 | 开源可选：缝合怪像素字体 Fusion Pixel Font（OFL）、Zpix（个人免费）；落位 `art/fonts/` |",
        "| 四向行走动画 | **m2-t17 已程序化交付**：`characters/hero_<id>_sheet.png`（4 向 x idle+walk×3, 16px/帧），player.gd 移动方向自动切换 | 正式素材可按此帧表布局连锁重绘；敌人 2 帧动画亦已交付（m2-t21 `enemies/<id>_sheet.png`） |",
        "| 敌人受击/死亡动画 | 目前仅白闪+爆粒子 | 每敌 2-4 帧即可显著提升手感 |",
        "| 雕像四 kinds 精绘 | 通用底 + 4 属性变体已备（shrine_*.png），披肩/徽记方案区分 | 正式素材按变体配色委托精绘即可 |",
        "| 地图整块背景装饰 | 墙沿/悬挂物/裂纹大图 | 可后置，优先级低 |",
        "| 正式 LOGO | 占位为系统字体渲染 | 像素字重绘或外包 |",
        "",
        "## 二次排查记录（无需出图/配置项）",
        "",
        "- **启动 Splash**：project.godot 未配置 boot_splash，现显示 Godot 默认闪屏 → 建议配置 `application/boot_splash/bg_color=#12141a`（纯配置，非素材）。",
        "- **训练房**（training_room.gd）：木桩/拾取靶为开发用场景，复用 `tiles/prop_crate.png` 与 `pickups/*` 即可，不单独出图。",
        "- **交互浮标**（ui/interact_prompt.gd）：纯文字 Label（action_label），如需键位图标可后补 `ui/key_e.png`。",
        "- **事件面板**（core/interact/events.gd）：纯文字选项卡，暂无图标需求；若做事件插画再补。",
        "- **商店**（shop_logic.gd）：售卖品为 武器/饮料/红心/蓝能 → 图标已全部覆盖（ui/weapons、ui/drinks、pickups/heart、pickups/energy）。",
        "- **武器手持外观**：当前武器只在 HUD/商店以图标出现，手上无武器贴图（元气骑士有持枪图）→ **已备好** `weapons/*.png` 40 张（16x16 朝右、持握点(4,8)、接线约定见清单行）；是否接入由后续决定。",
        "- **小地图**：游戏暂无小地图，`ui/minimap/*` 8 类型图标已按 floor_flow.gd 房间类型全集预留。",
        "- **应用图标**：icon.svg 已是自定义星形（非 Godot 默认）；`ui/icon_app.png` 为像素风备选。",
        "",
        "## 三次排查记录（M1 证据图 + 剩余文件复查）",
        "",
        "- 方法：逐张复查 `docs/superpowers/reports/m1-evidence/` 10 张实机截图，并补读黑市/延迟爆/死亡结算/门动画等未排查文件。",
        "- **雕像四属性变体已补**：`tiles/shrine_{zhanshen,jingling,fengshen,xingsui}.png`（M1 商店房四尊实景）。",
        "- **延迟爆无预警已补**：`fx/fuse_zone.png`——`delayed_blast.gd` 此前零绘制，72px 爆炸范围对玩家不可见。",
        "- **黑市视觉区分已补**：`ui/icon_blackmarket.png` + `tiles/shopkeeper{,_black}.png`（此前仅标题文字「黑市商人」+ 价格 ×1.8）。",
        "- m1-02 截图中的黄色弧点为子弹流（PLAYER_BULLET_COLOR），非挥砍视觉；melee.gd 仍无挥砍特效，`fx/fx_slash.png` 接线后为新增表现。",
        "- 门动画（floor_scene.gd:378-384 + fx/door_anim.gd）用 `tiles/door_*.png` 即可；死亡结算/事件面板/运行根提示均为纯文字，无素材需求。",
        "- 结论：M1 全部实机内容（含证据图 10 张）与代码视觉点至此均已建档，无未覆盖项。",
        "",
        "## 生成参数",
        "",
        "- 脚本：`tools/gen_placeholder_art.py`（M1 批次+公共库，自动串联 `tools/gen_placeholder_art_m2.py`）",
        "- M2 批次（附录 A/B/C 驱动）：武器 115 双套图/敌人 40 单帧+2 帧动画表/Boss 6/英雄 6 全家桶/增益 36/三生态地块/事件设施/局外 UI。",
        "- **武器/敌人 id 均以 data/*.json 为唯一权威**（m2-t21 收编，数据驱动出图）；M2 Boss slug 已对齐 data/enemies.json 行 id（m4p-u2 收编：prism_golem/frost_widow 原附录 E 暂定名 crystal_golem/frost_spider_mother）。",
        "- Python 3.12 + Pillow 12.3；随机种子固定 42，输出可复现；全量再生=先生成后按本清单清理陈旧（失败不毁库）。",
        "- 联络表：`_preview.png`（4x 放大，人工检查用，勿在游戏内引用）。",
    ]
    (OUT / "MANIFEST.md").write_text("\n".join(lines), encoding="utf-8")


def write_preview():
    cell, scale, cols = 40, 4, 10
    entries = [s for s in SPEC if not s[0].startswith("ui/logo")]
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 10)), (34, 32, 44, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 8)
    except OSError:
        font = ImageFont.load_default()
    for i, (rel, *_rest) in enumerate(entries):
        img = Image.open(OUT / rel)
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        x = (i % cols) * cell
        y = (i // cols) * (cell + 10)
        if img.width > cell or img.height > cell:
            img.thumbnail((cell, cell), Image.NEAREST)
        sheet.alpha_composite(img, (x + (cell - img.width) // 2, y + (cell - img.height) // 2))
        d.text((x + 2, y + cell), Path(rel).name, font=font, fill=(210, 210, 220, 255))
    sheet.save(OUT / "_preview.png")


# ---------------------------------------------------------------- prune（m4-a2 keep-set 修复）
# 非 M1 管线（M1+M2 批次+图集）拥有的子树豁免清理（m4-a2 P0 前置，2026-08-31 prelude
# 审查遗留）：
#   - fx/、trials/ 归 M3 所有（tools/spritegen_m3.py，清单标记 fx/MANIFEST_M3.md）；
#   - icon/ 归 X-C 所有（tools/gen_icon.py，无清单文件故走显式登记）。
# 此前 keep 集只含 M1 SPEC + MANIFEST.md/_preview.png/.gitkeep，全量跑 M1 管线会把
# 这三棵子树当"陈旧残留"静默删除。豁免为双保险：
#   1) 显式豁免集 PRUNE_FOREIGN_DIRS（无标记文件的子树在此登记）；
#   2) 通用规则：子树内存在其他生成器的清单标记（MANIFEST_*.md）即整树豁免——
#      未来新生成器在自家子树放一枚 MANIFEST_<名>.md 即自动免登记。
# 约定：非本管线的生成器二选一（子树放 MANIFEST_*.md 标记 / 在 PRUNE_FOREIGN_DIRS
# 登记），否则全量重跑会把该子树当残留清理。
# 另：*.import sidecar 归 Godot 导入器所有，一律保留（此前全量重跑会删光全部 sidecar，
# 下次打开编辑器/跑测试需整库重导入）。
PRUNE_FOREIGN_DIRS = frozenset({"fx", "trials", "icon"})


def _prune_exempt_dirs():
    """豁免子树集合 = 显式登记 ∪ 含 MANIFEST_*.md 清单标记的顶层子树。"""
    exempt = set(PRUNE_FOREIGN_DIRS)
    if OUT.is_dir():
        for p in OUT.iterdir():
            if p.is_dir() and any(
                    q.is_file() and q.suffix == ".md" and q.name.startswith("MANIFEST_")
                    for q in p.iterdir()):
                exempt.add(p.name)
    return exempt


def _prune_plan():
    """dry-run：返回将被清理的相对路径清单（不动磁盘），供回归测试与 _prune_stale 复用。"""
    keep = {"MANIFEST.md", "_preview.png"}
    for rel, *_rest in SPEC:
        keep.add(rel)
    exempt = _prune_exempt_dirs()
    removed = []
    for p in OUT.rglob("*"):
        # .gitkeep 按 p.name 匹配（任意嵌套层级都保留，m2-t21），不在 keep 集里按路径比对
        if not p.is_file() or p.name == ".gitkeep" or p.suffix == ".import":
            continue
        rel = p.relative_to(OUT).as_posix()
        if rel in keep:
            continue
        if "/" in rel and rel.split("/", 1)[0] in exempt:
            continue
        removed.append(rel)
    return removed


def _prune_stale():
    """成功全量生成后清掉不在 SPEC 的残留（m2-t21 时序修复）。

    旧实现"先清空目录再串联生成"是破坏性时序：生成中途断言/异常即把 art/generated
    毁成半空库（M2 批次武器断链即此案例，全量入口一度禁跑）。改为先生成后清理：
    - 生成失败时旧文件保持可用（可重跑修复），不再有"清空后写一半"窗口；
    - 全量成功后按 SPEC 清单清除陈旧残留（如 m2-t21 废除的 75 武器暂定 slug），
      终态与"清空重建"逐字节等价（每个 SPEC 条目每轮都被覆盖重写）。
    保留项：MANIFEST.md/_preview.png（本轮末统一重写）、.gitkeep、*.import sidecar、
    以及豁免子树（fx/trials/icon 等，见 PRUNE_FOREIGN_DIRS 注释，m4-a2 P0）。"""
    removed = _prune_plan()
    for rel in removed:
        (OUT / rel).unlink()
    return removed


def _prune_after_m2(m2_joined: bool):
    """m2-t21 防回归闸门：仅当 M2 批次实际参与生成后才允许陈旧清理。

    若 M2 导入失败被静默吞掉（旧实现 `except ImportError: pass`）而照常 prune，
    M1 SPEC 之外的整棵 M2 子树（数百文件：武器/敌人帧表/增益图标等）会被当
    "陈旧残留"静默删除——这里 fail-loud 拒绝执行。"""
    if not m2_joined:
        raise RuntimeError(
            "M2 批次未参与生成（gen_placeholder_art_m2 导入失败）"
            "——拒绝执行陈旧清理，防止误删 M2 子树")
    return _prune_stale()


def main():
    SPEC.clear()
    gen_hero_vanguard()
    gen_hero_ranger()
    gen_hero_walk_sheets()
    for eid, (name, cur, note), fn in (
        ("kuli_bug", ENEMY_SPRITES["kuli_bug"], paint_kuli),
        ("cave_bat", ENEMY_SPRITES["cave_bat"], paint_bat),
        ("crossbowman", ENEMY_SPRITES["crossbowman"], paint_crossbow),
        ("vine_charger", ENEMY_SPRITES["vine_charger"], paint_charger),
        ("mushroom_spore", ENEMY_SPRITES["mushroom_spore"], paint_mushroom),
        ("shuangdao_lizardman", ("双刀蜥人（精英）", "data/enemies.json id=shuangdao_lizardman; combo_charger 原型色块 (body_scale 1.25)",
                                 "原型:蜥人双刀客,青鳞金饰; 与普通体区分度要高"), paint_lizard),
        ("zibao_wangchong", ("自爆王虫（精英）", "data/enemies.json id=zibao_wangchong; delayed_blast 延迟爆视觉为色块",
                             "原型:橙红大甲虫+引信; 死亡后 60t 倒计时闪烁帧"), paint_wangchong),
        ("vine_colossus", ("藤蔓巨像（Boss）", "vine_colossus.gd:346-375 绿色块+特效色块; boss_base.gd:100 白闪",
                           "32x32 树巨人; 三阶段可共用本体+特效区分"), paint_colossus),
    ):
        img = fn()
        if eid == "vine_colossus":
            pass  # colossus 已在 painter 内含轮廓
        else:
            outline(img)
        save(img, f"enemies/{eid}.png", f"敌人「{name}」", cur, note)
    gen_projectiles()
    gen_pickups()
    gen_tiles()
    gen_fx()
    gen_ui_frames()
    gen_ui_icons()
    gen_buff_icons()
    gen_drink_icons()
    gen_misc()
    gen_batch2()
    gen_batch3()
    # M2 批次自动串联（脚本存在即生成；清单与联络表在 M2 追加后统一重写）
    m2_joined = False
    try:
        import sys as _sys
        import gen_placeholder_art_m2 as _m2
        _m2.generate(_sys.modules[__name__])
        m2_joined = True
    except Exception:
        import traceback
        traceback.print_exc()   # M2 批次失败可见（含 ImportError）
        raise                    # m2-t21：失败即中止——绝不能带着半量库去 prune
    # m2-t37 全图集合并（§18.3「draw call ≤150（全图集）」前提）：世界精灵装订单页
    # 图集。置于 m2 批次之后、prune 之前——图集失败即中止，绝不带陈旧/缺失图集执行
    # 清理（同 m2-t21 fail-closed 时序）；产物经 add 入 SPEC，随清理白名单保留。
    # fix（评审 Minor-8）：Pillow 缺失等失败给标注化信息后再抛（原样裸 traceback）。
    try:
        import gen_art_atlas as _atlas
        _atlas.pack_atlas(OUT, add_spec=add)
    except Exception:
        import traceback
        traceback.print_exc()   # 图集失败可见（含 Pillow ImportError）
        raise RuntimeError(
            "m2-t37 全图集生成失败——中止（绝不带陈旧/缺失图集去 prune）。"
            "修复提示：确认 Pillow 可用（ART_ATLAS_PYTHON 可指认解释器）、"
            "素材尺寸 ≤128px、总体可装入 1024x1024 页")
    removed = _prune_after_m2(m2_joined)
    write_manifest()
    write_preview()
    # m4-a2: 生成完即自检——美术 QA 三重校验全库（对比度/剪影/接缝，fail-closed）。
    # 存量超阈按 tools/art_qa_baseline.json 棘轮放行（清单已交编排者裁定：修资产或
    # 调阈值）；新增/恶化项直接抛错，绝不让劣化的产物静默入库。
    import art_qa_check as _qa
    _waived = _qa.wire_check(OUT)
    print(f"美术 QA 三重校验: PASS（存量超阈 {_waived} 项按基线棘轮放行，待编排者裁定）")
    print(f"生成 {len(SPEC)} 个素材 -> {OUT}（清理陈旧残留 {len(removed)} 项）")


if __name__ == "__main__":
    import sys as _argv
    if "--hero-sheets" in _argv.argv[1:]:
        gen_hero_sheets_scoped()
        # m2-t37：scoped 再生改动了图集源（英雄帧表虽不在图集，仍幂等重打包保一致）
        import gen_art_atlas as _atlas
        _atlas.pack_atlas(OUT)
    elif "--projectiles" in _argv.argv[1:]:
        gen_projectiles_scoped()
        # m2-t37：scoped 再生后图集随源刷新（幂等，重打包零漂移）
        import gen_art_atlas as _atlas
        _atlas.pack_atlas(OUT)
    elif "--atlas" in _argv.argv[1:]:
        # m2-t37 窄通道：仅重打包图集（additive/idempotent，不触碰任何源图）
        import gen_art_atlas as _atlas
        _atlas.pack_atlas(OUT)
    else:
        main()
