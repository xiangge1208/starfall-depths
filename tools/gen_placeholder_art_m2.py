# -*- coding: utf-8 -*-
"""M2 占位素材生成器（三生态/新角色/新 Boss/武器 115/增益 36/局外 UI）。

用法:
    python tools/gen_placeholder_art.py      # 已自动串联本脚本（推荐入口）
    python tools/gen_placeholder_art_m2.py   # 单独重跑 M2 批次（先调 M1 全量再生）

命名约定（m2-t21 收编后口径）:
    - 武器/敌人/增益 id 一律以 data/*.json 落地行为准（数据驱动出图，暂定拼音 slug 废除）；
    - 仅 M2 Boss 5 种（gem_queen 等）尚无 data 行，slug 仍为附录 E 暂定名，
      待 Boss 数据卡落地后如需改名，改本表 slug 重跑即可（清单同步更新）。
"""
import json
import math
import random
from pathlib import Path

# base 模块由 generate(caller) 注入（调用方即运行中的 M1 脚本模块对象），
# 避免脚本模式下 import 产生第二副本导致清单统计分离。
base = None
OUT = None

# ---------------------------------------------------------------- 武器 115
# m2-t21 管线收编（裁定⑪）：武器 id/名称/类别/稀有/元素以 data/weapons.json（T6 附录 A
# 115 行）为**唯一权威**，逐行读表驱动出图；旧 NEW_WEAPONS 75 暂定拼音 slug 全部废除
# （65 个与正式 id 重合、10 个非正式 slug 已随全量再生清出 art/generated）。
# 数据类别 "throw"（附录 A 投掷）映射模板键 "throwable"。
WEAPON_CAT_KEYS = {"throw": "throwable"}

def _hh_sniper(img, elem, acc):
    rect(img, 1, 7, 3, 9, WOOD)            # 托
    rect(img, 4, 6, 9, 9, METAL)
    rect(img, 9, 7, 15, 8, DARK)           # 全长炮管
    rect(img, 5, 4, 8, 5, DARK)
    px(img, 5, 4, acc)                     # 镜
    vline(img, 12, 9, 11, DARK)            # 两脚架
    px(img, 11, 12, DARK), px(img, 13, 12, DARK)
    px(img, 8, 7, elem)


def _hh_throwable(img, elem, acc):
    body = elem if elem != C("#8a97ad") else C("#4a5468")
    disk(img, 10, 9, 4, body)
    px(img, 8, 7, shade(body, 1.5))
    vline(img, 10, 3, 5, WOOD_L)           # 引信
    px(img, 10, 2, C("#ffd94a"))
    px(img, 11, 1, C("#fff3b8"))
    rect(img, 3, 8, 5, 10, WOOD)           # 握持部
    px(img, 4, 8, acc)


def _hh_special(img, elem, acc):
    rect(img, 4, 5, 12, 11, METAL)
    rect(img, 4, 5, 12, 6, shade(METAL, 1.2))
    disk(img, 11, 8, 2, elem)
    px(img, 11, 7, shade(elem, 1.4))
    rect(img, 5, 7, 7, 9, DARK)
    px(img, 6, 8, acc)
    vline(img, 13, 2, 4, DARK)             # 天线
    px(img, 13, 1, C("#ff5a4a"))
    rect(img, 6, 12, 8, 13, DARK)


HH_TEMPLATES_M2 = {"sniper": _hh_sniper, "throwable": _hh_throwable, "special": _hh_special}


def gen_weapons_m2():
    """115 把武器图标 + 手持图 —— data/weapons.json 全表数据驱动（m2-t21 收编，
    武器美术唯一出口；M1 侧 gen_weapon_icons/gen_weapons_handheld 已删除防双写）。"""
    existing = json.load(open(OUT.parent.parent / "data" / "weapons.json", encoding="utf-8"))
    rows = []
    for wid, row in existing.items():
        rows.append((wid, str(row.get("name", wid)), str(row.get("category", "pistol")),
                     str(row.get("rarity", "common")), str(row.get("element", "none"))))
    assert len(rows) == 115, f"附录 A 武器全集应为 115 把, data/weapons.json 实际 {len(rows)} 行"
    for wid, name, cat, rar, elem in rows:
        key = WEAPON_CAT_KEYS.get(cat, cat)
        elem_c = C(base.ELEM_COL.get(elem, "#8a97ad"))
        acc = C(RARITY.get(rar, "#cfd2d6"))
        star = "（熔铸限定★）" if "★" in name else ""
        # 图标
        img = canvas(16, 16)
        fn = base.ICON_TEMPLATES.get(key)
        if fn is not None:
            fn(img, elem_c)
        else:  # M2 新类别: 狙击/投掷/特殊
            hh = HH_TEMPLATES_M2.get(key)
            assert hh is not None, f"武器类别 {cat}({key}) 无图标画笔（ICON_TEMPLATES/HH_TEMPLATES_M2 均缺行）"
            hh(img, elem_c, acc)
        rect(img, 13, 0, 15, 2, acc)   # 稀有度角标
        outline(img)
        save(img, f"ui/weapons/{wid}.png", f"武器图标「{name.strip('★')}」({cat}/{rar}){star}",
             "附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编）",
             "左上角标=稀有度, 刀身/弹头色=元素")
        # 手持
        img = canvas(16, 16)
        if key in HH_TEMPLATES_M2:
            HH_TEMPLATES_M2[key](img, elem_c, acc)
        elif wid == "shuangbi":
            base.hh_dagger(img, elem_c, acc)
        else:
            base.templates_hh.get(key, base.hh_pistol)(img, elem_c, acc)
        outline(img)
        save(img, f"weapons/{wid}.png", f"手持武器「{name.strip('★')}」({cat}){star}",
             "weapon_rig.gd 无武器外观; muzzle=8px", "朝右0°, 持握点(4,8), 朝左 flip_v")


def generate(caller=None):
    """M2 批次入口（由 M1 脚本 main() 末尾自动调用并传入其模块对象）。

    直接运行本脚本时走 main() -> base.main()，保持清单/联络表单一出口。"""
    global base, OUT
    if base is None:
        import gen_placeholder_art as _b
        base = caller if caller is not None else _b
    elif caller is not None:
        base = caller
    OUT = base.OUT
    g = globals()
    for n in ("C", "rect", "hline", "vline", "px", "canvas", "disk", "ring",
              "outline", "eyes", "shade", "noise", "save", "RARITY"):
        g[n] = getattr(base, n)
    g["METAL"], g["DARK"], g["WOOD"], g["WOOD_L"] =         base.C("#c8d0dc"), base.C("#7a8496"), base.C("#8a6a3c"), base.C("#a8854e")
    gen_weapons_m2()
    gen_enemies_m2()
    gen_enemy_sheets_m2()
    gen_heroes_m2()
    gen_buffs_m2()
    gen_tiles_m2()
    gen_ui_m2()


# ---------------------------------------------------------------- 敌人 40 + Boss 6
# (slug, 名称, 生态, 原型, 特征, 现状/备注)  —— 附录 B；已有 7 种在 M1 脚本，不重复。
BIOME_PAL = {
    "A1": ("#57a03f", "#7ec463", "#2e6b21"),
    "A2": ("#4a8ab8", "#7ec4e8", "#1f4a66"),
    "A3": ("#b8502e", "#e88a4a", "#6b2414"),
    "SLIME": ("#5aa05a", "#8ad88a", "#2e6b3f"),
    "MINIBOSS": ("#a8865a", "#d8b478", "#5c4526"),
}


def _mob(arch, pal, feats):
    """按原型+生态色出 16x16 小怪剪影。feats: crystal/lava/shell/fuse/one_eye/petal/turret/wings"""
    body, light, dark = (C(h) for h in pal)
    img = canvas(16, 16)
    if arch == "charger":
        rect(img, 3, 5, 12, 12, body)
        rect(img, 3, 5, 12, 6, light)
        rect(img, 10, 2, 14, 7, body)
        eyes(img, 12, 4, gap=1, pupil=dark)
        for x in (4, 7, 10):
            rect(img, x, 13, x + 1, 14, dark)
    elif arch == "shooter":
        img = base.hero_base(body, cloak=base.shade(body, 0.72))
        rect(img, 3, 0, 12, 2, light)
        hline(img, 9, 14, 7, dark)
        px(img, 14, 7, light)
    elif arch == "wanderer":
        for s in (-1, 1):
            for i in range(5):
                px(img, 8 + s * (2 + i), 7 + (1 if i > 2 else 0), dark)
                px(img, 8 + s * (2 + i), 8, body)
        disk(img, 8, 8, 3, body)
        px(img, 6, 4, body), px(img, 10, 4, body)
        eyes(img, 8, 8, gap=1, white=C("#ff5a4a"), pupil=C("#701c14"))
    elif arch == "suicide":
        disk(img, 8, 10, 5, body)
        disk(img, 8, 10, 3, light)
        eyes(img, 8, 9, gap=2, pupil=dark)
        vline(img, 8, 3, 5, dark)
        px(img, 7, 2, C("#ffd94a")), px(img, 9, 2, C("#ffd94a"))
    elif arch == "barrage":
        rect(img, 6, 9, 9, 14, C("#e8dcc0"))
        rect(img, 3, 4, 12, 9, body)
        hline(img, 3, 12, 4, light)
        eyes(img, 8, 11, gap=1)
    elif arch == "summoner":
        rect(img, 7, 8, 8, 14, C("#4a7a3c"))
        disk(img, 8, 5, 4, body)
        disk(img, 8, 5, 2, C("#ffd94a"))
        for a in range(0, 360, 60):
            px(img, 8 + int(math.cos(math.radians(a)) * 5), 5 + int(math.sin(math.radians(a)) * 5), light)
        eyes(img, 8, 10, gap=1)
    elif arch == "tank":
        disk(img, 8, 10, 6, dark)
        rect(img, 2, 8, 13, 12, body)
        hline(img, 2, 13, 8, light)
        rect(img, 11, 4, 14, 8, body)
        eyes(img, 13, 6, gap=0, pupil=dark)
        rect(img, 4, 13, 5, 14, dark)
        rect(img, 9, 13, 10, 14, dark)
    elif arch == "turret":
        rect(img, 3, 10, 12, 14, dark)
        rect(img, 4, 9, 11, 11, body)
        rect(img, 7, 3, 8, 9, dark)
        px(img, 7, 2, light)
        rect(img, 8, 4, 10, 5, light)
    elif arch == "splitter":
        disk(img, 8, 11, 5, body)
        disk(img, 8, 11, 3, light)
        hline(img, 5, 11, 9, C("#ffffff", 90))
        eyes(img, 8, 10, gap=2, pupil=dark)
        px(img, 4, 14, body), px(img, 12, 14, body)
    # 特征件
    if "shell" in feats:
        ring(img, 8, 9, 6, dark, 1)
        hline(img, 3, 12, 6, light)
    if "crystal" in feats:
        for x, y in ((5, 4), (8, 2), (11, 4)):
            px(img, x, y, C("#8ae8ff"))
            px(img, x, y + 1, C("#c8f0ff"))
    if "lava" in feats:
        for _ in range(6):
            fx, fy = 4 + (len(str(feats)) * 3) % 8, 8 + (len(str(pal)) * 5) % 6
            px(img, fx, fy, C("#ff8a2e"))
    if "fuse" in feats:
        px(img, 8, 2, C("#ffd94a"))
    if "one_eye" in feats:
        disk(img, 8, 8, 2, C("#f4f4f0"))
        px(img, 8, 9, C("#20242c"))
    return img


MOBS_M2 = [
    # 通用 4（苦力虫/穴蝠/弩兵已有）+ 各生态 12（藤蔓冲锋者/蘑菇孢子手已有）
    ("mud_slime", "泥浆史莱姆", "通用", "splitter", "SLIME", "", "附录 B.1 分裂原型；死亡裂 2 小体"),
    ("hardshell_turtle", "硬壳龟", "A1", "tank", "A1", "shell", "正面减伤 80%, 龟缩免疫"),
    ("wing_lizard", "飞行翼蜥", "A1", "wanderer", "A1", "", "低空绕行+切线俯冲"),
    ("thorn_turret", "荆棘炮台", "A1", "turret", "A1", "", "固定抛物 3 连发"),
    ("spore_flower", "孢子召唤花", "A1", "summoner", "A1", "petal", "每 4s 出 1 苦力虫(上限 3)"),
    ("stone_boar", "石皮野猪", "A1", "charger", "A1", "shell", "受击后狂暴冲锋"),
    ("ruin_archer", "遗迹弓手", "A1", "shooter", "A1", "", "后撤步+射击交替"),
    ("moss_slime", "苔藓史莱姆", "A1", "splitter", "SLIME", "", "死亡分裂 2"),
    ("glowbug_swarm", "萤光虫群", "A1", "suicide", "A1", "fuse", "3 只一组扑向玩家"),
    ("old_tree_guard", "老树守卫", "A1", "tank", "A1", "", "缓慢逼近+根部弹环"),
    ("seed_pitcher", "种子投手", "A1", "barrage", "A1", "", "抛物种子落地 30% 生虫"),
    ("crystal_bat", "晶簇蝙蝠", "A2", "wanderer", "A2", "crystal", "死亡爆 4 向晶针"),
    ("ice_mage", "冰晶法师", "A2", "barrage", "A2", "crystal", "冰环弹+冰缓"),
    ("magnet_golem", "磁石傀儡", "A2", "tank", "A2", "crystal", "把玩家拉拽 2 格"),
    ("ghost_jelly", "幽光水母", "A2", "wanderer", "A2", "one_eye", "电弧链, 漂移无规律"),
    ("frost_crab", "冻土巨蟹", "A2", "tank", "A2", "shell", "横向钳击(预警扇区)"),
    ("crystal_rat", "窃晶鼠群", "A2", "suicide", "A2", "crystal", "4 只散兵, 偷 5 金后逃跑"),
    ("rock_crystal_turret", "岩晶炮台", "A2", "turret", "A2", "crystal", "蓄能直线激光(0.5s 警示线)"),
    ("crystal_summoner", "晶核召唤师", "A2", "summoner", "A2", "crystal", "每 5s 召 2 窃晶鼠"),
    ("prism_ranger", "棱镜游侠", "A2", "shooter", "A2", "crystal", "借晶柱折射(拐角弹)"),
    ("ice_spider", "冰蛛", "A2", "splitter", "A2", "", "3 只结网(1.5s 禁锢)"),
    ("echo_lurker", "深窟回响者", "A2", "barrage", "A2", "one_eye", "模仿玩家上次武器弹形"),
    ("crystal_dragon", "晶背龙蜥", "A2", "charger", "A2", "crystal", "撞墙自晕 1s(输出窗)"),
    ("lava_hound", "熔岩犬", "A3", "charger", "A3", "lava", "两段扑咬, 附带燃烧"),
    ("ash_shooter", "灰烬射手", "A3", "shooter", "A3", "", "3 连发点射"),
    ("firerain_priest", "火雨祭司", "A3", "barrage", "A3", "lava", "召唤火雨区(红圈预警)"),
    ("magma_slime", "熔核史莱姆", "A3", "splitter", "SLIME", "lava", "分裂 2 中型再分裂"),
    ("obsidian_guard", "黑曜卫", "A3", "tank", "A3", "shell", "盾墙推进, 推动玩家"),
    ("sulfur_moth", "硫磺蛾群", "A3", "suicide", "A3", "fuse", "爆燃留燃烧地面"),
    ("lava_turret", "岩浆喷吐炮台", "A3", "turret", "A3", "lava", "扇形 5 喷发"),
    ("ember_summoner", "余烬召唤师", "A3", "summoner", "A3", "lava", "召 2 熔岩犬"),
    ("scorch_stomper", "焦土践踏者", "A3", "charger", "A3", "lava", "跺地引发环形火浪"),
    ("flame_lich", "烈焰巫妖", "A3", "barrage", "A3", "lava", "火墙推进弹"),
    ("magma_wyvern", "熔火飞龙", "A3", "wanderer", "A3", "lava", "俯冲喷吐直线火"),
    ("starmarrow_blob", "星髓聚合体", "A3", "barrage", "A2", "crystal", "随机切换 4 元素弹幕"),
    ("undead_gunner", "亡灵枪手(小Boss)", "MINIBOSS", "shooter", "MINIBOSS", "", "复制玩家武器弹形对枪"),
    ("stone_shield_monk", "石盾武僧(小Boss)", "MINIBOSS", "tank", "MINIBOSS", "shell", "正面格挡一切, 绕背破势"),
    ("volt_spider", "电磁蛛(小Boss)", "MINIBOSS", "splitter", "MINIBOSS", "crystal", "电弧链场, 杀小蛛断链"),
    ("marsh_toad", "腐沼巨蛙(小Boss)", "MINIBOSS", "splitter", "A1", "one_eye", "吞弹存伤害后吐还"),
]


def gen_enemies_m2():
    for slug, name, act, arch, biome, feats, note in MOBS_M2:
        img = _mob(arch, BIOME_PAL[biome], feats)
        if biome == "MINIBOSS":
            ring(img, 8, 8, 7, C("#e2c04c", 200), 1)  # 小 Boss 金环
        outline(img)
        save(img, f"enemies/{slug}.png", f"敌人「{name}」({act}/{arch})",
             f"附录 B（{act}）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块", note + "; slug 暂定待 data 落地对齐")
    gen_bosses_m2()


# Boss 5（48x48）——m4p-u2 拆独立入口：画笔全固定坐标（零 RNG），scoped 重生成与
# 全量管线逐字节同图（支持只补 Boss 图的窄通道，免整库重跑/触发 prune 风险）。
def gen_bosses_m2():
    def bee_queen():
        img = canvas(48, 48)
        disk(img, 24, 26, 12, C("#d8a828"))
        disk(img, 24, 26, 8, C("#f2cc60"))
        for y in (20, 26, 32):
            hline(img, 14, 34, y, C("#3a3444"))
        rect(img, 18, 8, 30, 16, C("#d8a828"))
        eyes(img, 24, 12, gap=4, white=C("#ff5a4a"), pupil=C("#701c14"))
        vline(img, 23, 2, 7, C("#3a3444"))
        for s in (-1, 1):
            disk(img, 24 + s * 16, 20, 8, C("#8ae8ff", 170))
            disk(img, 24 + s * 16, 20, 4, C("#d2f4ff", 200))
        rect(img, 18, 38, 21, 44, C("#3a3444"))
        rect(img, 27, 38, 30, 44, C("#3a3444"))
        px(img, 24, 26, C("#e83a8a"))
        return img
    def crystal_golem():
        img = canvas(48, 48)
        rect(img, 14, 14, 34, 40, C("#4a6a8a"))
        rect(img, 14, 14, 34, 18, C("#6a92b8"))
        for x, y, h in ((18, 8, 8), (24, 4, 12), (30, 8, 8)):
            for i in range(h):
                hline(img, x - (h - i) // 6, x + (h - i) // 6, y + i, C("#8ae8ff"))
        rect(img, 20, 24, 22, 27, C("#d2f4ff"))
        rect(img, 27, 24, 29, 27, C("#d2f4ff"))
        disk(img, 24, 33, 3, C("#8ae8ff"))
        px(img, 24, 33, C("#ffffff"))
        rect(img, 6, 18, 12, 34, C("#4a6a8a"))
        rect(img, 36, 18, 42, 34, C("#4a6a8a"))
        rect(img, 16, 41, 22, 46, C("#33485e"))
        rect(img, 26, 41, 32, 46, C("#33485e"))
        return img
    def frost_spider():
        img = canvas(48, 48)
        disk(img, 24, 30, 13, C("#6a92c8"))
        disk(img, 24, 30, 8, C("#a2c4e8"))
        for s in (-1, 1):
            for i in range(4):
                x0, y0 = 24 + s * (10 + i * 3), 26 + i * 2
                vline(img, x0, y0, 44 - i * 2, C("#4a6a9a"))
                px(img, x0 + s, 44 - i * 2, C("#4a6a9a"))
        eyes(img, 24, 16, gap=2, white=C("#ff5a4a"), pupil=C("#701c14"))
        px(img, 20, 12, C("#a2c4e8")), px(img, 28, 12, C("#a2c4e8"))
        for a in range(0, 360, 45):
            px(img, 24 + int(math.cos(math.radians(a)) * 16), 30 + int(math.sin(math.radians(a)) * 8), C("#d2f0ff"))
        return img
    def magma_tyrant():
        img = canvas(48, 48)
        rect(img, 12, 14, 36, 38, C("#5c2a1c"))
        rect(img, 12, 14, 36, 19, C("#7a3a24"))
        for i in range(10):
            px(img, 14 + (i * 7) % 20, 20 + (i * 5) % 16, C("#ff8a2e"))
        disk(img, 24, 10, 8, C("#5c2a1c"))
        eyes(img, 24, 9, gap=3, white=C("#ffd94a"), pupil=C("#5c1a08"))
        rect(img, 4, 16, 10, 36, C("#5c2a1c"))
        rect(img, 38, 16, 44, 36, C("#5c2a1c"))
        disk(img, 7, 14, 3, C("#ff8a2e"))
        disk(img, 41, 14, 3, C("#ff8a2e"))
        rect(img, 14, 39, 20, 46, C("#3a1a10"))
        rect(img, 28, 39, 34, 46, C("#3a1a10"))
        return img
    def starfall_prophet():
        img = canvas(48, 48)
        rect(img, 16, 12, 32, 40, C("#3a2a5c"))
        rect(img, 12, 20, 36, 40, C("#2a1c44"))
        disk(img, 24, 10, 9, C("#181226"))
        eyes(img, 24, 9, gap=3, white=C("#b06cff"), pupil=C("#e2c0ff"))
        for a in range(0, 360, 30):
            px(img, 24 + int(math.cos(math.radians(a)) * 12), 10 + int(math.sin(math.radians(a)) * 12), C("#8ad8ff"))
        disk(img, 24, 28, 3, C("#ffd94a"))
        px(img, 24, 28, C("#fff3b8"))
        for s in (-1, 1):
            for i in range(5):
                px(img, 24 + s * (12 + i), 20 + i * 2, C("#b06cff"))
        px(img, 8, 6, C("#8ad8ff"))
        px(img, 40, 40, C("#8ad8ff"))
        return img
    # m4p-u2（附录 E 暂定 slug 收编）：crystal_golem/frost_spider_mother 的 data 行
    # 已落地为 prism_golem/frost_widow（data/enemies.json Boss 行）——slug 对齐行 id
    # 重出图（旧文件随管线 prune 清出），画笔函数不变 → 像素逐字节同图只改名。
    for slug, name, fn, theme in (
        ("gem_queen", "宝石蜂后（A1-②）", bee_queen, "召唤蜂群+冲锋; P2 蜂巢柱可破坏掩体"),
        ("prism_golem", "晶棱魔像（A2-①）", crystal_golem, "激光借晶柱折射; P3 瞬移弹幕"),
        ("frost_widow", "寒渊蛛母（A2-②）", frost_spider, "铺冰面+蛛网禁锢; P3 冰晶牢笼"),
        ("magma_tyrant", "熔核暴君（A3-①）", magma_tyrant, "岩浆喷区+火雨; P3 地裂火浪"),
        ("starfall_prophet", "星陨先知（A3-②隐藏）", starfall_prophet, "全元素轮回+共鸣攻击"),
    ):
        img = fn()
        outline(img)
        save(img, f"enemies/{slug}.png", f"Boss「{name}」48x48",
             f"data/enemies.json {slug} 行 + boss_script {slug}.gd", theme)


# ---------------------------------------------------------------- 敌人 2 帧动画表 (m2-t21)
# enemies/<id>_sheet.png = 2 列(idle|walk) × 1 行，帧尺寸与单帧图一致（常规怪 16x16 → 32x16）。
# 契约（消费端 core/rooms/room_combat.gd）：Sprite hframes=2 vframes=1；
#   frame=0 idle；移动中 frame = (物理帧/8) % 2 两帧交替（与 T17 玩家 8t/帧同拍）。
# 纪律：本节**零共享 RNG**（walk 帧 = idle 帧像素整体下移 1px 的确定性变换）——
# 插入主流程不扰动其它子树字节（T17 英雄帧表同款纪律）。
_M2_MOBS_BY_SLUG = {m[0]: m for m in MOBS_M2}


def _regular_enemy_rows():
    """data/enemies.json 常规行（m2-t21 数据驱动口径）：剔除 elite_affixes 行
    （精英×2/小 Boss×4 —— 复用单帧基图 + 运行时染色/金环，不出帧表）与
    archetype=boss 行（48px 多阶段 Boss 另有规格）→ 附录 B 常规 40 种。"""
    enemies = json.load(open(OUT.parent.parent / "data" / "enemies.json", encoding="utf-8"))
    out = []
    for eid, row in enemies.items():
        if "elite_affixes" in row or str(row.get("archetype", "")) == "boss":
            continue
        out.append((eid, str(row.get("name", eid))))
    return out


def _enemy_idle_painter(eid):
    """常规敌 id → 单帧画笔：M2 附录 B 表驱动 _mob；M1 五种沿用 M1 画笔。
    返回 None = 两表均缺该行（roster 漂移，调用方 fail-loud）。"""
    if eid in _M2_MOBS_BY_SLUG:
        _slug, _name, _act, arch, biome, feats, _note = _M2_MOBS_BY_SLUG[eid]
        return lambda: _mob(arch, BIOME_PAL[biome], feats)
    m1_painters = {
        "kuli_bug": base.paint_kuli, "cave_bat": base.paint_bat,
        "crossbowman": base.paint_crossbow, "vine_charger": base.paint_charger,
        "mushroom_spore": base.paint_mushroom,
    }
    return m1_painters.get(eid)


def _walk_bob(img):
    """walk 帧 = idle 整体下移 1px（两帧步态的通用占位节拍；原底行裁出画布=迈步落足）。"""
    out = canvas(img.width, img.height)
    src = img.load()
    dst = out.load()
    for y in range(1, img.height):
        for x in range(img.width):
            if src[x, y - 1][3] != 0:
                dst[x, y] = src[x, y - 1]
    return out


def gen_enemy_sheets_m2():
    roster = _regular_enemy_rows()
    assert len(roster) == 40, f"附录 B 常规敌人应为 40 种, data/enemies.json 实际 {len(roster)} 行"
    for eid, name in roster:
        painter = _enemy_idle_painter(eid)
        assert painter is not None, f"敌人 {eid} 无单帧画笔（M1/M2 画笔表缺行）"
        idle = painter()
        outline(idle)
        w, h = idle.size
        sheet = base.Image.new("RGBA", (w * 2, h), (0, 0, 0, 0))
        sheet.paste(idle, (0, 0))
        sheet.paste(_walk_bob(idle), (w, 0))
        save(sheet, f"enemies/{eid}_sheet.png",
             f"敌人「{name}」2 帧动画表（列=idle+walk, {w}px/帧）",
             "room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1",
             "m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图")


# ---------------------------------------------------------------- 新英雄 4 + 技能/被动
def gen_heroes_m2():
    import gen_placeholder_art as _b
    heroes = [
        ("mage", "法师·烬", C("#8a6ab8"), C("#6a4a94"), "wizard",
         "skill_arcane_nova", "奥术新星(CD10s/蓝20): 120px 冰霜新星+冻结", "回响: 法杖/激光伤 +15%", "echo"),
        ("assassin", "刺客·蝉", C("#4a4a5c"), C("#33333f"), "hood",
         "skill_afterimage_slash", "残影斩(CD8s): 突进 220px 无敌, 2x30 伤", "掠影: 近战杀返 5 蓝+翻滚无 CD 1s", "swift_shadow"),
        ("engineer", "工程师·铆", C("#c88a3c"), C("#96682a"), "goggles",
         "skill_turret", "自动炮台(CD12s): 部署炮台(上限 2)", "备件: 开局/进层补便携炮台", "spare_parts"),
        ("guardian", "守护者·萄", C("#7a9ab8"), C("#54748f"), "halo",
         "skill_life_tide", "生命潮汐(CD14s/蓝30): 回 2HP+治疗法阵 3s", "祝福: 进层满盾+5% 伤(叠 4)", "blessing"),
    ]
    for hid, name, body, cloak, hat, skill, sdesc, pdesc, pid in heroes:
        img = base.hero_base(body, cloak=cloak)
        if hat == "wizard":
            rect(img, 2, 0, 13, 1, cloak)
            rect(img, 4, 1, 11, 2, cloak)
            rect(img, 6, 2, 9, 3, shade(cloak, 1.25))
            px(img, 13, 0, C("#ffd94a"))
        elif hat == "hood":
            rect(img, 3, 0, 12, 4, cloak)
            hline(img, 5, 10, 4, shade(body, 0.6))
            px(img, 6, 3, C("#e83a4a")), px(img, 9, 3, C("#e83a4a"))
        elif hat == "goggles":
            rect(img, 3, 2, 12, 4, C("#c8d0dc"))
            rect(img, 4, 3, 6, 4, C("#5ab0ff"))
            rect(img, 9, 3, 11, 4, C("#5ab0ff"))
            px(img, 13, 1, C("#e2c04c"))
        elif hat == "halo":
            hline(img, 5, 10, 0, C("#ffe86a"))
            hline(img, 4, 11, 2, C("#e2c04c"))
        rect(img, 13, 9, 14, 12, C("#5c4530"))  # 手持短械剪影
        outline(img)
        save(img, f"characters/hero_{hid}.png", f"英雄「{name}」站立像（正面）",
             "GDD §6 角色表; data/heroes.json M2 待加行", f"{pdesc}")
        # 头像
        src = img
        pimg = canvas(32, 32)
        pimg.paste(src.resize((24, 24), base.Image.NEAREST), (4, 2))
        for i in range(32):
            px(pimg, i, 31, C("#2a3444"))
            px(pimg, i, 0, C("#5ab0ff"))
        save(pimg, f"ui/portrait_{hid}.png", f"{name} 选人头像 32x32", "ui/hero_select.gd 卡片", "")
        # 技能图标
        simg = canvas(16, 16)
        if hid == "mage":
            disk(simg, 8, 8, 5, C("#8ae8ff", 120))
            for a in range(0, 360, 45):
                for r in range(4, 7):
                    px(simg, 8 + int(math.cos(math.radians(a)) * r), 8 + int(math.sin(math.radians(a)) * r), C("#d2f4ff"))
            px(simg, 8, 8, C("#ffffff"))
        elif hid == "assassin":
            rect(simg, 4, 3, 7, 9, C("#8a9ab8", 140))
            rect(simg, 8, 5, 11, 12, C("#5a6a88", 220))
            hline(simg, 3, 12, 7, C("#e8e4da"))
        elif hid == "engineer":
            rect(simg, 5, 8, 11, 13, C("#7a8496"))
            rect(simg, 7, 3, 9, 8, C("#c8d0dc"))
            hline(simg, 6, 10, 8, C("#ff8a2e"))
            px(simg, 8, 2, C("#ff5a4a"))
        elif hid == "guardian":
            disk(simg, 8, 9, 4, C("#8ae8a0", 150))
            ring(simg, 8, 9, 4, C("#5ae88a"), 1)
            for y, (a, b) in enumerate(((1, 3), (0, 7), (0, 7), (1, 6), (2, 5), (3, 4))):
                hline(simg, a, b, y + 1, C("#e83a4a"))
        outline(simg)
        save(simg, f"ui/{skill}.png", f"技能图标「{sdesc.split('(')[0]}」({_b_name(name)})", "GDD §6 技能表", sdesc)
        # 技能升级版
        pimg2 = base.Image.open(OUT / f"ui/{skill}.png").copy()
        rect(pimg2, 10, 10, 15, 15, C("#e2c04c"))
        vline(pimg2, 12, 11, 14, C("#5c4514"))
        hline(pimg2, 11, 13, 12, C("#5c4514"))
        hline(pimg2, 11, 13, 14, C("#5c4514"))
        save(pimg2, f"ui/{skill}_plus.png", f"技能升级版图标「{sdesc.split('(')[0]}+」", "GDD §6 蓝晶 1500/名解锁", "")
        # 被动图标
        bimg = canvas(12, 12)
        if pid == "echo":
            for r in (2, 4):
                ring(bimg, 6, 6, r, C("#b06cff"), 1)
            px(bimg, 6, 6, C("#e0d0ff"))
        elif pid == "swift_shadow":
            px(bimg, 3, 3, C("#8a9ab8", 130))
            hline(bimg, 2, 9, 6, C("#e8e4da"))
            px(bimg, 8, 8, C("#5a6a88"))
        elif pid == "spare_parts":
            rect(bimg, 3, 3, 9, 9, C("#c8d0dc"))
            disk(bimg, 6, 6, 1, C("#4a5468"))
            px(bimg, 6, 1, C("#c8d0dc")), px(bimg, 6, 11, C("#c8d0dc"))
            px(bimg, 1, 6, C("#c8d0dc")), px(bimg, 11, 6, C("#c8d0dc"))
        elif pid == "blessing":
            ring(bimg, 6, 5, 3, C("#ffe86a"), 1)
            hline(bimg, 4, 8, 9, C("#5ae88a"))
            px(bimg, 6, 10, C("#5ae88a"))
        outline(bimg)
        save(bimg, f"ui/passive_{pid}.png", f"被动图标（{pdesc.split(':')[0].split('：')[0]}·{name}）", "GDD §6 被动列", pdesc)


def _b_name(hero_name):
    return hero_name.split("·")[1] if "·" in hero_name else hero_name


# ---------------------------------------------------------------- 增益 36（M1 已 16 → 新增 20）
def gen_buffs_m2():
    painters = {}

    def g(name):
        def deco(fn):
            painters[name] = fn
            return fn
        return deco

    @g("hunter")
    def _(img):
        disk(img, 6, 6, 3, C("#e83a4a"))
        px(img, 6, 6, C("#ffd94a"))
        vline(img, 6, 1, 2, C("#e83a4a"))
        hline(img, 9, 11, 6, C("#e83a4a"))

    @g("resonance_amplify")
    def _(img):
        ring(img, 4, 6, 3, C("#ff8a2e"), 1)
        ring(img, 8, 6, 3, C("#8ae8ff"), 1)
        px(img, 6, 6, C("#ffffff"))

    @g("vengeance")
    def _(img):
        for i in range(5):
            hline(img, 3, 9 - abs(2 - i), 2 + i, C("#e83a4a"))
        hline(img, 4, 8, 9, C("#ff8a94"))

    @g("anti_fire")
    def _(img):
        rect(img, 4, 3, 8, 9, C("#8194ad"))
        hline(img, 5, 7, 5, C("#ff6a2e"))
        hline(img, 6, 6, 6, C("#ff6a2e"))

    @g("anti_ice")
    def _(img):
        rect(img, 4, 3, 8, 9, C("#8194ad"))
        vline(img, 6, 4, 8, C("#8ae8ff"))
        hline(img, 4, 8, 6, C("#8ae8ff"))

    @g("anti_poison")
    def _(img):
        rect(img, 4, 3, 8, 9, C("#8194ad"))
        disk(img, 6, 6, 2, C("#8ad84a"))

    @g("nerve_reflex")
    def _(img):
        ring(img, 6, 6, 4, C("#e0b0ff"), 1)
        vline(img, 6, 3, 6, C("#ffffff"))
        hline(img, 6, 8, 7, C("#ffffff"))

    @g("carapace")
    def _(img):
        disk(img, 6, 7, 4, C("#7a8a5a"))
        for x in (3, 6, 9):
            px(img, x, 4, C("#5a6a3c"))
        hline(img, 3, 9, 8, C("#5a6a3c"))

    @g("thorns")
    def _(img):
        disk(img, 6, 6, 3, C("#6a8a4a"))
        for a in range(0, 360, 60):
            px(img, 6 + int(math.cos(math.radians(a)) * 5), 6 + int(math.sin(math.radians(a)) * 5), C("#c8e88a"))

    @g("dash_extend")
    def _(img):
        hline(img, 1, 9, 6, C("#5ab0ff"))
        px(img, 10, 5, C("#5ab0ff"))
        px(img, 10, 7, C("#5ab0ff"))
        px(img, 11, 6, C("#5ab0ff"))
        hline(img, 1, 3, 3, C("#c8e0ff"))

    @g("phoenix")
    def _(img):
        for i, w in enumerate((3, 5, 7, 5)):
            hline(img, 6 - w // 2, 6 - w // 2 + w - 1, 4 + i, C("#ff8a2e"))
        for s in (-1, 1):
            px(img, 6 + s * 4, 4, C("#ffd94a"))
            px(img, 6 + s * 5, 3, C("#ff8a2e"))

    @g("wealth")
    def _(img):
        rect(img, 2, 8, 10, 9, C("#c8901c"))
        rect(img, 3, 6, 9, 7, C("#ffd94a"))
        disk(img, 6, 4, 2, C("#ffd94a"))
        px(img, 5, 3, C("#fff3b8"))

    @g("big_eater")
    def _(img):
        disk(img, 6, 7, 4, C("#e8dcc0"))
        rect(img, 3, 6, 9, 7, C("#c88a4a"))
        px(img, 5, 2, C("#e83a4a"))
        px(img, 7, 1, C("#e83a4a"))

    @g("pickup_magnet")
    def _(img):
        for s in (-1, 1):
            rect(img, 6 + s * 3 - (1 if s > 0 else 0), 2, 6 + s * 3, 6, C("#e83a4a"))
        ring(img, 6, 6, 4, C("#e83a4a"), 2)
        for s in (-1, 1):
            px(img, 6 + s * 4, 2, C("#c8d0dc"))
            px(img, 6 + s * 4, 3, C("#c8d0dc"))

    @g("energy_leech")
    def _(img):
        disk(img, 5, 4, 2, C("#5aa0ff"))
        px(img, 5, 6, C("#c8e0ff"))
        px(img, 5, 8, C("#c8e0ff"))
        hline(img, 7, 10, 9, C("#5aa0ff"))

    @g("heart_sense")
    def _(img):
        for y, (a, b) in enumerate(((2, 4), (1, 9), (1, 9), (2, 7), (3, 6))):
            hline(img, a, b, y + 3, C("#e83a4a"))
        px(img, 2, 5, C("#ff8a94"))
        px(img, 10, 2, C("#ff8a94"))

    @g("ammo_convert")
    def _(img):
        rect(img, 3, 2, 5, 6, C("#ffd94a"))
        px(img, 4, 1, C("#fff3b8"))
        ring(img, 7, 8, 2, C("#5ab0ff"), 1)
        px(img, 10, 6, C("#5ab0ff"))

    @g("haggle")
    def _(img):
        rect(img, 2, 3, 9, 9, C("#8a6a3c"))
        px(img, 3, 4, C("#c8d0dc"))
        vline(img, 5, 5, 8, C("#fff3b8"))
        hline(img, 4, 7, 6, C("#fff3b8"))

    @g("element_vision")
    def _(img):
        disk(img, 6, 6, 4, C("#e2c04c"))
        disk(img, 6, 6, 2, C("#5c4514"))
        px(img, 6, 6, C("#ffffff"))
        px(img, 1, 1, C("#ff6a2e"))
        px(img, 11, 1, C("#8ae8ff"))
        px(img, 1, 11, C("#8ad84a"))
        px(img, 11, 11, C("#e0b0ff"))

    @g("resonance_vision")
    def _(img):
        disk(img, 6, 6, 4, C("#20242c"))
        ring(img, 6, 6, 4, C("#5ab0ff"), 1)
        px(img, 4, 6, C("#ff6a2e"))
        px(img, 8, 6, C("#8ae8ff"))

    new_buffs = [
        ("hunter", "猎杀者", "blue", "对异常目标伤害 +20%"),
        ("resonance_amplify", "共鸣增幅", "blue", "共鸣 AoE +30%/持续 +1s"),
        ("vengeance", "复仇者", "blue", "受击后 3s 伤害 +25%"),
        ("anti_fire", "抗火", "common", "免疫燃烧; 岩浆伤 -50%"),
        ("anti_ice", "抗冰", "common", "免疫冰缓与打滑"),
        ("anti_poison", "抗毒", "common", "免疫中毒"),
        ("nerve_reflex", "神经反射", "uncommon", "受击无敌帧 +0.25s"),
        ("carapace", "甲壳", "uncommon", "弹幕伤害 -8%"),
        ("thorns", "荆棘护甲", "uncommon", "被接触反伤 3"),
        ("dash_extend", "冲刺延伸", "blue", "翻滚距离 +25%"),
        ("phoenix", "不死鸟(唯一)", "blue", "致死保留 1 HP(每局 1 次)"),
        ("wealth", "财富", "common", "金币获取 +20%"),
        ("big_eater", "大胃王", "common", "饮料效果 +50%"),
        ("pickup_magnet", "捡拾磁铁", "common", "拾取范围 +60%"),
        ("energy_leech", "蓝能汲取", "uncommon", "击杀 10% 回 2 蓝"),
        ("heart_sense", "红心感应", "uncommon", "红心掉率 +50%"),
        ("ammo_convert", "弹药转化", "uncommon", "每 30s 回 10 蓝"),
        ("haggle", "议价", "blue", "商店价格 -15%"),
        ("element_vision", "元素视界", "blue", "预警 +0.15s 更醒目"),
        ("resonance_vision", "共鸣视界", "blue", "异常敌人高亮描边"),
    ]
    for bid, name, rar, effect in new_buffs:
        img = canvas(12, 12)
        painters[bid](img)
        outline(img)
        save(img, f"ui/buffs/{bid}.png", f"Buff 图标「{name}」({rar})",
             "附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定）", effect)
    # 16+20=36 校验由 data/buffs.json M2 行落地时对齐


# ---------------------------------------------------------------- 生态地砖/危险地块/设施/事件/局外 UI
def gen_tiles_m2():
    # A2 晶核洞穴
    img = base.tile_floor(C("#1c2438"), C("#242e48"), C("#141a2c"))
    for _ in range(5):
        px(img, base.RNG.randint(1, 14), base.RNG.randint(1, 14), C("#8ae8ff", 160))
    save(img, "tiles/floor_crystal.png", "A2 晶核洞穴地板", "GDD §10 A2 生态（暂无实现）", "替换需 16x16 无缝")
    img = base.tile_wall(C("#4a5a78", ), C("#33405c"), C("#5e7292"))
    save(img, "tiles/wall_crystal.png", "A2 晶核洞穴墙体", "同上", "顶部亮色已内嵌")
    # A3 熔火核心
    img = base.tile_floor(C("#241418"), C("#2e1a20"), C("#180e12"))
    for _ in range(4):
        x, y = base.RNG.randint(2, 12), base.RNG.randint(2, 12)
        px(img, x, y, C("#ff8a2e", 200))
        px(img, x + 1, y, C("#e84a1e", 160))
    save(img, "tiles/floor_magma.png", "A3 熔火核心地板", "GDD §10 A3 生态", "")
    img = base.tile_wall(C("#4a2e30"), C("#332022"), C("#5f3e42"))
    save(img, "tiles/wall_magma.png", "A3 熔火核心墙体", "同上", "")
    # 走廊变体
    save(base.tile_floor(C("#1a2233"), C("#202a42"), C("#121828")), "tiles/corridor_crystal.png", "A2 走廊地板", "floor_scene.gd:355-357", "")
    save(base.tile_floor(C("#1e1216"), C("#261820"), C("#150c10")), "tiles/corridor_magma.png", "A3 走廊地板", "同上", "")
    # 危险地块
    img = canvas(16, 16)
    rect(img, 0, 0, 15, 15, C("#a8d8f0", 110))
    for x in range(0, 16, 4):
        hline(img, x, x + 1, (x * 3) % 16, C("#e2f4ff", 150))
    save(img, "tiles/hazard_ice.png", "冰面（摩擦减半打滑）", "GDD §10 A2 危险地块", "半透明叠在地板上")
    img = canvas(16, 16)
    for _ in range(9):
        x, y = base.RNG.randint(1, 13), base.RNG.randint(1, 13)
        disk(img, x, y, base.RNG.choice((1, 2)), C("#ff5a1e", 210))
    disk(img, 8, 8, 3, C("#ffd94a", 190))
    save(img, "tiles/hazard_lava.png", "岩浆（DOT 2/s）", "GDD §10 A3 危险地块", "边缘与地板过渡")
    img = canvas(16, 16)
    for x in (3, 8, 13):
        for i in range(5):
            hline(img, x - (5 - i) // 3, x + (5 - i) // 3, 11 + i // 2 - 3, C("#b8c0cc"))
        px(img, x, 6, C("#e8ecf4"))
    save(img, "tiles/hazard_spikes.png", "地刺（周期伸缩）", "GDD §10 A2 陷阱", "伸出/缩回 2 帧共用本图+变形")
    img = canvas(16, 16)
    disk(img, 8, 8, 5, C("#18100c"))
    ring(img, 8, 8, 5, C("#5c4530"), 2)
    for a in range(90, 360, 90):
        px(img, 8 + int(math.cos(math.radians(a)) * 3), 8 + int(math.sin(math.radians(a)) * 3), C("#ff8a2e", 120))
    save(img, "tiles/hazard_vent.png", "间歇喷口（预警后喷发）", "GDD §10 A3 陷阱", "喷发时叠加 fx_explosion")
    # 可破坏掩体
    img = canvas(16, 16)
    for x0, h0 in ((4, 12), (8, 14), (11, 10)):
        for i in range(h0):
            w = max(1, 3 - i // 5)
            rect(img, x0 - w, 14 - i, x0 + w, 14 - i, C("#5ab8d8" if i > h0 // 2 else "#8ae8ff"))
    save(img, "tiles/prop_crystal_pillar.png", "晶柱（可破坏掩体/激光折射, 8~20HP）", "GDD §9.2 签名系统#3", "碎裂 2 帧后留碎块")
    img = canvas(16, 16)
    for x0, h0 in ((4, 5), (8, 7), (12, 4)):
        for i in range(h0):
            rect(img, x0 - 1, 14 - i, x0 + 1, 14 - i, C("#8ae8ff", 200 - i * 30))
    save(img, "tiles/prop_crystal_pillar_broken.png", "晶柱碎块（无碰撞贴地）", "GDD §9.2 摧毁后留碎块", "")
    img = canvas(16, 16)
    disk(img, 8, 12, 5, C("#6a5a4a"))
    disk(img, 5, 10, 3, C("#8a7a66"))
    disk(img, 11, 11, 3, C("#54483c"))
    save(img, "tiles/prop_debris.png", "残骸（可破坏掩体）", "GDD §9.2", "")
    # 熔铸台
    img = canvas(20, 18)
    rect(img, 2, 12, 17, 16, C("#4a4a56"))
    rect(img, 5, 6, 14, 12, C("#5c5c6a"))
    rect(img, 7, 8, 12, 10, C("#ff8a2e"))
    px(img, 9, 9, C("#ffd94a"))
    px(img, 11, 8, C("#ffd94a"))
    rect(img, 8, 2, 11, 6, C("#3a3a44"))
    save(img, "tiles/fusion_forge.png", "熔铸台（每层 1, 2 武器→配方产物）", "GDD §8.3 签名系统#2; 附录 D 15 配方", "工作时有火光动画")
    # 事件房 4 事件
    img = canvas(16, 18)
    rect(img, 5, 12, 6, 14, C("#2a2438"))
    rect(img, 9, 12, 10, 14, C("#2a2438"))
    rect(img, 4, 6, 11, 12, C("#4a3a5c"))
    rect(img, 3, 0, 12, 5, C("#2a2438"))
    eyes(img, 8, 3, gap=2, white=C("#e83a4a"), pupil=C("#701c14"))
    rect(img, 6, 8, 9, 10, C("#e83a4a"))
    outline(img)
    save(img, "tiles/event_merchant.png", "事件：神秘商人（2 HP 换 1 道具）", "GDD §11 事件房/附录 F.3; 现为纯文字面板", "")
    img = canvas(16, 18)
    rect(img, 5, 12, 6, 14, C("#5c4530"))
    rect(img, 9, 12, 10, 14, C("#5c4530"))
    rect(img, 4, 6, 11, 12, C("#8a7a5c"))
    rect(img, 4, 1, 11, 6, C("#a89878"))
    eyes(img, 8, 4, gap=2)
    disk(img, 13, 14, 2, C("#c8d0dc"))
    outline(img)
    save(img, "tiles/event_beggar.png", "事件：乞丐（投 40 金 70% 返 120）", "附录 F.3", "脚边碗")
    img = canvas(16, 18)
    rect(img, 2, 10, 13, 15, C("#6e6678"))
    rect(img, 3, 11, 12, 14, C("#b06cff"))
    px(img, 5, 12, C("#e2c0ff"))
    px(img, 9, 13, C("#e2c0ff"))
    rect(img, 6, 4, 9, 10, C("#8a6ab8"))
    disk(img, 7, 3, 2, C("#d2b8ff"))
    outline(img)
    save(img, "tiles/event_spring.png", "事件：星髓泉（本局盾上限 +1）", "附录 F.3", "")
    img = canvas(18, 18)
    rect(img, 1, 1, 16, 16, C("#8a7a5c"))
    for x in range(2, 16, 3):
        vline(img, x, 1, 16, C("#746448"))
    hline(img, 3, 14, 7, C("#e2c04c"))
    disk(img, 5, 11, 2, C("#5ab0ff"))
    rect(img, 10, 9, 13, 13, C("#e83a4a"))
    save(img, "tiles/event_graffiti.png", "事件：涂鸦墙（随机构筑提示）", "附录 F.3", "")
    # 复活图腾 / 回收架 / 暴击宝箱
    img = canvas(16, 20)
    rect(img, 6, 2, 9, 6, C("#8a6a3c"))
    rect(img, 4, 6, 11, 14, C("#a8854e"))
    rect(img, 6, 8, 9, 11, C("#e83a4a"))
    for y, (a, b) in enumerate(((1, 3), (0, 4))):
        hline(img, a + 5, b + 5, 16 + y, C("#e2c04c"))
    rect(img, 3, 18, 12, 19, C("#5c4530"))
    outline(img)
    save(img, "tiles/totem_revive.png", "复活图腾（Boss 房前 150 金, 一次性）", "GDD §14.2 价格锚点", "图腾眼=红心")
    img = canvas(16, 16)
    rect(img, 2, 4, 13, 13, C("#5c5c6a"))
    hline(img, 2, 13, 4, C("#7a7a8a"))
    for x in (4, 8, 12):
        vline(img, x, 5, 12, C("#444450"))
    hline(img, 3, 12, 2, C("#ffd94a"))
    px(img, 6, 2, C("#ffd94a"))
    outline(img)
    save(img, "tiles/recycle_rack.png", "回收架（商店门口, 弃枪 30% 回收）", "GDD §8.2", "")
    img = canvas(16, 16)
    rect(img, 2, 7, 13, 13, C("#d8a828"))
    rect(img, 2, 4, 13, 7, C("#f2cc60"))
    hline(img, 2, 13, 7, C("#8a6a1c"))
    rect(img, 6, 6, 9, 9, C("#fff3b8"))
    px(img, 7, 8, C("#8a6a1c"))
    px(img, 7, 2, C("#8ae8ff"))
    vline(img, 2, 4, 13, C("#fff3b8"))
    vline(img, 13, 4, 13, C("#fff3b8"))
    outline(img)
    save(img, "tiles/chest_crit.png", "暴击宝箱（15% 出现, 三倍掉落/25% 弹 3 波怪）", "GDD §11 宝箱房", "金身+蓝星")


def _b2(hero_name):
    return hero_name.split("·")[1] if "·" in hero_name else hero_name


def gen_ui_m2():
    # 蓝晶（局外货币）
    img = canvas(12, 12)
    for i, (a, b) in enumerate(((5, 6), (4, 7), (3, 8), (3, 8), (4, 7), (5, 6))):
        hline(img, a, b, 2 + i, C("#5ab8ff"))
    px(img, 4, 4, C("#d2f0ff"))
    vline(img, 5, 0, 1, C("#3a3444"))
    outline(img)
    save(img, "ui/icon_bluecrystal.png", "蓝晶（局外货币）", "GDD §14.1; 现无局外 UI", "死亡保留 50% 提示用同图")
    # 主菜单入口图标
    img = canvas(12, 12)
    rect(img, 5, 1, 6, 3, C("#8ad88a"))
    rect(img, 3, 4, 8, 5, C("#6ab84a"))
    rect(img, 1, 6, 10, 7, C("#5a9a3c"))
    vline(img, 5, 8, 11, C("#8a6a3c"))
    outline(img)
    save(img, "ui/icon_talent.png", "主菜单入口：天赋树", "GDD §19 局外循环", "")
    img = canvas(12, 12)
    rect(img, 2, 1, 9, 11, C("#a8854e"))
    rect(img, 3, 1, 8, 10, C("#e8dcc0"))
    vline(img, 5, 3, 9, C("#8a7a5c"))
    hline(img, 4, 8, 5, C("#8a7a5c"))
    outline(img)
    save(img, "ui/icon_codex.png", "主菜单入口：武器图鉴（115）", "GDD §19/§8.1 图鉴解锁掉落池", "")
    img = canvas(12, 12)
    ring(img, 6, 7, 4, C("#e2c04c"), 2)
    vline(img, 6, 1, 2, C("#e83a4a"))
    disk(img, 6, 3, 1, C("#e83a4a"))
    px(img, 6, 7, C("#fff3b8"))
    outline(img)
    save(img, "ui/icon_achievement.png", "主菜单入口：成就（24）", "附录 G.1", "")
    img = canvas(16, 16)
    ring(img, 8, 8, 6, C("#e2c04c"), 2)
    ring(img, 8, 8, 3, C("#8a6a1c"), 1)
    px(img, 8, 8, C("#ffd94a"))
    for s in (-1, 1):
        hline(img, 8 + s * 2, 8 + s * 4, 14, C("#5ab0ff"))
        hline(img, 8 + s * 3, 8 + s * 5, 15, C("#5ab0ff"))
    save(img, "ui/frame_medal.png", "成就勋章框（列表/解锁 toast 用）", "附录 G.1 成就+蓝晶奖励", "绶带=蓝晶色")
    # 天赋节点
    for suffix, col in (("empty", "#3a3f4c"), ("filled", "#5ab0ff")):
        img = canvas(12, 12)
        disk(img, 6, 6, 4, C(col))
        ring(img, 6, 6, 4, C("#8a97ad" if suffix == "empty" else "#d2f0ff"), 1)
        if suffix == "filled":
            px(img, 5, 5, C("#ffffff"))
        save(img, f"ui/talents/node_{suffix}.png", f"天赋节点（{ '未点亮' if suffix=='empty' else '已点亮'}）", "GDD §19 天赋树; 附录 G 天赋异禀 12 节点", "连线由代码画")
    # 死亡回顾致死来源标记
    img = canvas(12, 12)
    for i in range(6):
        hline(img, 1 + i, 1 + i, 6 - max(0, i - 3), C("#ff3a2e"))
        hline(img, 1 + i, 1 + i, 6 + max(0, i - 3), C("#ff3a2e"))
    ring(img, 8, 6, 2, C("#ff3a2e"), 1)
    save(img, "ui/icon_death_source.png", "死亡回顾：致死弹来源高亮标记", "GDD §19 死亡回顾（来源回放 3s）; M1 death_summary 纯文字", "")
    # 挑战房小地图图标
    img = canvas(8, 8)
    rect(img, 1, 1, 6, 6, C("#b06cff"))
    px(img, 1, 1, C("#d2b8ff"))
    hline(img, 3, 4, 3, C("#ffffff"))
    hline(img, 3, 4, 4, C("#ffffff"))
    save(img, "ui/minimap/challenge.png", "小地图图标：挑战房（灾厄三选一）", "GDD §11 挑战房（M2 新房型）", "")


def main():
    # 独立入口与全量入口同一条管线：prune 豁免（m4-a2 P0 keep-set 修复）与美术 QA
    # 三重校验尾部自检（m4-a2，fail-closed）都在 gen_placeholder_art.main() 尾部统一生效。
    import gen_placeholder_art as _b
    _b.main()


if __name__ == "__main__":
    main()

