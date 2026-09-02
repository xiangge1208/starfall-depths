# -*- coding: utf-8 -*-
"""美术 QA 三重校验全管线（M4-A2）：对比度 / 剪影 / 接缝，覆盖全部 art/generated/。

规格源:
    GDD §16.1（docs/superpowers/specs/2026-08-28-starfall-depths-design.md:281-284）
        —— 前景/玩法层与背景亮度差 ≥30；剪影 30% 亮度下轮廓可辨。
    GDD §21 风险表 —— 「调色板/剪影/对比度三重脚本校验」。
    既有先例: tools/spritegen_m3.py（fx+trials 三查；本脚本直接 import 其 qa_frame
        与阈值常量做单一数学源，不再复制公式）。

三重项定义（阈值沿用先例，不放宽）:
    对比度  = 可见集（合成到底色后亮度差 ≥8/255 的像素）平均亮度(0~100) − 底色亮度
              (#181420 ≈ 8.9) ≥ 30。人群口径澄清（M4-A2）: 先例 alpha>0 全体在无描边
              fx 上与本口径同值；M1/M2 精灵普遍带 ≈底色的分离描边，全体人群会把描边
              计入前景系统性低估（baoliejian strict 22.0 vs 可见集 55.0）。先例严格值
              仍逐帧记入 records['contrast_strict'] 供审计。
              不透明背景瓦片改为成对口径: wall_X vs floor_X 平均亮度差 ≥30（GDD
              「玩法层 vs 背景」在瓦片上的可走/阻挡可读性读法）。
    剪影    = 亮度压至 30% 后阈值重建 mask 与可见 mask 的 IoU ≥ 0.85，
              且主连通域(8-conn)占比 ≥ 0.85
    接缝    = ①瓦片可平铺性: 边缘 wrap 缝亮度差 vs 内部梯度（地板/走廊查左右+上下；
              墙体只查水平——顶部亮边为设计内嵌「顶部 1px 亮色已内嵌」，上下砖带
              观感即 2.5D 设计本身）
              ②帧序列（对齐 spritegen_m3 既有「帧序列」检查）: 尺寸/帧数正确、每帧
              非空；walk/动画帧表追加相邻帧可见 mask IoU ≥0.40（fx 条带为扩张/消散
              演出，帧间大幅变化即设计，不查连续性）

目录-校验项映射表（子树 × 项）:
    | 子树                        | 对比度        | 剪影 | 接缝(帧序列)            | 接缝(瓦片)   |
    |-----------------------------|---------------|------|-------------------------|--------------|
    | characters/ 单帧 (6)        | ✓(可见集)     | ✓    | —                       | —            |
    | characters/*_sheet (6)      | ✓/帧          | ✓/帧 | 16 帧非空+连续性        | —            |
    | enemies/ 单帧 (54, 含 Boss) | ✓(可见集)     | ✓    | —                       | —            |
    | enemies/*_sheet (40)        | ✓/帧          | ✓/帧 | 2 帧非空+连续性         | —            |
    | projectiles/ (11) pickups/  | ✓(可见集)     | ✓    | —                       | —            |
    | fx/ M3 条带+图标 (10)       | ✓/帧          | ✓/帧 | 先例全查(帧数+颜色≤6)   | —            |
    | fx/ M1 其余精灵 (7)         | ✓(可见集)     | ✓    | —                       | —            |
    | fx/ 覆盖层 5 (telegraph 等) | 语义豁免      | 语义豁免 | —                    | —            |
    | trials/ (8)                 | ✓             | ✓    | 先例全查(颜色≤6)        | —            |
    | ui/ weapons/ 图标套件 (355) | ✓(可见集)     | 语义豁免 | —（无帧表）          | —            |
    |   （面板承载的 HUD/商店/菜单图标: 剪影主连通域对设计性断开细节是噪声——爆裂剑   |
    |    碎片/雪花辐条；仍查非空【已实证抓到 5 张空 buff 图标】+ 对比度 HUD 可读性）  |
    | tiles/ 可平铺地块 (13)      | 成对 墙vs地≥30 | —   | —                       | wrap 缝      |
    | tiles/ 其余道具 (29)        | ✓(可见集)     | ✓    | —                       | —            |
    | tiles/hazard_* + fx 覆盖层  | 语义豁免      | 语义豁免 | —                    | —            |
    | atlas/ icon/                | —             | —    | —                       | —            |
    | （复合图集页/应用图标: 结构校验 only——atlas 解码+≤1024+json 可解析；icon 由     |
    |   gen_icon.py 自带 5 项 QA 且大图含满幅夜空底，GDD 前景/背景口径不适用）        |
    | MANIFEST.md / _preview.png / fx/MANIFEST_M3.md: 存在性断言                     |

fail-closed: 任一失败退出码 1（结构错误 2）；gen_placeholder_art.py 全量入口尾部
接线（生成完即自检）。只读资产，零磁盘写入（--json 报告除外）。

用法:
    python tools/art_qa_check.py [--root PATH] [--json PATH] [--verbose]
                                 [--baseline PATH] [--strict] [--save-baseline]

棘轮口径（M4-A2 存量基线）: 存量库有 40 项超阈（清单见 tools/art_qa_baseline.json，
已交编排者裁定：修资产或调阈值）。默认按基线棘轮放行已知项（fail-closed 只对
"新增/恶化"生效——当前失败项 ⊄ 基线即退出码 1）；`--strict` 忽略基线纯校验；
`--save-baseline` 全量刷新基线（修资产后应重刷收缩清单，不许无声扩大）。
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spritegen_m3 as m3  # noqa: E402  三重校验单一数学源（qa_frame + 阈值）

from PIL import Image  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BASELINE = ROOT / "tools" / "art_qa_baseline.json"

# ---- 沿用先例阈值（GDD §16.1 / spritegen_m3）——不得在本脚本内放宽
CONTRAST_MIN = m3.CONTRAST_MIN        # 30
IOU_MIN = m3.IOU_MIN                  # 0.85
SHARE_MIN = m3.SHARE_MIN              # 0.85
COLOR_MAX = m3.COLOR_MAX              # 6 —— 仅 M3 先例文件（M3 条带预算口径；GDD 无颜色上限要求）
# ---- 本卡新增阈值（GDD ≥30 直接引用；接缝两项为基线标定，见 header/报告）
TILE_PAIR_DELTA_MIN = 30.0            # GDD §16.1: 墙(阻挡) vs 地板(可走) 亮度差 ≥30
SEAM_WRAP_MAX = 26.0                  # 瓦片 wrap 缝: max(左右, 上下)边缘亮度差均值上限（基线标定）
SEAM_RATIO_MAX = 3.0                  # wrap 缝 / 内部梯度 比值上限（基线标定）
CONTINUITY_MIN = 0.40                 # 相邻帧可见 mask IoU 下限（基线标定: 1px bob 设计实测最低 0.446，
                                      # 错帧/坏帧类缺陷实测量级 ≤0.3，取 0.40 留 ~10% 裕度）

# ---- tiles/ 可平铺背景地块（生成端语义: 地板/墙体/走廊，"替换需保持 16x16 无缝"）
TILEABLE = {
    "floor_cave", "floor_garden", "floor_boss", "floor_crystal", "floor_magma",
    "corridor_floor", "corridor_crystal", "corridor_magma",
    "wall_cave", "wall_garden", "wall_boss", "wall_crystal", "wall_magma",
}
PAIR_BIOMES = ("cave", "garden", "boss", "crystal", "magma")   # wall_X/floor_X 成对对比度
# 半透明战术指示/覆盖层 + 准星（overlay）: telegraph/safe_zone/fuse_zone 为半透明
# 预警区（游戏内 tint/闪烁动画承载可读性，静态 PNG 的前景/背景对比度口径不适用）；
# reticle 十字准星多域断开为设计本身（剪影主连通域不适用）；hazard_* 同理；
# vignette_lowhp（满屏半透明低血提醒 alpha≤192）/joystick_base（触屏摇杆底座 alpha≤90）
# 为 HUD 半透明件。→ 结构校验 only（非空 + 半透明存在），三重项豁免属语义类裁定
# 而非阈值放宽。
OVERLAYS = {
    "fx/telegraph_circle.png", "fx/telegraph_rect.png", "fx/safe_zone.png",
    "fx/fuse_zone.png", "fx/reticle.png",
    "tiles/hazard_vine.png", "tiles/hazard_ice.png", "tiles/hazard_lava.png",
    "tiles/hazard_spikes.png", "tiles/hazard_vent.png",
    "ui/vignette_lowhp.png", "ui/joystick_base.png",
}
STRUCTURAL_DIRS = {"atlas", "icon"}   # 复合图集页 / 应用图标（各自生成器自带 QA），结构校验 only

M3_STRIP_FRAMES = {name: spec for name, spec in m3.EXPECT.items()}
M3_TRIAL_FILES = set(m3.TRIAL_EXPECT)


# ---------------------------------------------------------------- 基础工具
def _lum(rgb):
    return m3._lum255(rgb[:3])


def load_rgba(path):
    with Image.open(path) as im:
        return im.convert("RGBA")


def vis_mask(frame):
    """可见像素 mask（同 spritegen_m3 口径: 合成到底色后亮度差 ≥ VIS_DELTA）。
    同时返回可见集对比度（合成亮度均值 − 底色亮度，0~100 口径）。

    口径澄清（M4-A2）: 先例公式人群=alpha>0 全体，对无描边 fx 与本口径完全一致
    （如 pickups/coin 两口径同值）；但 M1/M2 精灵普遍带 #181420 分离描边（≈底色），
    全体人群会把描边计入前景造成系统性低估（如 weapons/baoliejian strict 22.0 vs
    可见集 55.0）。GDD「前景/玩法层与背景亮度差」按可见集计；先例严格值仍记入
    records['contrast_strict'] 供审计。阈值不放宽（仍 ≥30）。"""
    px = frame.load()
    w, h = frame.size
    total = 0.0
    n = 0
    out = set()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0:
                cl = a / 255.0 * _lum((r, g, b)) + (1 - a / 255.0) * m3.BG_LUM
                if cl - m3.BG_LUM >= m3.VIS_DELTA:
                    out.add((x, y))
                    total += cl
                    n += 1
    contrast = (total / n / 255.0 * 100.0 - m3.BG_LUM100) if n else 0.0
    return out, contrast


def mask_iou(a, b):
    union = a | b
    return (len(a & b) / len(union)) if union else 1.0


def split_frames(rel, img):
    """按文件约定切帧。返回 (帧列表, 约定说明)；非条带/帧表 → 单帧。"""
    parts = rel.split("/")
    name = parts[-1]
    w, h = img.size
    if rel.startswith("fx/") and name in M3_STRIP_FRAMES:
        _ew, _eh, n = M3_STRIP_FRAMES[name]
        if n > 1:
            fw = w // n
            return [img.crop((i * fw, 0, (i + 1) * fw, h)) for i in range(n)], f"M3 条带 {n} 帧"
        return [img], "M3 单帧"
    if rel.startswith("characters/") and name.endswith("_sheet.png"):
        # 4 向 x (idle+walk x3)，行=下/上/左/右，列帧 16px（gen_hero_walk_sheets）
        frames = [img.crop((c * 16, r * 16, (c + 1) * 16, (r + 1) * 16))
                  for r in range(h // 16) for c in range(w // 16)]
        return frames, f"walk 帧表 {w // 16}x{h // 16} 帧(16px)"
    if rel.startswith("enemies/") and name.endswith("_sheet.png"):
        # m2-t21: (2w, h) 横向 2 帧（列=idle+walk）
        fw = w // 2
        return [img.crop((0, 0, fw, h)), img.crop((fw, 0, w, h))], "2 帧动画表(idle+walk)"
    return [img], "单帧"


def tile_seam_metrics(img):
    """不透明可平铺地块的 wrap 缝指标: 边缘环亮度差 vs 内部梯度。"""
    px = img.load()
    w, h = img.size
    lum = [[_lum(px[x, y][:3]) for x in range(w)] for y in range(h)]
    wrap_h = sum(abs(lum[y][w - 1] - lum[y][0]) for y in range(h)) / h
    wrap_v = sum(abs(lum[h - 1][x] - lum[0][x]) for x in range(w)) / w
    grad = 0.0
    n = 0
    for y in range(h):
        for x in range(w - 1):
            grad += abs(lum[y][x + 1] - lum[y][x])
            n += 1
    for y in range(h - 1):
        for x in range(w):
            grad += abs(lum[y + 1][x] - lum[y][x])
            n += 1
    interior = grad / n if n else 0.0
    wrap = max(wrap_h, wrap_v)
    return {"wrap_h": round(wrap_h, 2), "wrap_v": round(wrap_v, 2),
            "wrap": round(wrap, 2), "interior": round(interior, 2),
            "ratio": round(wrap / max(interior, 1e-6), 2)}


# ---------------------------------------------------------------- 分类
def classify(rel):
    """返回 (kind, detail)。
    kind ∈ m3/sheet_hero/sheet_enemy/tile/overlay/structural/icon/sprite。"""
    parts = rel.split("/")
    sub, name = parts[0], parts[-1]
    stem = name[:-4] if name.endswith(".png") else name
    if sub in STRUCTURAL_DIRS or rel in OVERLAYS:
        return "structural" if sub in STRUCTURAL_DIRS else "overlay", sub
    if sub == "fx" and name in M3_STRIP_FRAMES:
        return "m3", "fx"
    if sub == "trials" and name in M3_TRIAL_FILES:
        return "m3", "trials"
    if sub == "characters" and name.endswith("_sheet.png"):
        return "sheet_hero", "characters"
    if sub == "enemies" and name.endswith("_sheet.png"):
        return "sheet_enemy", "enemies"
    if sub == "tiles" and stem in TILEABLE:
        return "tile", stem
    if sub in ("ui", "weapons"):
        # 图标/UI 套件类: 面板承载的 HUD/商店/菜单图标与面板件。GDD §16.1 剪影口径
        # （角色/Boss 在地牢背景上的轮廓可辨）不适用于面板图标学——武器图标的设计性
        # 碎片/雪花辐条等断开细节会让主连通域阈值成为噪声。仍查: 非空（已实证抓到
        # 5 张空 buff 图标）+ 对比度（HUD 可读性仍由「图标 vs 暗面板」传递）。
        return "icon", sub
    return "sprite", sub


def check_sprite_file(rel, img, rec, enforce_colors, check_continuity):
    """对比度 + 剪影（逐帧）+ 帧非空 + 帧数 +（walk/动画帧表）相邻帧连续性。"""
    frames, kind_txt = split_frames(rel, img)
    rec["frames"] = len(frames)
    rec["kind"] = kind_txt
    fails = []
    masks = []
    for i, f in enumerate(frames):
        q = m3.qa_frame(f)
        mask, contrast = vis_mask(f)
        masks.append(mask)
        tag = f"f{i}"
        rec.setdefault("contrast", []).append(contrast)
        rec.setdefault("contrast_strict", []).append(round(q["contrast"], 1))
        rec.setdefault("iou", []).append(round(q["iou"], 3))
        rec.setdefault("share", []).append(round(q["share"], 3))
        rec.setdefault("colors", []).append(q["ncolors"])
        if not q["nonempty"]:
            fails.append(f"{tag} 空帧")
        if contrast < CONTRAST_MIN:
            fails.append(f"{tag} 对比度 {contrast:.1f} < {CONTRAST_MIN}")
        if q["iou"] < IOU_MIN:
            fails.append(f"{tag} 剪影 IoU {q['iou']:.3f} < {IOU_MIN}")
        if q["share"] < SHARE_MIN:
            fails.append(f"{tag} 主连通域 {q['share']:.3f} < {SHARE_MIN}")
        if enforce_colors and q["ncolors"] > COLOR_MAX:
            fails.append(f"{tag} 颜色数 {q['ncolors']} > {COLOR_MAX}（M3 条带预算）")
    # 接缝(帧序列): 仅 walk/动画帧表——帧是同一姿态的推进，相邻帧 mask 应连续；
    # fx 条带是扩张/消散演出（帧间大幅变化为设计本身），只保留先例帧检查不查连续性。
    if check_continuity and len(frames) > 1:
        cont = [round(mask_iou(masks[i], masks[i + 1]), 3) for i in range(len(masks) - 1)]
        rec["continuity"] = cont
        for i, c in enumerate(cont):
            if c < CONTINUITY_MIN:
                fails.append(f"f{i}->f{i+1} 连续性 IoU {c:.3f} < {CONTINUITY_MIN}")
    return fails


def mean_lum(img):
    """整图平均亮度（0~255，成对墙/地对比度用；瓦片不透明故不扣 alpha）。"""
    px = img.load()
    w, h = img.size
    total = 0.0
    for y in range(h):
        for x in range(w):
            total += _lum(px[x, y][:3])
    return total / (w * h)


def check_icon_file(rel, img, rec):
    """图标/UI 套件类: 逐帧非空 + 对比度（可见集）。剪影/主连通域不查（语义豁免）。"""
    frames, kind_txt = split_frames(rel, img)
    rec["frames"] = len(frames)
    rec["kind"] = kind_txt
    fails = []
    for i, f in enumerate(frames):
        _mask, contrast = vis_mask(f)
        nonempty = f.getchannel("A").getextrema()[1] > 0
        tag = f"f{i}"
        rec.setdefault("contrast", []).append(contrast)
        if not nonempty:
            fails.append(f"{tag} 空帧")
        elif contrast < CONTRAST_MIN:
            fails.append(f"{tag} 对比度 {contrast:.1f} < {CONTRAST_MIN}")
    return fails


# ---------------------------------------------------------------- 主校验
def check_all(root=None, verbose=False):
    """全库三重校验（只读）。返回 (records, failures)。
    failures: ["<file>: <msg>", ...]；结构错误直接抛 RuntimeError。"""
    root = Path(root) if root else ROOT / "art" / "generated"
    if not root.is_dir():
        raise RuntimeError(f"资产根目录不存在: {root}")

    records = []
    failures = []
    tile_imgs = {}   # 可平铺地块暂存，第二轮统一查（接缝 + 成对对比度）

    pngs = sorted(root.rglob("*.png"))
    for p in pngs:
        rel = p.relative_to(root).as_posix()
        if rel == "_preview.png":
            continue  # 联络表（人工检查用），存在性在收尾断言
        try:
            img = load_rgba(p)
        except Exception as e:  # noqa: BLE001 —— 结构错误: 解码失败即整库不可信
            raise RuntimeError(f"PNG 解码失败: {rel}: {e}")
        kind, detail = classify(rel)
        rec = {"file": rel, "class": kind}
        local_fails = []
        if kind == "structural":
            w, h = img.size
            if w == 0 or h == 0:
                local_fails.append("空图")
            if img.getchannel("A").getextrema()[1] == 0:
                local_fails.append("全透明")
            rec.update({"w": w, "h": h})
        elif kind == "overlay":
            extrema = img.getchannel("A").getextrema()
            if extrema[1] == 0:
                local_fails.append("空图（全透明覆盖层）")
            rec["class_note"] = "半透明指示/覆盖层: 三重项语义豁免（结构校验 only）"
            rec["alpha_range"] = list(extrema)
        elif kind == "tile":
            tile_imgs[rel] = img
        elif kind == "m3":
            local_fails = check_sprite_file(rel, img, rec, enforce_colors=True,
                                            check_continuity=False)
        elif kind == "sheet_hero":
            if img.size != (64, 64):
                local_fails.append(f"帧表尺寸 {img.size} != (64, 64)")
            local_fails += check_sprite_file(rel, img, rec, enforce_colors=False,
                                             check_continuity=True)
        elif kind == "sheet_enemy":
            if img.size[0] != 2 * img.size[1] or img.size[0] % 2:
                local_fails.append(f"2 帧动画表尺寸异常 {img.size}（应为 2w x w）")
            local_fails += check_sprite_file(rel, img, rec, enforce_colors=False,
                                             check_continuity=True)
        elif kind == "icon":
            local_fails = check_icon_file(rel, img, rec)
        else:  # sprite
            local_fails = check_sprite_file(rel, img, rec, enforce_colors=False,
                                            check_continuity=False)

        if kind != "tile":
            for msg in local_fails:
                failures.append(f"{rel}: {msg}")
            records.append(rec)

    # 第二轮: 可平铺地块（接缝 + 成对对比度；亮度表一次算齐）
    # 接缝口径: 地板/走廊 = 任意方向平铺 → 左右+上下 wrap 全查；
    # 墙体 = 2.5D 立面砖，顶部亮边为设计内嵌（gen_tiles "顶部 1px 亮色已内嵌"），
    # 上下 wrap 非无缝是砖带观感本身 → 只查水平 wrap（左右列邻接）。
    lum_table = {rel: mean_lum(img) for rel, img in tile_imgs.items()}
    for rel, img in sorted(tile_imgs.items()):
        stem = rel.split("/")[-1][:-4]
        rec = {"file": rel, "class": "tile"}
        fails = []
        m = tile_seam_metrics(img)
        rec["seam"] = m
        is_wall = stem.startswith("wall_")
        wrap = m["wrap_h"] if is_wall else m["wrap"]
        ratio = wrap / max(m["interior"], 1e-6)
        rec["seam"]["checked_wrap"] = round(wrap, 2)
        rec["seam"]["checked_ratio"] = round(ratio, 2)
        if wrap > SEAM_WRAP_MAX:
            fails.append(f"wrap 缝 {wrap:.1f} > {SEAM_WRAP_MAX}"
                         f"（h={m['wrap_h']}/v={m['wrap_v']}{'，墙只查水平' if is_wall else ''}）")
        if ratio > SEAM_RATIO_MAX:
            fails.append(f"wrap/内部梯度比 {ratio:.2f} > {SEAM_RATIO_MAX}（内部 {m['interior']}）")
        biome = stem.split("_")[-1]
        if is_wall and biome in PAIR_BIOMES:
            floor_key = f"tiles/floor_{biome}"
            if floor_key in lum_table:
                delta = abs(lum_table[rel] - lum_table[floor_key])
                rec["pair_delta"] = round(delta, 1)
                if delta < TILE_PAIR_DELTA_MIN:
                    fails.append(f"墙/地亮度差 {delta:.1f} < {TILE_PAIR_DELTA_MIN}"
                                 f"（wall_{biome} {lum_table[rel]:.1f} vs floor_{biome} {lum_table[floor_key]:.1f}）")
        for msg in fails:
            failures.append(f"{rel}: {msg}")
        records.append(rec)
    # 结构存在性: 清单/联络表/图集页
    for must in ("MANIFEST.md", "_preview.png", "fx/MANIFEST_M3.md"):
        if not (root / must).exists():
            failures.append(f"{must}: 缺失（清单/联络表/M3 标记必须存在）")
    atlas_json = root / "atlas" / "atlas.json"
    if atlas_json.exists():
        try:
            json.loads(atlas_json.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            failures.append(f"atlas/atlas.json: 解析失败 {e}")

    if verbose:
        for rec in records:
            print(json.dumps(rec, ensure_ascii=False))
    return records, failures


def failure_key(msg):
    """失败消息 → 稳定键 "<file>: <项>"（棘轮比对用；量测值不进键，修资产即自动收缩）。"""
    rel, text = msg.split(": ", 1)
    for probe, kind in (("对比度", "contrast"), ("剪影 IoU", "iou"), ("主连通域", "share"),
                        ("颜色数", "colors"), ("连续性", "continuity"), ("wrap", "seam"),
                        ("墙/地", "pair"), ("空帧", "empty"), ("空图", "empty")):
        if probe in text:
            return f"{rel}:{kind}"
    return f"{rel}:other"


def load_baseline(path):
    p = Path(path)
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def wire_check(root=None, baseline_path=None):
    """生成管线尾部自检入口（fail-closed）：新增/恶化超阈即 RuntimeError。
    已知存量超阈按基线棘轮放行（清单交编排者裁定中）。"""
    root = Path(root) if root else ROOT / "art" / "generated"
    baseline_path = Path(baseline_path) if baseline_path else DEFAULT_BASELINE
    _records, failures = check_all(root)
    known = load_baseline(baseline_path)
    new = failures
    waived = 0
    if known is not None:
        known_keys = set(known.get("known_failures", {}))
        cur = {failure_key(m): m for m in failures}
        new = [m for k, m in cur.items() if k not in known_keys]
        waived = len(cur) - len(new)
    if new:
        print(f"美术 QA 三重校验: 新增/恶化 {len(new)} 项（存量放行 {waived} 项）:")
        for m in new:
            print(f"  - {m}")
        raise RuntimeError(
            f"美术 QA 三重校验 fail-closed: {len(new)} 项新增/恶化超阈"
            f"（存量已知项按 {baseline_path.name} 棘轮放行；修资产后用 --save-baseline 收缩清单）")
    return waived


def main(argv=None):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="美术 QA 三重校验全管线（M4-A2）")
    ap.add_argument("--root", default=None, help="资产根目录（默认 <repo>/art/generated）")
    ap.add_argument("--json", dest="json_path", default=None, help="机器可读报告输出路径")
    ap.add_argument("--verbose", action="store_true", help="逐文件打印记录")
    ap.add_argument("--baseline", default=None,
                    help="已知超阈基线 JSON（默认 tools/art_qa_baseline.json；不存在=严格模式）")
    ap.add_argument("--strict", action="store_true", help="忽略基线棘轮，全量严格校验")
    ap.add_argument("--save-baseline", action="store_true",
                    help="把当前失败项全量写入基线（修资产后重刷收缩；不许无声扩大）")
    args = ap.parse_args(argv)

    root = Path(args.root) if args.root else ROOT / "art" / "generated"
    baseline_path = Path(args.baseline) if args.baseline else DEFAULT_BASELINE
    try:
        records, failures = check_all(root, verbose=args.verbose)
    except RuntimeError as e:
        print(f"FAIL(structural): {e}")
        return 2

    if args.save_baseline:
        entry = {
            "comment": "美术 QA 已知超阈清单（棘轮基线）。条目=失败项稳定键，值为最近一次实测。"
                       "修资产后重跑 --save-baseline 收缩清单；生成管线/测试对新增项 fail-closed。"
                       "清单裁定权在编排者（A-2 只建账，不修资产不调阈值）。",
            "known_failures": {failure_key(m): m for m in failures},
        }
        baseline_path.write_text(json.dumps(entry, ensure_ascii=False, indent=1),
                                 encoding="utf-8")
        print(f"OK: 基线已写入 {baseline_path}（已知超阈 {len(failures)} 项）")
        return 0

    if args.json_path:
        Path(args.json_path).write_text(
            json.dumps({"root": str(root), "failures": failures, "records": records},
                       ensure_ascii=False, indent=1), encoding="utf-8")

    known = None if args.strict else load_baseline(baseline_path)
    waived_msgs = []
    if known is not None and failures:
        known_keys = set(known.get("known_failures", {}))
        cur = {failure_key(m): m for m in failures}
        waived_msgs = [m for k, m in cur.items() if k in known_keys]
        failures = [m for k, m in cur.items() if k not in known_keys]

    by_sub = {}
    for rec in records:
        by_sub.setdefault(rec["file"].split("/")[0], []).append(rec)
    print(f"== 美术 QA 三重校验 == root={root}")
    print("  阈值: 对比度(可见集)≥30 / 剪影 IoU≥0.85 / 主连通域≥0.85"
          " / M3 条带颜色≤6 / 墙地差≥30 / wrap 缝≤26(比≤3.0) / 帧连续性 IoU≥0.40")
    for sub in sorted(by_sub):
        rs = by_sub[sub]
        print(f"  [{sub}] 校验 {len(rs)} 项")
    if failures:
        print(f"FAIL: {len(failures)} 项新增/恶化未过（fail-closed；存量放行 "
              f"{len(waived_msgs)} 项）:")
        for msg in failures:
            print(f"  - {msg}")
        return 1
    if waived_msgs:
        print(f"OK: 三重校验通过（{len(records)} 文件）；存量超阈 {len(waived_msgs)} 项"
              f"按基线棘轮放行（清单 {baseline_path.name}，待编排者裁定）:")
        for msg in waived_msgs:
            print(f"  ~ {msg}")
        print(f"ART-QA-CHECK-OK waived={len(waived_msgs)} checked={len(records)}")
        return 0
    print(f"OK: 三重校验全 PASS（{len(records)} 文件）")
    print(f"ART-QA-CHECK-OK waived=0 checked={len(records)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
