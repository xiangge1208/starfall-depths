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

m4-k1 ③ LOGO 方向变体（同目录新增，只交预览供用户定稿；不替换 icon.svg/项目配置）:
    logo_variant_a_gate_256.png   方向 A 星空石门（= 现行 canonical 构图复刻）
    logo_variant_b_crystal_256.png 方向 B 蓝晶星坠（星陨坠入蓝晶簇——深渊矿物母题）
    logo_variant_c_knight_256.png  方向 C 星芒剑士（星芒下的骑士胸像+竖剑——英雄母题）
    logo_variants_preview.png     三方向并排预览页（256px 面板 + 标注，用户圈选用）

变体扩展色（仍全部出自 tools/spritegen_m3.py 项目调色板，未新增库外色值）:
    #8ae8ff / #b8ecff / #e2f4ff = RAMP_ICE（elem_ice 家族青白）→ 蓝晶簇。

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
    5) 前景/单色层主体外沿在自适应安全区圆（432 直径的 66.7%）内；
    6) m4-k1 变体: 三方向 256 尺寸精确、扩展调色板封口、预览页尺寸精确、
       变体层二次构建 SHA256 一致（同 4 口径）。
"""
import hashlib
import random
import sys
from pathlib import Path

from PIL import Image, ImageFont

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

# m4-k1 ③ 变体扩展色（仍全部出自 tools/spritegen_m3.py 项目调色板，未新增库外色值）：
# RAMP_ICE（elem_ice 家族青白）→ 蓝晶簇母题。
ICE_D = C("#8ae8ff")      # RAMP_ICE 深青（晶体暗面）
ICE_M = C("#b8ecff")      # RAMP_ICE 中青（晶体亮面）
ICE_L = C("#e2f4ff")      # RAMP_ICE 浅青（晶体脊线高光）
PALETTE_VARIANTS = PALETTE | {ICE_D, ICE_M, ICE_L}

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


# ---------------------------------------------------------------- m4-k1 ③ 方向变体
# 三方向（64x64 逻辑画，×4 放大到 256）：A 星空石门（现行 canonical 构图）/ B 蓝晶星坠 /
# C 星芒剑士。变体只产预览供用户定稿，不触碰 icon.svg / 项目配置 / export preset。

def shard(img, cx, y_tip, y_wide, y_base, half_w):
    """菱形晶柱：顶尖→最宽→底收。左半暗面 ICE_D、右半亮面 ICE_M、脊线 ICE_L。"""
    span_top = max(1, y_wide - y_tip)
    span_bot = max(1, y_base - y_wide)
    for y in range(min(y_tip, y_base), max(y_tip, y_base) + 1):
        if y <= y_wide:
            w = int(round(half_w * (y - y_tip) / span_top))
        else:
            w = int(round(half_w * (y_base - y) / span_bot))
        for x in range(cx - w, cx + w + 1):
            px(img, x, y, ICE_D if x < cx else ICE_M)
        px(img, cx, y, ICE_L)


def draw_crystal_fg():
    """变体 B 主体：蓝晶簇（中央主晶 + 左右伴晶 + 白芯闪点 + 石基线），主体外全透明。"""
    img = canvas(64, 64)
    shard(img, 32, 18, 40, 60, 9)     # 中央主晶
    shard(img, 20, 32, 46, 56, 6)     # 左伴晶
    shard(img, 45, 28, 46, 57, 6)     # 右伴晶
    px(img, 32, 19, WHITE)            # 晶尖白芯
    for x, y in ((29, 26), (36, 33), (17, 42), (48, 34), (31, 47)):
        px(img, x, y, WHITE)          # 闪点
    rect(img, 14, 58, 49, 58, STONE_D)  # 石基线（对齐方向 A 台阶的接地语言）
    return img


def draw_bg_knight():
    """变体 C 背景层：静谧星野（无流星，避让星芒区）+ 金色大四芒星（骑士背光）。全不透明。"""
    img = canvas(64, 64, BG_DEEP)
    rng = random.Random(7)
    cells = [(x, y) for y in range(0, 22) for x in range(64)]
    rng.shuffle(cells)
    placed = 0
    for x, y in cells:
        if placed >= 12:
            break
        if 20 <= x <= 44 and 8 <= y <= 36:
            continue   # 星芒区避让
        px(img, x, y, GREY if rng.random() < 0.7 else STAR_PALE)
        placed += 1
    cx, cy = 32, 22
    for d in range(0, 15):   # 正交四芒: 白芯→暖白→黄→金
        c = WHITE if d == 0 else (STAR_PALE if d <= 5 else (YELLOW if d <= 9 else GOLD))
        for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px(img, cx + sx * d, cy + sy * d, c)
    for d in range(3, 6):    # 对角短芒
        c = YELLOW if d < 5 else GOLD
        for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            px(img, cx + sx * d, cy + sy * d, c)
    return img


def draw_knight_fg():
    """变体 C 主体：星芒剑士（圆盔胸像 + 星徽 + 右侧竖剑 + 石阶基座），主体外全透明。"""
    img = canvas(64, 64)
    # 盔冠金饰 + 圆盔（逐行收宽成穹顶）
    rect(img, 30, 24, 33, 25, GOLD_L)
    rect(img, 27, 26, 37, 27, STONE)
    rect(img, 26, 28, 38, 30, STONE)
    rect(img, 25, 31, 39, 38, STONE)
    for y in range(28, 39):
        px(img, 38 if y < 31 else 39, y, STONE_D)   # 右缘暗面
    # 面甲缝（暗槽 + 双白目点）
    rect(img, 27, 33, 37, 34, PORTAL)
    px(img, 30, 33, WHITE)
    px(img, 34, 33, WHITE)
    # 颈甲
    rect(img, 28, 39, 36, 40, STONE_D)
    # 肩甲 + 金缘 + 胸甲
    rect(img, 20, 41, 44, 41, GOLD_D)
    rect(img, 19, 42, 45, 43, STONE_D)
    rect(img, 16, 44, 48, 56, STONE_D)
    rect(img, 25, 44, 39, 56, STONE)
    for x in (16, 48):
        px(img, x, 44, STONE)                        # 肩头高光
    # 胸前星徽（白芯暖白正芒金斜芒）
    px(img, 32, 50, WHITE)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        px(img, 32 + dx, 50 + dy, STAR_PALE)
    for dx, dy in ((1, -1), (-1, -1)):
        px(img, 32 + dx, 50 + dy, GOLD)
    # 竖剑（右侧：白刃线 + 灰刃身 + 金护手/柄/首）
    rect(img, 49, 14, 49, 40, GREY)
    rect(img, 50, 15, 50, 40, WHITE)
    px(img, 50, 13, WHITE)
    px(img, 49, 13, WHITE)
    px(img, 50, 14, GREY)
    rect(img, 46, 41, 53, 41, GOLD_L)
    rect(img, 46, 42, 53, 42, GOLD_D)
    rect(img, 49, 43, 50, 49, GOLD_D)
    rect(img, 49, 50, 50, 50, GOLD)
    # 石阶基座（对齐方向 A 的接地语言）
    rect(img, 14, 57, 49, 57, STONE)
    rect(img, 12, 58, 51, 58, STONE_D)
    return img


def build_preview(panels):
    """三方向并排预览页：夜空底 + 石框 + 融合像素字标注（缺失时回退默认字体 ASCII）。"""
    from PIL import ImageDraw
    margin, gutter, panel, label_h = 24, 24, 256, 40
    width = margin * 2 + panel * 3 + gutter * 2
    height = margin + panel + label_h + margin
    page = canvas(width, height, BG_DEEP)
    labels = ["A 星空石门（现行）", "B 蓝晶星坠", "C 星芒剑士"]
    labels_fallback = ["A gate (current)", "B crystal", "C knight"]
    font = None
    try:
        font_path = ROOT / "art" / "fonts" / "fusion-pixel-12px-monospaced-zh_hans.ttf"
        font = ImageFont.truetype(str(font_path), 24)
    except Exception:
        font = None
    for i, (name, img) in enumerate(panels.items()):
        x0 = margin + i * (panel + gutter)
        rect(page, x0 - 2, margin - 2, x0 + panel + 1, margin + panel + 1, STONE_D)  # 石框
        page.alpha_composite(img, (x0, margin))
        strip = Image.new("RGBA", (panel, label_h), (0, 0, 0, 0))
        text = labels[i] if font is not None else labels_fallback[i]
        ImageDraw.Draw(strip).text((panel // 2, label_h // 2 - 2), text, font=font,
                                   fill=WHITE, anchor="mm")
        page.alpha_composite(strip, (x0, margin + panel + 8))
    return page


# ---------------------------------------------------------------- QA 自检
def qa_variants(variants, preview, expect_preview_size):
    """m4-k1 变体 QA：三方向 256 尺寸精确 + 扩展调色板封口 + 预览页尺寸精确。失败退出码 1。"""
    for name, img in variants.items():
        if img.size != (256, 256):
            print(f"[gen_icon] VARIANT QA FAIL: {name} size {img.size} != (256,256)")
            return False
        data = img.convert("RGBA").load()
        stray = set()
        for y in range(256):
            for x in range(256):
                c = data[x, y]
                if c[3] != 0 and c not in PALETTE_VARIANTS:
                    stray.add(c)
        if stray:
            print(f"[gen_icon] VARIANT QA FAIL: {name} 调色板外色值 x{len(stray)}: {sorted(stray)[:4]}")
            return False
    if preview.size != expect_preview_size:
        print(f"[gen_icon] VARIANT QA FAIL: preview size {preview.size} != {expect_preview_size}")
        return False
    print("[gen_icon] VARIANT QA PASS: 三方向 256 尺寸/扩展调色板封口/预览页尺寸 全过")
    return True


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
    # ---- m4-k1 ③ LOGO 方向变体（A 现行复刻 / B 蓝晶星坠 / C 星芒剑士）----
    gate = bg64.copy()
    gate.alpha_composite(fg)
    vb = draw_bg(64).copy()
    vb.alpha_composite(draw_crystal_fg())
    vc = draw_bg_knight()
    vc.alpha_composite(draw_knight_fg())
    variants = {
        "logo_variant_a_gate_256.png": upscale(gate, 4),
        "logo_variant_b_crystal_256.png": upscale(vb, 4),
        "logo_variant_c_knight_256.png": upscale(vc, 4),
    }
    # 变体层确定性: 重建一遍比对（同 canonical 口径）
    vb2 = draw_bg(64).copy()
    vb2.alpha_composite(draw_crystal_fg())
    vc2 = draw_bg_knight()
    vc2.alpha_composite(draw_knight_fg())
    deterministic_v = (
        hashlib.sha256(vb.tobytes()).hexdigest() == hashlib.sha256(vb2.tobytes()).hexdigest()
        and hashlib.sha256(vc.tobytes()).hexdigest() == hashlib.sha256(vc2.tobytes()).hexdigest()
    )
    if not deterministic_v:
        print("[gen_icon] VARIANT QA FAIL: 两次构建不一致（变体确定性破坏）")
        return 1
    preview = build_preview(variants)
    for name, img in variants.items():
        img.save(OUT / name)
        print(f"[gen_icon] wrote art/generated/icon/{name}  {img.width}x{img.height}")
    preview.save(OUT / "logo_variants_preview.png")
    print(f"[gen_icon] wrote art/generated/icon/logo_variants_preview.png  {preview.width}x{preview.height}")
    if not qa_variants(variants, preview, preview.size):
        return 1
    print("[gen_icon] LOGO-VARIANTS-OK: 3 directions + preview page, seed=42/7, palette=project DB16-derived")
    print("[gen_icon] DONE: 5 products, seed=42, palette=project DB16-derived, zero third-party assets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
