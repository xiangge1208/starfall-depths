# -*- coding: utf-8 -*-
"""M5-B 六 Boss 专属橙武器素材生成器（增量，勿跑 gen_placeholder_art_m2 全量）。

产出 12 张 16x16 PNG（幂等：同输入逐字节同输出，可安全重跑）：
    art/generated/ui/weapons/<id>.png   图标（右上 legend 稀有度角标）
    art/generated/weapons/<id>.png      手持精灵（朝右 0°，持握点(4,8)，muzzle=8px）

行清单 = data/weapons.json 中 boss_exclusive:true 的行（单一事实源，跑前自校验恰 6 行；
新行未入 weapons.json 时 hard fail，防素材与数据漂移）。

风格约定与 gen_placeholder_art(_m2) 一致：元素色刀身/弹头 + legend 橙角标 + 深色描边；
纯确定性像素模板，无随机数（比固定 seed 更强的幂等）。跑完请执行：
    python tools/gen_art_atlas.py        # 重打包全图集（atlas_page/atlas.json）
"""
import json
from pathlib import Path

try:
    from PIL import Image
except ImportError:   # 入口统一 hard-fail（拒绝静默跳过，同 m2-t37 口径）
    raise SystemExit("Pillow 不可用：M5-B 素材生成拒绝静默跳过")

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated"

# 调色板（与 gen_placeholder_art.py 同源锚点）
METAL = (200, 208, 220, 255)
DARK = (122, 132, 150, 255)
WOOD = (138, 106, 60, 255)
WOOD_L = (168, 133, 78, 255)
OUTLINE = (24, 20, 32, 255)
LEGEND = (255, 166, 77, 255)
ELEM = {"fire": (255, 106, 46, 255), "ice": (138, 232, 255, 255),
        "poison": (138, 216, 74, 255), "shock": (224, 176, 255, 255),
        "none": (184, 200, 224, 255)}


def _canvas():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))


def _px(img, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        img.putpixel((int(x), int(y)), c)


def _rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            _px(img, x, y, c)


def _outline(img):
    """透明像素邻接不透明 → 深色描边（同 gen_placeholder_art.outline）。"""
    im = img.load()
    src = img.copy().load()
    for y in range(16):
        for x in range(16):
            if im[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 16 and 0 <= ny < 16 and src[nx, ny][3] != 0:
                    im[x, y] = OUTLINE
                    break


# ---------------------------------------------------------------- 六把专属橙

def _draw_tengmanjiaobian(img, e):
    """藤蔓绞鞭（melee/poison）：棕柄 + 藤绿 S 形长鞭 + 深绿倒钩刺。"""
    _rect(img, 2, 8, 3, 9, WOOD)                     # 持握点(4,8) 前的短柄
    pts = [(4, 9), (5, 8), (6, 7), (7, 8), (8, 9), (9, 8),
           (10, 7), (11, 6), (12, 5), (13, 4), (14, 3)]
    for i, (x, y) in enumerate(pts):
        _px(img, x, y, e)
        _px(img, x, y + 1, e if i % 2 == 0 else _dark(e))
        if i % 3 == 1:
            _px(img, x, y - 1, _dark(e))             # 倒钩刺
    _px(img, 14, 2, _light(e))                       # 鞭梢亮芯


def _draw_fenghoulengci(img, e):
    """蜂后棱刺（pistol/none 三晶棘）：短枪身 + 枪口三根水晶刺。"""
    _rect(img, 3, 7, 8, 9, METAL)                    # 枪身
    _rect(img, 3, 10, 5, 12, DARK)                   # 握把
    _rect(img, 8, 8, 10, 8, DARK)                    # 枪管
    for dy, slope in ((-1, (0, 0, -1)), (0, (0, 0, 0)), (1, (0, 0, 1))):
        for k in range(3):                           # 三向晶棘（projectiles 3）
            _px(img, 11 + k, 8 + dy + slope[k], e)
        _px(img, 11, 8 + dy, _light(e))
    _px(img, 5, 7, WOOD_L)                           # 蜂巢护木
    _px(img, 6, 7, WOOD_L)


def _draw_jinglenguanchuan(img, e):
    """晶棱贯穿（laser/pierce 3）：棱镜长枪身 + 贯穿晶柱通轴。"""
    _rect(img, 2, 7, 4, 9, WOOD)                     # 托
    _rect(img, 5, 7, 10, 9, METAL)
    _rect(img, 11, 8, 14, 8, DARK)                   # 长管
    for x in range(6, 15):                           # 贯穿晶柱（透管轴线）
        _px(img, x, 8, e if x % 2 == 0 else _light(e))
    _rect(img, 7, 5, 8, 6, _light(e))                # 棱镜镜座
    _px(img, 6, 5, e)
    _px(img, 9, 5, e)


def _draw_shuangzhurensi(img, e):
    """霜蛛韧丝（smg/ice bounce 4）：紧凑机身体 + 冰丝蛛网涟纹。"""
    _rect(img, 3, 7, 8, 9, METAL)
    _rect(img, 4, 10, 6, 11, DARK)
    _rect(img, 9, 8, 10, 8, DARK)
    _px(img, 11, 8, e)                               # 冰丝射口
    for i, (dx, dy) in enumerate(((1, -1), (2, 0), (3, -1), (4, 0))):
        _px(img, 11 + dx, 8 + dy, e if i % 2 == 0 else _light(e))   # 波状韧丝
    _px(img, 12, 7, _light(e))                       # 网结
    _px(img, 14, 7, _light(e))
    _px(img, 13, 9, e)


def _draw_ronghepenliu(img, e):
    """熔核喷流（rifle/fire pierce 1）：长枪身 + 通体熔岩芯线 + 枪口喷口。"""
    _rect(img, 2, 7, 4, 9, WOOD)
    _rect(img, 5, 7, 11, 9, METAL)
    _rect(img, 12, 7, 14, 9, DARK)                   # 加粗喷口
    for x in range(5, 13):                           # 熔岩芯线
        _px(img, x, 8, e)
        if x % 2 == 1:
            _px(img, x, 7, _light(e))                # 上沿辉光
    _px(img, 15, 8, e)                               # 喷流
    _px(img, 6, 10, DARK), _px(img, 7, 10, DARK)     # 散热鳍


def _draw_shuangziyunxing(img, e):
    """双子陨星（staff/shock 双弹）：木杖顶并列两颗星辉陨星。"""
    for y in range(6, 15):                           # 杖身（持握点(4,8)）
        _px(img, 4, y, WOOD)
        _px(img, 5, y, WOOD_L if y % 3 == 0 else WOOD)
    _rect(img, 2, 4, 3, 5, e)                        # 双子星·左
    _px(img, 2, 4, _light(e))
    _rect(img, 6, 4, 7, 5, e)                        # 双子星·右
    _px(img, 7, 4, _light(e))
    _px(img, 4, 4, WOOD_L), _px(img, 5, 4, WOOD_L)   # 杖头托架
    _px(img, 1, 3, _light(e)), _px(img, 8, 3, _light(e))   # 星芒


DRAWERS = {
    "tengmanjiaobian": _draw_tengmanjiaobian,
    "fenghoulengci": _draw_fenghoulengci,
    "jinglenguanchuan": _draw_jinglenguanchuan,
    "shuangzhurensi": _draw_shuangzhurensi,
    "ronghepenliu": _draw_ronghepenliu,
    "shuangziyunxing": _draw_shuangziyunxing,
}


def _dark(c):
    return (max(c[0] - 60, 0), max(c[1] - 60, 0), max(c[2] - 40, 0), 255)


def _light(c):
    return (min(c[0] + 50, 255), min(c[1] + 50, 255), min(c[2] + 50, 255), 255)


def _save(img, relpath):
    p = OUT / relpath
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p)


def main():
    rows = json.loads((ROOT / "data" / "weapons.json").read_text(encoding="utf-8"))
    boss_rows = {wid: row for wid, row in rows.items()
                 if bool(row.get("boss_exclusive", False))}
    missing = sorted(set(DRAWERS) - set(boss_rows))
    extra = sorted(set(boss_rows) - set(DRAWERS))
    if missing or extra:
        raise SystemExit(f"M5-B 行清单漂移：缺画笔 {missing} / 多余行 {extra}"
                         "—— weapons.json boss_exclusive 行与 DRAWERS 必须一一对应")
    for wid, row in sorted(boss_rows.items()):
        elem = ELEM.get(str(row.get("element", "none")))
        if elem is None:
            raise SystemExit(f"M5-B：武器 {wid} 元素 '{row.get('element')}' 无调色板行")
        # 手持（无角标）
        img = _canvas()
        DRAWERS[wid](img, elem)
        _outline(img)
        _save(img, f"weapons/{wid}.png")
        # 图标（同形 + legend 稀有度角标）
        img = _canvas()
        DRAWERS[wid](img, elem)
        _rect(img, 13, 0, 15, 2, LEGEND)
        _outline(img)
        _save(img, f"ui/weapons/{wid}.png")
        print(f"[m5b] {wid} 「{row.get('name')}」 -> weapons/ + ui/weapons/")
    print(f"[m5b] {len(boss_rows)} weapons x2 sprites done (idempotent)")


if __name__ == "__main__":
    main()
