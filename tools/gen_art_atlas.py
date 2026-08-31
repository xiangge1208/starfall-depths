# -*- coding: utf-8 -*-
"""m2-t37 全图集合并生成器（GDD §18.3「draw call ≤150（全图集）」前提落地）。

additive / idempotent：
    只新增 atlas/ 子目录两件产物（atlas_page.png + atlas.json），绝不改写/删除任何
    源图；同输入逐字节同输出（确定性排序 + shelf 装箱），重跑零漂移。
排除（不可入图集）：
    - 白名单外目录（tiles/* 走 region+repeat 无缝平铺、ui/ 大图/Control 消费、
      atlas/ 产物自身等）——显式白名单防未来大图/平铺图误入打挂管线；
    - *_sheet.png：Sprite2D hframes/vframes 帧表寻址依赖整图尺寸。
fail-closed：
    - Pillow 缺失 → hard fail（拒绝静默跳过，同 m2-t21 口径）；
    - 单图 > MAX_SPRITE_DIM（当前最大 Boss/fx 64）→ 拒绝而非静默膨胀；
    - 装不进 MAX_PAGE（1024，2GB 内存机型 VRAM 预算线）→ 拒绝。
装箱：2px 边缘外扩（复制边框像素）防采样渗色；整数像素区域，最近邻采样不模糊。
用法：
    python tools/gen_art_atlas.py                        # 从现有 art/generated 打包
    python tools/gen_art_atlas.py --root <dir> --out <dir>  # 测试重定向（零仓库副作用）
管线接线（tools/gen_placeholder_art.py）：main() 末尾 m2 批次之后、prune 之前调用
    pack_atlas(OUT, add_spec=add)——产物入 SPEC 随清理白名单保留；图集失败即中止，
    绝不带陈旧/缺失图集执行清理。
"""
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:   # 入口统一 hard-fail（拒绝静默吞，test_art_pipeline 口径）
    Image = None

PAGE_NAME = "atlas_page.png"
MANIFEST_NAME = "atlas.json"
PAD = 2                       # 边缘外扩像素（防图集采样渗色）
MAX_PAGE = 1024               # 单页边长上限（2GB 内存机型 VRAM 预算，fail-closed）
MIN_PAGE = 256
MAX_SPRITE_DIM = 128          # 单图边长上限（当前最大 Boss/fx 64；超限拒绝入库）
## 入图集白名单（运行时世界精灵目录，与 ArtLookup 表驱动消费面对齐）：
## characters/（站立像；*_sheet.png 帧表排除）、enemies/（单体像）、projectiles/、
## pickups/、fx/、weapons/（手持）、ui/weapons/（图鉴/武器架图标）。
## ui/ 其余（logo/portrait/vignette/条形框等大图、Control 消费）不入——显式白名单
## 防未来大图/平铺图误入把管线打挂（fail-closed 优于静默膨胀）。
ALLOW_DIRS = ("characters", "enemies", "projectiles", "pickups", "fx", "weapons",
              "ui/weapons")


def _in_allow(rel: str) -> bool:
    return any(rel == d or rel.startswith(d + "/") for d in ALLOW_DIRS)


def _iter_sources(root: Path):
    """确定性枚举可入图集的世界精灵源图（排序遍历 → 幂等）。"""
    for p in sorted(root.rglob("*.png")):
        rel = p.relative_to(root).as_posix()
        if not _in_allow(rel):                # 白名单外（tiles/ui 大图/产物自身…）不入
            continue
        if rel.endswith("_sheet.png"):        # hframes/vframes 帧表依赖独立整图
            continue
        yield rel, p


def _extrude(img, pad: int):
    """边缘外扩：把边框像素向外复制 pad 圈（防图集相邻区域采样渗色/浮点边缘漂移）。"""
    w, h = img.size
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    out.paste(img, (pad, pad))
    px = out.load()
    src = img.load()
    for y in range(h):
        for i in range(pad):
            row = y + pad
            left = src[0, y]
            right = src[w - 1, y]
            for x in range(pad):
                px[x, row] = left
                px[w + pad + x, row] = right
    for x in range(w):
        for i in range(pad):
            col = x + pad
            top = src[x, 0]
            bottom = src[x, h - 1]
            for y in range(pad):
                px[col, y] = top
                px[col, h + pad + y] = bottom
    for x in range(pad):
        for y in range(pad):
            px[x, y] = src[0, 0]
            px[w + pad + x, y] = src[w - 1, 0]
            px[x, h + pad + y] = src[0, h - 1]
            px[w + pad + x, h + pad + y] = src[w - 1, h - 1]
    return out


def _shelf_pack(cells, page: int):
    """确定性 shelf 装箱：cells = [(rel, w, h)]（含 padding 的格子），按 (-h, -w, rel)
    排序，行内左→右、行高取行内最大。放不下返回 None（调用方换更大页）。"""
    pos = {}
    x = y = row_h = 0
    for rel, w, h in cells:
        if w > page or h > page:
            return None
        if x + w > page:
            x = 0
            y += row_h
            row_h = 0
        if y + h > page:
            return None
        pos[rel] = (x, y)
        x += w
        row_h = max(row_h, h)
    return pos


def pack_atlas(out_dir, root=None, add_spec=None) -> dict:
    """打包世界精灵为单页图集 + 区域清单。add_spec(rel, purpose, current, note)
    供管线把产物登记进 SPEC（prune 白名单）；缺省 None（standalone/测试路径）。"""
    if Image is None:
        raise ImportError("Pillow 不可用：全图集生成拒绝静默跳过（m2-t37 fail-closed）")
    out_dir = Path(out_dir)
    root = Path(root) if root is not None else out_dir
    out_atlas = out_dir / "atlas"
    out_atlas.mkdir(parents=True, exist_ok=True)

    items = []   # (rel, w, h, pil_img)
    for rel, p in _iter_sources(root):
        img = Image.open(p).convert("RGBA")
        if max(img.size) > MAX_SPRITE_DIM:
            raise RuntimeError(f"图集拒绝超限精灵 {rel} {img.size} > {MAX_SPRITE_DIM}px")
        if img.size[0] <= 0 or img.size[1] <= 0:
            raise RuntimeError(f"图集拒绝空精灵 {rel} {img.size}")
        items.append((rel, img.size[0], img.size[1], img))

    cells = sorted(
        ((rel, w + PAD * 2, h + PAD * 2) for rel, w, h, _img in items),
        key=lambda c: (-c[2], -c[1], c[0]),
    )
    page = MIN_PAGE
    pos = _shelf_pack(cells, page)
    while pos is None:
        page *= 2
        if page > MAX_PAGE:
            raise RuntimeError(
                f"图集装不进 {MAX_PAGE}x{MAX_PAGE} 页（{len(cells)} 格）——拒绝入库，"
                "请收缩素材或评估 VRAM 预算后再放宽 MAX_PAGE")
        pos = _shelf_pack(cells, page)

    page_img = Image.new("RGBA", (page, page), (0, 0, 0, 0))
    entries = {}
    for rel, w, h, img in items:
        cx, cy = pos[rel]
        page_img.paste(_extrude(img, PAD), (cx, cy))
        entries[rel] = [cx + PAD, cy + PAD, w, h]

    page_img.save(out_atlas / PAGE_NAME)
    manifest = {
        "page": PAGE_NAME,
        "size": [page, page],
        "padding": PAD,
        "count": len(entries),
        "entries": entries,
    }
    (out_atlas / MANIFEST_NAME).write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=1) + "\n",
        encoding="utf-8")

    if add_spec is not None:
        add_spec(f"atlas/{PAGE_NAME}", "全图集单页（m2-t37 §18.3 全图集前提）",
                 "运行时经 core/art/art_atlas.gd 按 atlas.json 区域取样（AtlasTexture 共页）",
                 "由 tools/gen_art_atlas.py 生成；tiles/* 与 *_sheet.png 排除（repeat/帧表不兼容）")
        add_spec(f"atlas/{MANIFEST_NAME}", "全图集区域清单（m2-t37）",
                 "ArtLookup.tex 按相对路径查区域；缺表回落逐文件纹理（fail-closed）",
                 "确定性 shelf 装箱 + 2px 边缘外扩；重跑幂等")
    return manifest


def main() -> None:
    root = Path(sys.argv[sys.argv.index("--root") + 1]) if "--root" in sys.argv else None
    out = Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv else None
    if out is None:
        out = root if root is not None else Path(__file__).resolve().parent.parent / "art" / "generated"
    m = pack_atlas(out, root)
    print(f"[atlas] {m['count']} sprites -> {out / 'atlas' / PAGE_NAME} "
          f"({m['size'][0]}x{m['size'][1]}, pad={m['padding']})")


if __name__ == "__main__":
    main()
