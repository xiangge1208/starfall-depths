# 占位素材清单（art/generated）

> 由 `tools/gen_placeholder_art.py` 自动生成并维护，重跑脚本即整体再生（确定性随机种子 42）。
> 当前项目**没有任何外部贴图**：全部画面为程序化纯色 Polygon2D/ColorRect（见各素材「现状」列）。
> 本目录素材为**像素风占位**：①先让画面脱离纯色块 ②为外包/自绘提供尺寸与风格锚点。
> 接线方式：把对应代码点的 Polygon2D 换成 `Sprite2D`（保留节点名 `Sprite`，受击白闪 fx.gd 按名查找），
> 像素材质需在导入设置开 `filter=nearest`（或项目默认纹理过滤改 Nearest）。

图例：尺寸为像素；「现状」= 当前程序化表现的代码位置。

| 素材 | 尺寸 | 用途 | 现状（代码替换点） | 替换指引 |
|---|---|---|---|---|
| `characters/hero_vanguard.png` | 16x16 | 英雄「骑士·凛」站立像（正面） | core/player/player.tscn:27-29 Sprite=12x14 米色色块; autoload/fx.gd:197 受击白闪按节点名 Sprite 查找 | 替换为四向行走 SpriteSheet（每向 idle+walk 2-4 帧），节点保留名 Sprite 以复用白闪 |
| `characters/hero_ranger.png` | 16x16 | 英雄「游侠·苇」站立像（正面） | core/player/player.tscn:27-29 同上（两位英雄共用同一 Sprite 节点） | 同骑士·凛；另需影袭残影帧（半透明复制帧即可） |
| `characters/hero_vanguard_sheet.png` | 64x64 | 英雄「骑士·凛」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧） | core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4 | m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变） |
| `characters/hero_ranger_sheet.png` | 64x64 | 英雄「游侠·苇」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧） | core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4 | m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变） |
| `characters/hero_engineer_sheet.png` | 64x64 | 英雄「工程师·铆」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧） | core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4 | m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变） |
| `characters/hero_mage_sheet.png` | 64x64 | 英雄「法师·烬」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧） | core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4 | m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变） |
| `characters/hero_guardian_sheet.png` | 64x64 | 英雄「守护者·萄」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧） | core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4 | m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变） |
| `characters/hero_assassin_sheet.png` | 64x64 | 英雄「刺客·蝉」四向行走帧表（行=下/上/左/右, 列=idle+walk×3, 16px/帧） | core/player/player.gd _update_walk_anim 帧驱动; player.tscn Sprite hframes=4 vframes=4 | m2-t17：移动方向自动切行, idle 列0 / 行走循环列1-3（8t/帧）; 受击白闪沿用 Fx（节点名 Sprite 不变） |
| `enemies/kuli_bug.png` | 16x16 | 敌人「苦力虫（自爆虫）」 | data/enemies.json id=kuli_bug; 现为 room_combat.gd:191-197 按 ARCHETYPE_COLORS.suicide 0.4,0.8,0.35 纯色块 | 原型:绿色圆虫+引信触角+大眼；死亡闪烁接 fuse_ticks |
| `enemies/cave_bat.png` | 16x16 | 敌人「穴蝠」 | 同上, archetype=orbiter 0.45,0.42,0.55 | 原型:灰紫蝙蝠,展开双翼,红眼獠牙；飞行做 2 帧扑翼 |
| `enemies/crossbowman.png` | 16x16 | 敌人「弩兵」 | 同上, archetype=shooter 0.5,0.6,0.85 | 原型:蓝衣弩手+弩；蓄力(windup 30t)需抬弩帧 |
| `enemies/vine_charger.png` | 16x16 | 敌人「藤蔓冲锋者」 | 同上, archetype=charger 0.7,0.4,0.8 | 原型:紫甲冲撞兽,前倾冲锋蓄力帧+冲锋帧 |
| `enemies/mushroom_spore.png` | 16x16 | 敌人「蘑菇孢子手」 | 同上, archetype=mushroom_spore 0.58,0.82,0.46 | 原型:绿斑蘑菇,喷孢子；攻击时伞盖压缩帧 |
| `enemies/shuangdao_lizardman.png` | 20x20 | 敌人「双刀蜥人（精英）」 | data/enemies.json id=shuangdao_lizardman; combo_charger 原型色块 (body_scale 1.25) | 原型:蜥人双刀客,青鳞金饰; 与普通体区分度要高 |
| `enemies/zibao_wangchong.png` | 20x20 | 敌人「自爆王虫（精英）」 | data/enemies.json id=zibao_wangchong; delayed_blast 延迟爆视觉为色块 | 原型:橙红大甲虫+引信; 死亡后 60t 倒计时闪烁帧 |
| `enemies/vine_colossus.png` | 32x32 | 敌人「藤蔓巨像（Boss）」 | vine_colossus.gd:346-375 绿色块+特效色块; boss_base.gd:100 白闪 | 32x32 树巨人; 三阶段可共用本体+特效区分 |
| `projectiles/bullet_player.png` | 8x8 | 玩家子弹（radius≈3px） | floor_scene.gd:61 / room_combat.gd:37 PLAYER_BULLET_COLOR 纯色方块 Polygon2D | 元素弹可用 modulate 调色或换 elem_* 专用图 |
| `projectiles/bullet_enemy.png` | 8x8 | 敌方子弹 | floor_scene.gd:62 / room_combat.gd:38 ENEMY_BULLET_COLOR 纯色方块 | 同上 |
| `projectiles/elem_fire.png` | 8x8 | fire 元素弹 | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_ice.png` | 8x8 | ice 元素弹 | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_poison.png` | 8x8 | poison 元素弹 | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_shock.png` | 8x8 | shock 元素弹 | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_fire_enemy.png` | 8x8 | fire 元素弹（敌方变体·暗边框） | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_ice_enemy.png` | 8x8 | ice 元素弹（敌方变体·暗边框） | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_poison_enemy.png` | 8x8 | poison 元素弹（敌方变体·暗边框） | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/elem_shock_enemy.png` | 8x8 | shock 元素弹（敌方变体·暗边框） | autoload/fx.gd:18-21 元素色表（火/冰/毒/电） | 元素异常命中粒子同色系 |
| `projectiles/laser_seg.png` | 16x6 | 激光束段（16x6 可平铺） | data/weapons.json category=laser（熔断激光/冰晶射线）暂无表现 | 水平旋转 90° 得竖直束 |
| `pickups/coin.png` | 8x8 | 金币掉落 | core/rooms/pickup.gd:7-23 coin 色块 Polygon2D | — |
| `pickups/energy.png` | 8x8 | 蓝能拾取 | pickup.gd energy 0.3,0.6,1.0 色块 | — |
| `pickups/heart.png` | 8x8 | 红心（回血） | pickup.gd heart 1.0,0.3,0.4 色块 | — |
| `pickups/weapon_crate.png` | 12x12 | 武器掉落箱（drops=weapon） | 核心/rooms/pickup.gd 尚无武器拾取表现 | 开启后接武器图标气泡 |
| `tiles/floor_cave.png` | 16x16 | 洞穴(普通房) 地板 16x16 可平铺 | floor_scene.gd:223/230 tint 0.17,0.15,0.2; room_combat.gd:368 | 替换需保持 16x16 无缝 |
| `tiles/floor_garden.png` | 16x16 | 庭院(出生/起点房) 地板 | floor_scene.gd:225 tint 0.14,0.16,0.15; inter_floor.gd:85; training_room.gd:217 | 替换需保持 16x16 无缝 |
| `tiles/floor_boss.png` | 16x16 | Boss 房 地板 | floor_scene.gd:227 tint 0.2,0.13,0.16 | 替换需保持 16x16 无缝 |
| `tiles/wall_cave.png` | 16x16 | 洞穴墙体（墙厚 16px=1 tile） | floor_scene.gd:235-236/1159/1185 0.36,0.3,0.28 色块 | 顶部 1px 亮色已内嵌 |
| `tiles/wall_garden.png` | 16x16 | 庭院墙体 | 同上（当前不分生物群系） | 顶部 1px 亮色已内嵌 |
| `tiles/wall_boss.png` | 16x16 | Boss 房墙体 | 同上 | 顶部 1px 亮色已内嵌 |
| `tiles/corridor_floor.png` | 16x16 | 房间连接走廊地板 | floor_scene.gd:355-357 0.13,0.12,0.16 色块 | — |
| `tiles/door_closed.png` | 16x16 | 房间木门（16px 厚墙体上的门洞盖板） | floor_scene.gd:378-382/862 与 room_combat.gd:374-379 0.62,0.4,0.22 色块 | 开门动画可滑动+淡出 |
| `tiles/door_locked.png` | 16x16 | 锁定门（通关条件未满足） | floor_scene.gd:862 locked → 0.7,0.2,0.2 红色块 | 锁牌换红色更醒目 |
| `tiles/prop_pillar.png` | 16x16 | 石柱（实体阻挡 16x16） | floor_scene.gd:284 0.5,0.48,0.52 色块 | — |
| `tiles/prop_crate.png` | 16x16 | 木箱（实体阻挡） | floor_scene.gd:286 0.55,0.4,0.24 色块 | — |
| `tiles/prop_bush.png` | 16x16 | 灌木（纯视觉） | floor_scene.gd:288 0.25,0.42,0.24 色块 | — |
| `tiles/hazard_vine.png` | 32x32 | 藤蔓减速带（32x32 半透明，可平铺） | floor_scene.gd:291-303 半径 24 圆形 0.3,0.55,0.3 alpha0.18 | 整圆贴图亦可(需含 alpha) |
| `tiles/chest_closed.png` | 16x16 | 宝箱（宝物房） | 当前宝物房无箱体表现（m1-05 证据图） | 开箱动画 2 帧即可 |
| `tiles/exit_crystal.png` | 12x18 | 层间出口水晶 | run_root.gd:150-157 marker 0.08,0.16,0.24 + crystal 0.35,0.75,1.0 色块 | 可做上下浮动+发光 |
| `tiles/fountain_full.png` | 16x16 | 层间喷泉（可饮用） | inter_floor.gd:100-102/183 0.3,0.6,0.9 → 用尽 0.25,0.4,0.5 | — |
| `tiles/fountain_used.png` | 16x16 | 层间喷泉（已用尽） | inter_floor.gd:100-102/183 0.3,0.6,0.9 → 用尽 0.25,0.4,0.5 | — |
| `tiles/shrine.png` | 16x18 | 雕像（许愿/强化交互） | floor_scene.gd:888-895 0.75,0.58,0.2 → 用尽 0.4,0.34,0.16 色块 | 用尽态换灰色 modulate |
| `tiles/drink_machine.png` | 16x18 | 饮料机 | floor_scene.gd:914-916 0.3,0.6,0.75 色块; core/interact/drink_machine.gd UI 面板 | — |
| `tiles/event_device.png` | 16x18 | 事件装置 | floor_scene.gd:932-934 0.35,0.35,0.45 色块 | — |
| `fx/fx_slash.png` | 16x16 | 近战挥砍弧光 | core/player/melee.gd 目前无独立视觉（仅结算） | 旋转 0/90/180/270 覆盖四向 |
| `fx/fx_explosion.png` | 24x24 | 爆炸爆云（自爆/死亡爆/熔火） | autoload/fx.gd:116 _puff 0.9,0.33,0.14 12 粒 | 可改 4 帧序列图 |
| `fx/fx_puff.png` | 8x8 | 命中/翻滚烟尘粒子 | autoload/fx.gd:88 _puff 0.85 白 6 粒 | — |
| `fx/fx_muzzle.png` | 8x8 | 枪口闪光 | 当前无表现（weapon_rig.gd） | — |
| `fx/telegraph_circle.png` | 32x32 | 圆形危险预警（Boss 拍击/爆炸范围） | vine_colossus.gd:145 _fx_wedge 1.0,0.16,0.12 a0.35; delayed_blast.gd 延迟爆亦无预警(用 fuse_zone) | 运行时按半径缩放 |
| `fx/telegraph_rect.png` | 32x16 | 矩形危险预警（横扫/弹雨区） | vine_colossus.gd:152/156 _fx_rect 1.0,0.16,0.12 a0.15-0.2 | 运行时九宫格/平铺缩放 |
| `fx/safe_zone.png` | 32x32 | Boss 安全区绿圈 | vine_colossus.gd:377 0.3,0.9,0.35 a0.4 | — |
| `fx/cloud_blaze.png` | 16x16 | 灼烧云（BLAZE 共鸣） | combat.spawn_blaze_cloud / status 组件（program 无贴图） | — |
| `fx/cloud_spore.png` | 16x16 | 毒孢子云（蘑菇手/毒共鸣） | combat.spawn_blaze_cloud / status 组件（program 无贴图） | — |
| `ui/panel_dark.png` | 24x24 | UI 深色面板（24x24 九宫格:边 6px） | shop.gd:15 / drink_machine.gd:19 / events.gd:22 PANEL_BG 0.07,0.08,0.1 色块 | NinePatchRect |
| `ui/frame_rarity_common.png` | 16x16 | common 品质边框（16x16 九宫格:边 2px） | shop.gd:18-19 / buff_pick.gd:9 / hud.gd:28-30 RARITY_COLORS | 卡背内衬半透明 |
| `ui/frame_rarity_uncommon.png` | 16x16 | uncommon 品质边框（16x16 九宫格:边 2px） | shop.gd:18-19 / buff_pick.gd:9 / hud.gd:28-30 RARITY_COLORS | 卡背内衬半透明 |
| `ui/frame_rarity_rare.png` | 16x16 | rare 品质边框（16x16 九宫格:边 2px） | shop.gd:18-19 / buff_pick.gd:9 / hud.gd:28-30 RARITY_COLORS | 卡背内衬半透明 |
| `ui/frame_rarity_epic.png` | 16x16 | epic 品质边框（16x16 九宫格:边 2px） | shop.gd:18-19 / buff_pick.gd:9 / hud.gd:28-30 RARITY_COLORS | 卡背内衬半透明 |
| `ui/frame_rarity_legend.png` | 16x16 | legend 品质边框（16x16 九宫格:边 2px） | shop.gd:18-19 / buff_pick.gd:9 / hud.gd:28-30 RARITY_COLORS | 卡背内衬半透明 |
| `ui/portrait_vanguard.png` | 32x32 | 骑士·凛 选人头像 32x32 | ui/hero_select.gd:82-112 卡片纯文字无头像 | 选人卡左侧 24x24 显示区 |
| `ui/portrait_ranger.png` | 32x32 | 游侠·苇 选人头像 32x32 | ui/hero_select.gd:82-112 卡片纯文字无头像 | 选人卡左侧 24x24 显示区 |
| `ui/icon_heart_full.png` | 8x8 | HUD 红心(满) | hud.gd:17-18 HEART_FULL 0.85,0.16,0.16 色块 | empty 用同形暗色 modulate |
| `ui/icon_heart_empty.png` | 8x8 | HUD 红心(空) | hud.gd:18 HEART_EMPTY 0.24,0.1,0.1 | — |
| `ui/icon_shield.png` | 8x8 | HUD 护盾 | hud.gd:20 SHIELD_COLOR 0.5,0.8,1.0 色块 | — |
| `ui/icon_energy.png` | 8x8 | HUD 蓝能 | hud.gd:21 ENERGY_COLOR 0.3,0.45,1.0 色块 | 闪电造型 |
| `ui/icon_coin.png` | 8x8 | HUD 金币 | hud.gd:22 COIN_COLOR 1.0,0.85,0.3 色块 | — |
| `ui/skill_rampage.png` | 16x16 | 技能「狂潮」(骑士·凛): 双持齐射 | hud.gd:355-372 技能冷却环(纯圆弧) | 冷却环扣图标显示 |
| `ui/skill_shadowstep.png` | 16x16 | 技能「影袭」(游侠·苇): 瞬步+必暴 | 同上 | — |
| `ui/icon_roll.png` | 12x12 | 翻滚 CD 指示点图标 | hud.gd:25-26 DOT_READY/DOT_DIM 色点 | — |
| `ui/buffs/fire_enchant.png` | 12x12 | Buff 图标「火焰附魔」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/ice_enchant.png` | 12x12 | Buff 图标「冰霜附魔」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/poison_enchant.png` | 12x12 | Buff 图标「毒素附魔」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/shock_enchant.png` | 12x12 | Buff 图标「电弧附魔」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/bullet_speed.png` | 12x12 | Buff 图标「弹速强化」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/precision.png` | 12x12 | Buff 图标「精准」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/vigor.png` | 12x12 | Buff 图标「强健」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/shield_tune.png` | 12x12 | Buff 图标「护盾调谐」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/swift_trigger.png` | 12x12 | Buff 图标「迅捷扳机」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/deadly.png` | 12x12 | Buff 图标「致命」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/status_erode.png` | 12x12 | Buff 图标「状态侵蚀」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/quick_charge.png` | 12x12 | Buff 图标「快速充能」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/energy_max.png` | 12x12 | Buff 图标「蓝能上限」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/roll_master.png` | 12x12 | Buff 图标「翻滚大师」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/extra_projectiles.png` | 12x12 | Buff 图标「散弹扩张」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/crit_detonate.png` | 12x12 | Buff 图标「暴虐回响」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/hunter.png` | 12x12 | Buff 图标「猎杀者」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/resonance_amp.png` | 12x12 | Buff 图标「共鸣增幅」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/avenger.png` | 12x12 | Buff 图标「复仇者」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/anti_fire.png` | 12x12 | Buff 图标「抗火」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/anti_ice.png` | 12x12 | Buff 图标「抗冰」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/anti_poison.png` | 12x12 | Buff 图标「抗毒」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/nerve_reflex.png` | 12x12 | Buff 图标「神经反射」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/carapace.png` | 12x12 | Buff 图标「甲壳」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/thorn_armor.png` | 12x12 | Buff 图标「荆棘护甲」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/dash_extend.png` | 12x12 | Buff 图标「冲刺延伸」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/phoenix.png` | 12x12 | Buff 图标「不死鸟」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/wealth.png` | 12x12 | Buff 图标「财富」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/glutton.png` | 12x12 | Buff 图标「大胃王」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/pickup_magnet.png` | 12x12 | Buff 图标「捡拾磁铁」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/energy_siphon.png` | 12x12 | Buff 图标「蓝能汲取」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/heart_sense.png` | 12x12 | Buff 图标「红心感应」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/ammo_convert.png` | 12x12 | Buff 图标「弹药转化」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/haggle.png` | 12x12 | Buff 图标「议价」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/element_vision.png` | 12x12 | Buff 图标「元素视界」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/buffs/resonance_vision.png` | 12x12 | Buff 图标「共鸣视界」 | hud.gd:329 buff 芯片按稀有度着色（无图标）; ui/buff_pick.gd 卡片纯文字 | 12x12 显示, 24x24 网格可后期重绘 |
| `ui/drinks/shengming_soda.png` | 12x12 | 饮料图标「生命苏打」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/nengliang_qishui.png` | 12x12 | 饮料图标「蓝能汽水」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/jifeng_bohe.png` | 12x12 | 饮料图标「疾风薄荷」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/yingyan_kafei.png` | 12x12 | 饮料图标「鹰眼咖啡」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/chongneng_keke.png` | 12x12 | 饮料图标「充能可可」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/qingyu_qipao.png` | 12x12 | 饮料图标「轻羽气泡」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/xingsui_tete.png` | 12x12 | 饮料图标「星髓特调」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/drinks/shenmi_hunhe.png` | 12x12 | 饮料图标「神秘混合」 | core/interact/drink_machine.gd 卡片纯文字（PANEL_BG/ACCENT） | 瓶身色=效果色，重绘时保留辨识度 |
| `ui/joystick_base.png` | 48x48 | 虚拟摇杆底盘 | ui/virtual_joystick.gd:97-101 draw_circle a0.12 + arc a0.35 | — |
| `ui/joystick_nub.png` | 24x24 | 虚拟摇杆摇杆头 | virtual_joystick.gd:101 a0.55 圆 | — |
| `ui/vignette_lowhp.png` | 96x96 | 低血红屏 vignette（中心透明） | hud.gd:184 vignette 0.75,0.05,0.05 a0.12 色块 | 全屏拉伸, modulate 控制强度 |
| `ui/logo_title.png` | 240x64 | 主菜单标题 LOGO 占位（系统字体渲染） | ui/main_menu.tscn 标题为纯 Label | 正式版换像素字体 LOGO（见 MANIFEST 待采购项） |
| `ui/white.png` | 4x4 | 纯白 4x4 工具图（modulate 调色用） | 多处 ColorRect 临时替代 | — |
| `enemies/vine_charger_elite.png` | 16x16 | 客人「精英·藤蔓冲锋者」（金色变体） | floor_scene.gd:52-56/622-624 GUEST_COLORS.elite 1.0,0.82,0.25 染色色块 | 亦可直接用 base 图 + modulate 金色 |
| `enemies/vine_charger_miniboss.png` | 16x16 | 客人「垒主·藤蔓冲锋者」（红色变体） | floor_scene.gd:52-56/622-624 GUEST_COLORS.miniboss 0.85,0.25,0.2 染色色块 | — |
| `fx/shield_spirit.png` | 16x16 | 护盾精灵（精灵像供奉物，跟随玩家拦弹 3 次） | core/interact/shield_spirit.gd 纯 Node2D 无任何外观（隐形）; floor_scene.gd:437 挂载 | 拦截瞬间可加白闪/缩放弹跳 |
| `ui/status_burn.png` | 8x8 | 敌人状态角标：灼烧 | core/combat/status_component.gd DoT 无视觉表现 | 悬浮敌人头顶 |
| `ui/status_frozen.png` | 8x8 | 敌人状态角标：冰冻 | status_component.gd is_frozen 无视觉 | — |
| `ui/status_shock.png` | 8x8 | 敌人状态角标：麻痹 | status_component.gd SHOCK/眩晕 无视觉 | — |
| `ui/status_poison.png` | 8x8 | 敌人状态角标：中毒 | status_component.gd 毒 DoT 无视觉 | — |
| `ui/affix_swift.png` | 12x12 | 词缀角标：迅捷(×1.3 速度) | core/enemies/elites/elite_affix.gd:11 AFFIXES，全部无视觉标识 | 悬浮血条旁 |
| `ui/affix_armored.png` | 12x12 | 词缀角标：坚甲(HP×3) | elite_affix.gd ARMORED_HP_MULT | — |
| `ui/affix_splitter.png` | 12x12 | 词缀角标：分裂(死亡一分为二) | elite_affix.gd split_on_death | — |
| `ui/affix_leech.png` | 12x12 | 词缀角标：虹吸(接触吸血) | elite_affix.gd leech | — |
| `ui/affix_barrage.png` | 12x12 | 词缀角标：弹幕(+1 弹) | elite_affix.gd barrage_extra | — |
| `ui/affix_berserk.png` | 12x12 | 词缀角标：狂暴(<50% 血攻速×1.3) | elite_affix.gd has_berserk / enemy_base.gd:231 | — |
| `ui/boss_bar_frame.png` | 96x12 | Boss 血条框（96x12, 运行时缩放） | 无（游戏当前没有 Boss 血条，boss_base.gd 仅白闪） | NinePatch/TextureProgressBar |
| `ui/boss_bar_fill.png` | 96x12 | Boss 血条填充 | 同上 | TextureProgressBar progress 贴图 |
| `ui/btn_skill.png` | 16x16 | 触屏按钮：技能 | ui/touch_controls.tscn:41-54 SkillButton 纯文字「技能」 | Button.icon |
| `ui/btn_roll.png` | 16x16 | 触屏按钮：翻滚 | touch_controls.tscn:56-69 RollButton 文字「翻滚」 | — |
| `ui/btn_switch.png` | 16x16 | 触屏按钮：切枪 | touch_controls.tscn:71-81 SwitchButton 文字「切枪」 | — |
| `ui/btn_interact.png` | 16x16 | 触屏按钮：交互 | touch_controls.tscn:83-93 InteractButton 文字「交互」 | 叹号气泡造型 |
| `ui/minimap/combat.png` | 8x8 | 小地图图标：普通战斗房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/start.png` | 8x8 | 小地图图标：出生房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/boss.png` | 8x8 | 小地图图标：Boss 房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/treasure.png` | 8x8 | 小地图图标：宝物房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/shop.png` | 8x8 | 小地图图标：商店房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/event.png` | 8x8 | 小地图图标：事件房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/elite.png` | 8x8 | 小地图图标：精英(嘉宾)房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/minimap/miniboss.png` | 8x8 | 小地图图标：小 Boss 房（暂无小地图，预留） | floor_flow.gd:22-24 INSTANT_CLEAR_TYPES/GUEST_EVENT_TYPES 房间类型全集 | 8x8, 间距 1px 显示 |
| `ui/passive_defiance.png` | 12x12 | 被动图标：坚守（骑士·凛, 破盾反伤） | data/heroes.json passive_id=defiance; player.gd:167 _on_shield_broken | 选人卡/局内 HUD 预留 |
| `ui/passive_hawkeye.png` | 12x12 | 被动图标：鹰眼（游侠·苇） | data/heroes.json passive_id=hawk_eye | — |
| `ui/skill_rampage_plus.png` | 16x16 | 技能升级版图标（狂潮+） | data/heroes.json upgraded 字段; player.gd:14 RAMPAGE_DR 狂潮(升级)减伤 | 右下金+角标 |
| `ui/skill_shadowstep_plus.png` | 16x16 | 技能升级版图标（影袭+） | data/heroes.json upgraded 字段; player.gd:14 RAMPAGE_DR 狂潮(升级)减伤 | 右下金+角标 |
| `fx/reticle.png` | 8x8 | 瞄准准星（自动瞄准/手柄瞄准表现预留） | core/player/auto_aim.gd 纯逻辑无表现 | 触屏/手柄模式下显示 |
| `ui/icon_app.png` | 128x128 | 应用图标（像素风备选; 根目录 icon.svg 为现有自绘星形版） | icon.svg（项目窗口图标，已是自定义星形非 Godot 默认） | 替换时同步改 project.godot config/icon |
| `tiles/shrine_zhanshen.png` | 16x18 | 战神像（攻击力 +25% 10s） | core/interact/shrine.gd:14 KINDS=zhanshen; floor_scene.gd:768-772 四尊同房均为金色色块 | 披肩/底座=属性色, 身部白点=徽记 |
| `tiles/shrine_jingling.png` | 16x18 | 精灵像（召唤护盾精灵拦弹 3 次） | shrine.gd jingling; core/interact/shield_spirit.gd | — |
| `tiles/shrine_fengshen.png` | 16x18 | 风神像（攻速/移速 +30% 5s） | shrine.gd fengshen | — |
| `tiles/shrine_xingsui.png` | 16x18 | 星髓像（武器临时元素附魔 60s） | shrine.gd xingsui; weapon_rig.gd temporary_enchant | — |
| `fx/fuse_zone.png` | 48x48 | 自爆引信预警圈（苦力虫 40px / 自爆王虫 72px，倒计时脉冲） | core/enemies/elites/delayed_blast.gd 完全无视觉; enemy_base.gd:192 _spawn_delayed_blast | 运行时按 aoe_radius 缩放, 倒计时闪烁 modulate |
| `ui/icon_blackmarket.png` | 16x16 | 黑市标识（武器价 ×1.8, UI 标题旁） | core/interact/shop.gd:14/30 BLACK_TITLE 黑市商人(纯文字), floor_scene.gd BLACK_SHOP_CHANCE | — |
| `tiles/shopkeeper.png` | 16x18 | 商人 NPC（商店房形象预留; 现商店仅弹 UI 面板） | core/interact/shop.gd + shop.tscn（无世界内形象） | 黑市款换紫袍+兜帽 |
| `tiles/shopkeeper_black.png` | 16x18 | 黑市商人 NPC（兜帽遮面） | shop.gd black 变体（标题/价格区分, 无形象） | — |
| `ui/weapons/laohuoji.png` | 16x16 | 武器图标「老伙计」(pistol/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/laohuoji.png` | 16x16 | 手持武器「老伙计」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/maodingqiang.png` | 16x16 | 武器图标「铆钉枪」(pistol/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/maodingqiang.png` | 16x16 | 手持武器「铆钉枪」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/duangong.png` | 16x16 | 武器图标「短弓」(bow/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/duangong.png` | 16x16 | 手持武器「短弓」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xuetufazhang.png` | 16x16 | 武器图标「学徒法杖」(staff/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xuetufazhang.png` | 16x16 | 手持武器「学徒法杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/tiejian.png` | 16x16 | 武器图标「铁剑」(melee/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/tiejian.png` | 16x16 | 手持武器「铁剑」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shuangbi.png` | 16x16 | 武器图标「双匕」(melee/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shuangbi.png` | 16x16 | 手持武器「双匕」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhishibuqiang.png` | 16x16 | 武器图标「制式步枪」(rifle/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhishibuqiang.png` | 16x16 | 手持武器「制式步枪」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/qianguan.png` | 16x16 | 武器图标「铅管」(shotgun/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/qianguan.png` | 16x16 | 手持武器「铅管」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shuangzixing.png` | 16x16 | 武器图标「双子星」(pistol/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shuangzixing.png` | 16x16 | 手持武器「双子星」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/fengci.png` | 16x16 | 武器图标「蜂刺」(pistol/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/fengci.png` | 16x16 | 手持武器「蜂刺」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/fengqun.png` | 16x16 | 武器图标「蜂群」(smg/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/fengqun.png` | 16x16 | 手持武器「蜂群」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/jiaoju.png` | 16x16 | 武器图标「角锯」(smg/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/jiaoju.png` | 16x16 | 手持武器「角锯」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/sandianjungui.png` | 16x16 | 武器图标「三点军规」(rifle/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/sandianjungui.png` | 16x16 | 手持武器「三点军规」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/lieluren.png` | 16x16 | 武器图标「猎鹿人」(rifle/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/lieluren.png` | 16x16 | 手持武器「猎鹿人」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/wulianbao.png` | 16x16 | 武器图标「五连爆」(shotgun/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/wulianbao.png` | 16x16 | 手持武器「五连爆」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/huoqiuzhang.png` | 16x16 | 武器图标「火球杖」(staff/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/huoqiuzhang.png` | 16x16 | 手持武器「火球杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/bingzhuizhang.png` | 16x16 | 武器图标「冰锥杖」(staff/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/bingzhuizhang.png` | 16x16 | 手持武器「冰锥杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/duyunzhang.png` | 16x16 | 武器图标「毒云杖」(staff/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/duyunzhang.png` | 16x16 | 手持武器「毒云杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/dujian.png` | 16x16 | 武器图标「毒箭」(bow/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/dujian.png` | 16x16 | 手持武器「毒箭」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/bingjian.png` | 16x16 | 武器图标「冰箭」(bow/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/bingjian.png` | 16x16 | 手持武器「冰箭」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/ronghuoshouqiang.png` | 16x16 | 武器图标「熔火手枪」(pistol/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/ronghuoshouqiang.png` | 16x16 | 手持武器「熔火手枪」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shuangya.png` | 16x16 | 武器图标「霜牙」(pistol/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shuangya.png` | 16x16 | 手持武器「霜牙」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xunxiang.png` | 16x16 | 武器图标「讯响」(pistol/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xunxiang.png` | 16x16 | 手持武器「讯响」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shenpanzhe.png` | 16x16 | 武器图标「审判者」(pistol/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shenpanzhe.png` | 16x16 | 手持武器「审判者」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xingxie.png` | 16x16 | 武器图标「星屑」(pistol/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xingxie.png` | 16x16 | 手持武器「星屑」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/lanshan.png` | 16x16 | 武器图标「蓝闪」(smg/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/lanshan.png` | 16x16 | 手持武器「蓝闪」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shuangchixuanfeng.png` | 16x16 | 武器图标「双持旋风」(smg/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shuangchixuanfeng.png` | 16x16 | 手持武器「双持旋风」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/guanchuanzhe.png` | 16x16 | 武器图标「贯穿者」(rifle/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/guanchuanzhe.png` | 16x16 | 手持武器「贯穿者」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shenkong.png` | 16x16 | 武器图标「深空」(rifle/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shenkong.png` | 16x16 | 手持武器「深空」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhanhaoqingxiao.png` | 16x16 | 武器图标「战壕清扫」(shotgun/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhanhaoqingxiao.png` | 16x16 | 手持武器「战壕清扫」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/liexiong.png` | 16x16 | 武器图标「猎熊」(shotgun/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/liexiong.png` | 16x16 | 手持武器「猎熊」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/rongduanjiguang.png` | 16x16 | 武器图标「熔断激光」(laser/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/rongduanjiguang.png` | 16x16 | 手持武器「熔断激光」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/bingjingshexian.png` | 16x16 | 武器图标「冰晶射线」(laser/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/bingjingshexian.png` | 16x16 | 手持武器「冰晶射线」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/leilianzhang.png` | 16x16 | 武器图标「雷链杖」(staff/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/leilianzhang.png` | 16x16 | 手持武器「雷链杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/liefengchanggong.png` | 16x16 | 武器图标「猎风长弓」(bow/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/liefengchanggong.png` | 16x16 | 手持武器「猎风长弓」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/dianque.png` | 16x16 | 武器图标「电雀」(pistol/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/dianque.png` | 16x16 | 手持武器「电雀」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/ranshaodanlian.png` | 16x16 | 武器图标「燃烧弹链」(rifle/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/ranshaodanlian.png` | 16x16 | 手持武器「燃烧弹链」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/donghehe.png` | 16x16 | 武器图标「冻结核」(rifle/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/donghehe.png` | 16x16 | 手持武器「冻结核」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/longxi.png` | 16x16 | 武器图标「龙息」(shotgun/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/longxi.png` | 16x16 | 手持武器「龙息」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/liuhuang.png` | 16x16 | 武器图标「硫磺」(shotgun/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/liuhuang.png` | 16x16 | 手持武器「硫磺」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zuolunzhengwu.png` | 16x16 | 武器图标「左轮·正午」(pistol/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zuolunzhengwu.png` | 16x16 | 手持武器「左轮·正午」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/yahuozhe.png` | 16x16 | 武器图标「哑火者」(pistol/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/yahuozhe.png` | 16x16 | 手持武器「哑火者」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/yingwan.png` | 16x16 | 武器图标「影丸」(pistol/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/yingwan.png` | 16x16 | 手持武器「影丸」(pistol) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhusi.png` | 16x16 | 武器图标「蛛丝」(smg/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhusi.png` | 16x16 | 手持武器「蛛丝」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shezhezhe.png` | 16x16 | 武器图标「折射者」(smg/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shezhezhe.png` | 16x16 | 手持武器「折射者」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/bingzhuiji.png` | 16x16 | 武器图标「冰锥机」(smg/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/bingzhuiji.png` | 16x16 | 手持武器「冰锥机」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/duyepensa.png` | 16x16 | 武器图标「毒液喷洒」(smg/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/duyepensa.png` | 16x16 | 手持武器「毒液喷洒」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/cibao.png` | 16x16 | 武器图标「磁暴」(smg/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/cibao.png` | 16x16 | 手持武器「磁暴」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhongyanjicu.png` | 16x16 | 武器图标「终焉急促」(smg/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhongyanjicu.png` | 16x16 | 手持武器「终焉急促」(smg) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xinggui.png` | 16x16 | 武器图标「星轨」(rifle/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xinggui.png` | 16x16 | 手持武器「星轨」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/laobing.png` | 16x16 | 武器图标「老兵」(rifle/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/laobing.png` | 16x16 | 手持武器「老兵」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/caijue.png` | 16x16 | 武器图标「裁决」(rifle/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/caijue.png` | 16x16 | 手持武器「裁决」(rifle) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shuangguanliyi.png` | 16x16 | 武器图标「双管礼仪」(shotgun/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shuangguanliyi.png` | 16x16 | 手持武器「双管礼仪」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/tanshexian.png` | 16x16 | 武器图标「弹射霰」(shotgun/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/tanshexian.png` | 16x16 | 手持武器「弹射霰」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/suijingpao.png` | 16x16 | 武器图标「碎晶炮」(shotgun/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/suijingpao.png` | 16x16 | 手持武器「碎晶炮」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/yaniemhaojiao.png` | 16x16 | 武器图标「湮灭号角」(shotgun/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/yaniemhaojiao.png` | 16x16 | 手持武器「湮灭号角」(shotgun) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/pojixuanding.png` | 16x16 | 武器图标「迫击·悬顶」(sniper/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/pojixuanding.png` | 16x16 | 手持武器「迫击·悬顶」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/yinsuizhui.png` | 16x16 | 武器图标「音速锥」(sniper/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/yinsuizhui.png` | 16x16 | 手持武器「音速锥」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/changfeng.png` | 16x16 | 武器图标「长风」(sniper/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/changfeng.png` | 16x16 | 手持武器「长风」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/huoshenzhongpao.png` | 16x16 | 武器图标「火神重炮」(sniper/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/huoshenzhongpao.png` | 16x16 | 手持武器「火神重炮」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/duantoutai.png` | 16x16 | 武器图标「断头台」(sniper/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/duantoutai.png` | 16x16 | 手持武器「断头台」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/guanri.png` | 16x16 | 武器图标「贯日」(sniper/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/guanri.png` | 16x16 | 手持武器「贯日」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/liedizhe.png` | 16x16 | 武器图标「裂地者」(sniper/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/liedizhe.png` | 16x16 | 手持武器「裂地者」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xingyunpao.png` | 16x16 | 武器图标「星陨炮」(sniper/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xingyunpao.png` | 16x16 | 手持武器「星陨炮」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/dianciguidao.png` | 16x16 | 武器图标「电磁轨道」(sniper/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/dianciguidao.png` | 16x16 | 手持武器「电磁轨道」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shenpanzhiri.png` | 16x16 | 武器图标「审判之日」(sniper/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shenpanzhiri.png` | 16x16 | 手持武器「审判之日」(sniper) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/guanglengshoudian.png` | 16x16 | 武器图标「光棱手电」(laser/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/guanglengshoudian.png` | 16x16 | 手持武器「光棱手电」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xiangweirenguang.png` | 16x16 | 武器图标「相位刃光」(laser/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xiangweirenguang.png` | 16x16 | 手持武器「相位刃光」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/qiegezhe.png` | 16x16 | 武器图标「切割者」(laser/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/qiegezhe.png` | 16x16 | 手持武器「切割者」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/lengjingquanzhang.png` | 16x16 | 武器图标「棱镜权杖」(laser/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/lengjingquanzhang.png` | 16x16 | 手持武器「棱镜权杖」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/dianhubian.png` | 16x16 | 武器图标「电弧鞭」(laser/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/dianhubian.png` | 16x16 | 手持武器「电弧鞭」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/chuanlengjing.png` | 16x16 | 武器图标「穿棱镜」(laser/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/chuanlengjing.png` | 16x16 | 手持武器「穿棱镜」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/caihongfashengqi.png` | 16x16 | 武器图标「彩虹发生器」(laser/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/caihongfashengqi.png` | 16x16 | 手持武器「彩虹发生器」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/guidaobiaojiqi.png` | 16x16 | 武器图标「轨道标记器」(laser/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/guidaobiaojiqi.png` | 16x16 | 手持武器「轨道标记器」(laser) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/jingjizhang.png` | 16x16 | 武器图标「荆棘杖」(staff/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/jingjizhang.png` | 16x16 | 手持武器「荆棘杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/yunshizhang.png` | 16x16 | 武器图标「陨石杖」(staff/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/yunshizhang.png` | 16x16 | 手持武器「陨石杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xinghuizhang.png` | 16x16 | 武器图标「星辉杖」(staff/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xinghuizhang.png` | 16x16 | 手持武器「星辉杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/jingmianzhang.png` | 16x16 | 武器图标「镜面杖」(staff/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/jingmianzhang.png` | 16x16 | 手持武器「镜面杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhongyanzhizhang.png` | 16x16 | 武器图标「终焉之杖」(staff/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhongyanzhizhang.png` | 16x16 | 手持武器「终焉之杖」(staff) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/liannu.png` | 16x16 | 武器图标「连弩」(bow/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/liannu.png` | 16x16 | 手持武器「连弩」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/baoliejian.png` | 16x16 | 武器图标「爆裂箭」(bow/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/baoliejian.png` | 16x16 | 手持武器「爆裂箭」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/huixuanrengong.png` | 16x16 | 武器图标「回旋刃弓」(bow/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/huixuanrengong.png` | 16x16 | 手持武器「回旋刃弓」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/leimingnu.png` | 16x16 | 武器图标「雷鸣弩」(bow/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/leimingnu.png` | 16x16 | 手持武器「雷鸣弩」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/fenliejian.png` | 16x16 | 武器图标「分裂箭」(bow/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/fenliejian.png` | 16x16 | 手持武器「分裂箭」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/guanxinggong.png` | 16x16 | 武器图标「贯星弓」(bow/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/guanxinggong.png` | 16x16 | 手持武器「贯星弓」(bow) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shoulei.png` | 16x16 | 武器图标「手雷」(throw/common) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shoulei.png` | 16x16 | 手持武器「手雷」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/ranshaoping.png` | 16x16 | 武器图标「燃烧瓶」(throw/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/ranshaoping.png` | 16x16 | 手持武器「燃烧瓶」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/duqiguan.png` | 16x16 | 武器图标「毒气罐」(throw/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/duqiguan.png` | 16x16 | 手持武器「毒气罐」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/jishulei.png` | 16x16 | 武器图标「集束雷」(throw/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/jishulei.png` | 16x16 | 手持武器「集束雷」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/bingdonglei.png` | 16x16 | 武器图标「冰冻雷」(throw/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/bingdonglei.png` | 16x16 | 手持武器「冰冻雷」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/huixuanbiao.png` | 16x16 | 武器图标「回旋镖」(throw/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/huixuanbiao.png` | 16x16 | 手持武器「回旋镖」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/tantiaokuwu.png` | 16x16 | 武器图标「弹跳苦无」(throw/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/tantiaokuwu.png` | 16x16 | 手持武器「弹跳苦无」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/diancimaichonglei.png` | 16x16 | 武器图标「电磁脉冲雷」(throw/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/diancimaichonglei.png` | 16x16 | 手持武器「电磁脉冲雷」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/heidongfashengqi.png` | 16x16 | 武器图标「黑洞发生器」(throw/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/heidongfashengqi.png` | 16x16 | 手持武器「黑洞发生器」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xingheliudan.png` | 16x16 | 武器图标「星核榴弹」(throw/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xingheliudan.png` | 16x16 | 手持武器「星核榴弹」(throw) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/duyaduanren.png` | 16x16 | 武器图标「毒牙短刃」(melee/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/duyaduanren.png` | 16x16 | 手持武器「毒牙短刃」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/changqiang.png` | 16x16 | 武器图标「长枪」(melee/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/changqiang.png` | 16x16 | 手持武器「长枪」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/lieyanjian.png` | 16x16 | 武器图标「烈焰剑」(melee/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/lieyanjian.png` | 16x16 | 手持武器「烈焰剑」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/bingshuangjujian.png` | 16x16 | 武器图标「冰霜巨剑」(melee/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/bingshuangjujian.png` | 16x16 | 手持武器「冰霜巨剑」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/lianchui.png` | 16x16 | 武器图标「链锤」(melee/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/lianchui.png` | 16x16 | 手持武器「链锤」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/xuewenci.png` | 16x16 | 武器图标「血蚊刺」(melee/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/xuewenci.png` | 16x16 | 手持武器「血蚊刺」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhuixingdajian.png` | 16x16 | 武器图标「坠星大剑」(melee/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhuixingdajian.png` | 16x16 | 手持武器「坠星大剑」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/guangjian.png` | 16x16 | 武器图标「光剑」(melee/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/guangjian.png` | 16x16 | 手持武器「光剑」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/leishenzhichui.png` | 16x16 | 武器图标「雷神之锤」(melee/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/leishenzhichui.png` | 16x16 | 手持武器「雷神之锤」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/zhanjiandao.png` | 16x16 | 武器图标「斩舰刀」(melee/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/zhanjiandao.png` | 16x16 | 手持武器「斩舰刀」(melee) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/cilishoutao.png` | 16x16 | 武器图标「磁力手套」(special/uncommon) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/cilishoutao.png` | 16x16 | 手持武器「磁力手套」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/hudunfashengqi.png` | 16x16 | 武器图标「护盾发生器」(special/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/hudunfashengqi.png` | 16x16 | 手持武器「护盾发生器」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/kuileiling.png` | 16x16 | 武器图标「傀儡铃」(special/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/kuileiling.png` | 16x16 | 手持武器「傀儡铃」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/weixiubi.png` | 16x16 | 武器图标「维修臂」(special/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/weixiubi.png` | 16x16 | 手持武器「维修臂」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/lantuhanqiang.png` | 16x16 | 武器图标「蓝图焊枪」(special/rare) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/lantuhanqiang.png` | 16x16 | 手持武器「蓝图焊枪」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/fenshenxinhaotan.png` | 16x16 | 武器图标「分身信号弹」(special/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/fenshenxinhaotan.png` | 16x16 | 手持武器「分身信号弹」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/chuansongbiaoqiang.png` | 16x16 | 武器图标「传送标枪」(special/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/chuansongbiaoqiang.png` | 16x16 | 手持武器「传送标枪」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/wurenjimujian.png` | 16x16 | 武器图标「无人机母舰」(special/epic) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/wurenjimujian.png` | 16x16 | 手持武器「无人机母舰」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/shijianshalou.png` | 16x16 | 武器图标「时间沙漏」(special/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/shijianshalou.png` | 16x16 | 手持武器「时间沙漏」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `ui/weapons/yamiehexin.png` | 16x16 | 武器图标「湮灭核心」(special/legend) | 附录 A = data/weapons.json 115 行（m2-t21 数据驱动收编） | 左上角标=稀有度, 刀身/弹头色=元素 |
| `weapons/yamiehexin.png` | 16x16 | 手持武器「湮灭核心」(special) | weapon_rig.gd 无武器外观; muzzle=8px | 朝右0°, 持握点(4,8), 朝左 flip_v |
| `enemies/mud_slime.png` | 16x16 | 敌人「泥浆史莱姆」(通用/splitter) | 附录 B（通用）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 附录 B.1 分裂原型；死亡裂 2 小体; slug 暂定待 data 落地对齐 |
| `enemies/hardshell_turtle.png` | 16x16 | 敌人「硬壳龟」(A1/tank) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 正面减伤 80%, 龟缩免疫; slug 暂定待 data 落地对齐 |
| `enemies/wing_lizard.png` | 16x16 | 敌人「飞行翼蜥」(A1/wanderer) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 低空绕行+切线俯冲; slug 暂定待 data 落地对齐 |
| `enemies/thorn_turret.png` | 16x16 | 敌人「荆棘炮台」(A1/turret) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 固定抛物 3 连发; slug 暂定待 data 落地对齐 |
| `enemies/spore_flower.png` | 16x16 | 敌人「孢子召唤花」(A1/summoner) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 每 4s 出 1 苦力虫(上限 3); slug 暂定待 data 落地对齐 |
| `enemies/stone_boar.png` | 16x16 | 敌人「石皮野猪」(A1/charger) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 受击后狂暴冲锋; slug 暂定待 data 落地对齐 |
| `enemies/ruin_archer.png` | 16x16 | 敌人「遗迹弓手」(A1/shooter) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 后撤步+射击交替; slug 暂定待 data 落地对齐 |
| `enemies/moss_slime.png` | 16x16 | 敌人「苔藓史莱姆」(A1/splitter) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 死亡分裂 2; slug 暂定待 data 落地对齐 |
| `enemies/glowbug_swarm.png` | 16x16 | 敌人「萤光虫群」(A1/suicide) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 3 只一组扑向玩家; slug 暂定待 data 落地对齐 |
| `enemies/old_tree_guard.png` | 16x16 | 敌人「老树守卫」(A1/tank) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 缓慢逼近+根部弹环; slug 暂定待 data 落地对齐 |
| `enemies/seed_pitcher.png` | 16x16 | 敌人「种子投手」(A1/barrage) | 附录 B（A1）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 抛物种子落地 30% 生虫; slug 暂定待 data 落地对齐 |
| `enemies/crystal_bat.png` | 16x16 | 敌人「晶簇蝙蝠」(A2/wanderer) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 死亡爆 4 向晶针; slug 暂定待 data 落地对齐 |
| `enemies/ice_mage.png` | 16x16 | 敌人「冰晶法师」(A2/barrage) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 冰环弹+冰缓; slug 暂定待 data 落地对齐 |
| `enemies/magnet_golem.png` | 16x16 | 敌人「磁石傀儡」(A2/tank) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 把玩家拉拽 2 格; slug 暂定待 data 落地对齐 |
| `enemies/ghost_jelly.png` | 16x16 | 敌人「幽光水母」(A2/wanderer) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 电弧链, 漂移无规律; slug 暂定待 data 落地对齐 |
| `enemies/frost_crab.png` | 16x16 | 敌人「冻土巨蟹」(A2/tank) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 横向钳击(预警扇区); slug 暂定待 data 落地对齐 |
| `enemies/crystal_rat.png` | 16x16 | 敌人「窃晶鼠群」(A2/suicide) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 4 只散兵, 偷 5 金后逃跑; slug 暂定待 data 落地对齐 |
| `enemies/rock_crystal_turret.png` | 16x16 | 敌人「岩晶炮台」(A2/turret) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 蓄能直线激光(0.5s 警示线); slug 暂定待 data 落地对齐 |
| `enemies/crystal_summoner.png` | 16x16 | 敌人「晶核召唤师」(A2/summoner) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 每 5s 召 2 窃晶鼠; slug 暂定待 data 落地对齐 |
| `enemies/prism_ranger.png` | 16x16 | 敌人「棱镜游侠」(A2/shooter) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 借晶柱折射(拐角弹); slug 暂定待 data 落地对齐 |
| `enemies/ice_spider.png` | 16x16 | 敌人「冰蛛」(A2/splitter) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 3 只结网(1.5s 禁锢); slug 暂定待 data 落地对齐 |
| `enemies/echo_lurker.png` | 16x16 | 敌人「深窟回响者」(A2/barrage) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 模仿玩家上次武器弹形; slug 暂定待 data 落地对齐 |
| `enemies/crystal_dragon.png` | 16x16 | 敌人「晶背龙蜥」(A2/charger) | 附录 B（A2）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 撞墙自晕 1s(输出窗); slug 暂定待 data 落地对齐 |
| `enemies/lava_hound.png` | 16x16 | 敌人「熔岩犬」(A3/charger) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 两段扑咬, 附带燃烧; slug 暂定待 data 落地对齐 |
| `enemies/ash_shooter.png` | 16x16 | 敌人「灰烬射手」(A3/shooter) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 3 连发点射; slug 暂定待 data 落地对齐 |
| `enemies/firerain_priest.png` | 16x16 | 敌人「火雨祭司」(A3/barrage) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 召唤火雨区(红圈预警); slug 暂定待 data 落地对齐 |
| `enemies/magma_slime.png` | 16x16 | 敌人「熔核史莱姆」(A3/splitter) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 分裂 2 中型再分裂; slug 暂定待 data 落地对齐 |
| `enemies/obsidian_guard.png` | 16x16 | 敌人「黑曜卫」(A3/tank) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 盾墙推进, 推动玩家; slug 暂定待 data 落地对齐 |
| `enemies/sulfur_moth.png` | 16x16 | 敌人「硫磺蛾群」(A3/suicide) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 爆燃留燃烧地面; slug 暂定待 data 落地对齐 |
| `enemies/lava_turret.png` | 16x16 | 敌人「岩浆喷吐炮台」(A3/turret) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 扇形 5 喷发; slug 暂定待 data 落地对齐 |
| `enemies/ember_summoner.png` | 16x16 | 敌人「余烬召唤师」(A3/summoner) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 召 2 熔岩犬; slug 暂定待 data 落地对齐 |
| `enemies/scorch_stomper.png` | 16x16 | 敌人「焦土践踏者」(A3/charger) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 跺地引发环形火浪; slug 暂定待 data 落地对齐 |
| `enemies/flame_lich.png` | 16x16 | 敌人「烈焰巫妖」(A3/barrage) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 火墙推进弹; slug 暂定待 data 落地对齐 |
| `enemies/magma_wyvern.png` | 16x16 | 敌人「熔火飞龙」(A3/wanderer) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 俯冲喷吐直线火; slug 暂定待 data 落地对齐 |
| `enemies/starmarrow_blob.png` | 16x16 | 敌人「星髓聚合体」(A3/barrage) | 附录 B（A3）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 随机切换 4 元素弹幕; slug 暂定待 data 落地对齐 |
| `enemies/undead_gunner.png` | 16x16 | 敌人「亡灵枪手(小Boss)」(MINIBOSS/shooter) | 附录 B（MINIBOSS）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 复制玩家武器弹形对枪; slug 暂定待 data 落地对齐 |
| `enemies/stone_shield_monk.png` | 16x16 | 敌人「石盾武僧(小Boss)」(MINIBOSS/tank) | 附录 B（MINIBOSS）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 正面格挡一切, 绕背破势; slug 暂定待 data 落地对齐 |
| `enemies/volt_spider.png` | 16x16 | 敌人「电磁蛛(小Boss)」(MINIBOSS/splitter) | 附录 B（MINIBOSS）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 电弧链场, 杀小蛛断链; slug 暂定待 data 落地对齐 |
| `enemies/marsh_toad.png` | 16x16 | 敌人「腐沼巨蛙(小Boss)」(MINIBOSS/splitter) | 附录 B（MINIBOSS）暂无 data 行; M1 为 ARCHETYPE_COLORS 纯色块 | 吞弹存伤害后吐还; slug 暂定待 data 落地对齐 |
| `enemies/gem_queen.png` | 48x48 | Boss「宝石蜂后（A1-②）」48x48 | 附录 E 招式规格; 现无 data 行/脚本 | 召唤蜂群+冲锋; P2 蜂巢柱可破坏掩体 |
| `enemies/crystal_golem.png` | 48x48 | Boss「晶棱魔像（A2-①）」48x48 | 附录 E 招式规格; 现无 data 行/脚本 | 激光借晶柱折射; P3 瞬移弹幕 |
| `enemies/frost_spider_mother.png` | 48x48 | Boss「寒渊蛛母（A2-②）」48x48 | 附录 E 招式规格; 现无 data 行/脚本 | 铺冰面+蛛网禁锢; P3 冰晶牢笼 |
| `enemies/magma_tyrant.png` | 48x48 | Boss「熔核暴君（A3-①）」48x48 | 附录 E 招式规格; 现无 data 行/脚本 | 岩浆喷区+火雨; P3 地裂火浪 |
| `enemies/starfall_prophet.png` | 48x48 | Boss「星陨先知（A3-②隐藏）」48x48 | 附录 E 招式规格; 现无 data 行/脚本 | 全元素轮回+共鸣攻击 |
| `enemies/kuli_bug_sheet.png` | 32x16 | 敌人「苦力虫」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/cave_bat_sheet.png` | 32x16 | 敌人「穴蝠」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/crossbowman_sheet.png` | 32x16 | 敌人「弩兵」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/mud_slime_sheet.png` | 32x16 | 敌人「泥浆史莱姆」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/vine_charger_sheet.png` | 32x16 | 敌人「藤蔓冲锋者」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/mushroom_spore_sheet.png` | 32x16 | 敌人「蘑菇孢子手」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/hardshell_turtle_sheet.png` | 32x16 | 敌人「硬壳龟」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/wing_lizard_sheet.png` | 32x16 | 敌人「飞行翼蜥」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/thorn_turret_sheet.png` | 32x16 | 敌人「荆棘炮台」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/spore_flower_sheet.png` | 32x16 | 敌人「孢子召唤花」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/stone_boar_sheet.png` | 32x16 | 敌人「石皮野猪」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/ruin_archer_sheet.png` | 32x16 | 敌人「遗迹弓手」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/moss_slime_sheet.png` | 32x16 | 敌人「苔藓史莱姆」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/glowbug_swarm_sheet.png` | 32x16 | 敌人「萤光虫群」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/old_tree_guard_sheet.png` | 32x16 | 敌人「老树守卫」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/seed_pitcher_sheet.png` | 32x16 | 敌人「种子投手」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/crystal_bat_sheet.png` | 32x16 | 敌人「晶簇蝙蝠」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/ice_mage_sheet.png` | 32x16 | 敌人「冰晶法师」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/magnet_golem_sheet.png` | 32x16 | 敌人「磁石傀儡」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/ghost_jelly_sheet.png` | 32x16 | 敌人「幽光水母」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/frost_crab_sheet.png` | 32x16 | 敌人「冻土巨蟹」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/crystal_rat_sheet.png` | 32x16 | 敌人「窃晶鼠群」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/rock_crystal_turret_sheet.png` | 32x16 | 敌人「岩晶炮台」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/crystal_summoner_sheet.png` | 32x16 | 敌人「晶核召唤师」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/prism_ranger_sheet.png` | 32x16 | 敌人「棱镜游侠」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/ice_spider_sheet.png` | 32x16 | 敌人「冰蛛」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/echo_lurker_sheet.png` | 32x16 | 敌人「深窟回响者」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/crystal_dragon_sheet.png` | 32x16 | 敌人「晶背龙蜥」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/lava_hound_sheet.png` | 32x16 | 敌人「熔岩犬」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/ash_shooter_sheet.png` | 32x16 | 敌人「灰烬射手」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/firerain_priest_sheet.png` | 32x16 | 敌人「火雨祭司」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/magma_slime_sheet.png` | 32x16 | 敌人「熔核史莱姆」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/obsidian_guard_sheet.png` | 32x16 | 敌人「黑曜卫」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/sulfur_moth_sheet.png` | 32x16 | 敌人「硫磺蛾群」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/lava_turret_sheet.png` | 32x16 | 敌人「岩浆喷吐炮台」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/ember_summoner_sheet.png` | 32x16 | 敌人「余烬召唤师」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/scorch_stomper_sheet.png` | 32x16 | 敌人「焦土践踏者」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/flame_lich_sheet.png` | 32x16 | 敌人「烈焰巫妖」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/magma_wyvern_sheet.png` | 32x16 | 敌人「熔火飞龙」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `enemies/starmarrow_blob_sheet.png` | 32x16 | 敌人「星髓聚合体」2 帧动画表（列=idle+walk, 16px/帧） | room_combat.gd _tick_enemy_anim 帧驱动; Sprite hframes=2 vframes=1 | m2-t21：移动中 8t/帧交替 idle/walk；静止恒 idle 列0；缺表敌种回落单帧图 |
| `characters/hero_mage.png` | 16x16 | 英雄「法师·烬」站立像（正面） | GDD §6 角色表; data/heroes.json M2 待加行 | 回响: 法杖/激光伤 +15% |
| `ui/portrait_mage.png` | 32x32 | 法师·烬 选人头像 32x32 | ui/hero_select.gd 卡片 | — |
| `ui/skill_arcane_nova.png` | 16x16 | 技能图标「奥术新星」(烬) | GDD §6 技能表 | 奥术新星(CD10s/蓝20): 120px 冰霜新星+冻结 |
| `ui/skill_arcane_nova_plus.png` | 16x16 | 技能升级版图标「奥术新星+」 | GDD §6 蓝晶 1500/名解锁 | — |
| `ui/passive_echo.png` | 12x12 | 被动图标（回响·法师·烬） | GDD §6 被动列 | 回响: 法杖/激光伤 +15% |
| `characters/hero_assassin.png` | 16x16 | 英雄「刺客·蝉」站立像（正面） | GDD §6 角色表; data/heroes.json M2 待加行 | 掠影: 近战杀返 5 蓝+翻滚无 CD 1s |
| `ui/portrait_assassin.png` | 32x32 | 刺客·蝉 选人头像 32x32 | ui/hero_select.gd 卡片 | — |
| `ui/skill_afterimage_slash.png` | 16x16 | 技能图标「残影斩」(蝉) | GDD §6 技能表 | 残影斩(CD8s): 突进 220px 无敌, 2x30 伤 |
| `ui/skill_afterimage_slash_plus.png` | 16x16 | 技能升级版图标「残影斩+」 | GDD §6 蓝晶 1500/名解锁 | — |
| `ui/passive_swift_shadow.png` | 12x12 | 被动图标（掠影·刺客·蝉） | GDD §6 被动列 | 掠影: 近战杀返 5 蓝+翻滚无 CD 1s |
| `characters/hero_engineer.png` | 16x16 | 英雄「工程师·铆」站立像（正面） | GDD §6 角色表; data/heroes.json M2 待加行 | 备件: 开局/进层补便携炮台 |
| `ui/portrait_engineer.png` | 32x32 | 工程师·铆 选人头像 32x32 | ui/hero_select.gd 卡片 | — |
| `ui/skill_turret.png` | 16x16 | 技能图标「自动炮台」(铆) | GDD §6 技能表 | 自动炮台(CD12s): 部署炮台(上限 2) |
| `ui/skill_turret_plus.png` | 16x16 | 技能升级版图标「自动炮台+」 | GDD §6 蓝晶 1500/名解锁 | — |
| `ui/passive_spare_parts.png` | 12x12 | 被动图标（备件·工程师·铆） | GDD §6 被动列 | 备件: 开局/进层补便携炮台 |
| `characters/hero_guardian.png` | 16x16 | 英雄「守护者·萄」站立像（正面） | GDD §6 角色表; data/heroes.json M2 待加行 | 祝福: 进层满盾+5% 伤(叠 4) |
| `ui/portrait_guardian.png` | 32x32 | 守护者·萄 选人头像 32x32 | ui/hero_select.gd 卡片 | — |
| `ui/skill_life_tide.png` | 16x16 | 技能图标「生命潮汐」(萄) | GDD §6 技能表 | 生命潮汐(CD14s/蓝30): 回 2HP+治疗法阵 3s |
| `ui/skill_life_tide_plus.png` | 16x16 | 技能升级版图标「生命潮汐+」 | GDD §6 蓝晶 1500/名解锁 | — |
| `ui/passive_blessing.png` | 12x12 | 被动图标（祝福·守护者·萄） | GDD §6 被动列 | 祝福: 进层满盾+5% 伤(叠 4) |
| `ui/buffs/hunter.png` | 12x12 | Buff 图标「猎杀者」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 对异常目标伤害 +20% |
| `ui/buffs/resonance_amplify.png` | 12x12 | Buff 图标「共鸣增幅」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 共鸣 AoE +30%/持续 +1s |
| `ui/buffs/vengeance.png` | 12x12 | Buff 图标「复仇者」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 受击后 3s 伤害 +25% |
| `ui/buffs/anti_fire.png` | 12x12 | Buff 图标「抗火」(common) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 免疫燃烧; 岩浆伤 -50% |
| `ui/buffs/anti_ice.png` | 12x12 | Buff 图标「抗冰」(common) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 免疫冰缓与打滑 |
| `ui/buffs/anti_poison.png` | 12x12 | Buff 图标「抗毒」(common) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 免疫中毒 |
| `ui/buffs/nerve_reflex.png` | 12x12 | Buff 图标「神经反射」(uncommon) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 受击无敌帧 +0.25s |
| `ui/buffs/carapace.png` | 12x12 | Buff 图标「甲壳」(uncommon) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 弹幕伤害 -8% |
| `ui/buffs/thorns.png` | 12x12 | Buff 图标「荆棘护甲」(uncommon) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 被接触反伤 3 |
| `ui/buffs/dash_extend.png` | 12x12 | Buff 图标「冲刺延伸」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 翻滚距离 +25% |
| `ui/buffs/phoenix.png` | 12x12 | Buff 图标「不死鸟(唯一)」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 致死保留 1 HP(每局 1 次) |
| `ui/buffs/wealth.png` | 12x12 | Buff 图标「财富」(common) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 金币获取 +20% |
| `ui/buffs/big_eater.png` | 12x12 | Buff 图标「大胃王」(common) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 饮料效果 +50% |
| `ui/buffs/pickup_magnet.png` | 12x12 | Buff 图标「捡拾磁铁」(common) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 拾取范围 +60% |
| `ui/buffs/energy_leech.png` | 12x12 | Buff 图标「蓝能汲取」(uncommon) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 击杀 10% 回 2 蓝 |
| `ui/buffs/heart_sense.png` | 12x12 | Buff 图标「红心感应」(uncommon) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 红心掉率 +50% |
| `ui/buffs/ammo_convert.png` | 12x12 | Buff 图标「弹药转化」(uncommon) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 每 30s 回 10 蓝 |
| `ui/buffs/haggle.png` | 12x12 | Buff 图标「议价」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 商店价格 -15% |
| `ui/buffs/element_vision.png` | 12x12 | Buff 图标「元素视界」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 预警 +0.15s 更醒目 |
| `ui/buffs/resonance_vision.png` | 12x12 | Buff 图标「共鸣视界」(blue) | 附录 C 共 36 条; M1 已 16 条, 此为新增 20 条（slug 暂定） | 异常敌人高亮描边 |
| `tiles/floor_crystal.png` | 16x16 | A2 晶核洞穴地板 | GDD §10 A2 生态（暂无实现） | 替换需 16x16 无缝 |
| `tiles/wall_crystal.png` | 16x16 | A2 晶核洞穴墙体 | 同上 | 顶部亮色已内嵌 |
| `tiles/floor_magma.png` | 16x16 | A3 熔火核心地板 | GDD §10 A3 生态 | — |
| `tiles/wall_magma.png` | 16x16 | A3 熔火核心墙体 | 同上 | — |
| `tiles/corridor_crystal.png` | 16x16 | A2 走廊地板 | floor_scene.gd:355-357 | — |
| `tiles/corridor_magma.png` | 16x16 | A3 走廊地板 | 同上 | — |
| `tiles/hazard_ice.png` | 16x16 | 冰面（摩擦减半打滑） | GDD §10 A2 危险地块 | 半透明叠在地板上 |
| `tiles/hazard_lava.png` | 16x16 | 岩浆（DOT 2/s） | GDD §10 A3 危险地块 | 边缘与地板过渡 |
| `tiles/hazard_spikes.png` | 16x16 | 地刺（周期伸缩） | GDD §10 A2 陷阱 | 伸出/缩回 2 帧共用本图+变形 |
| `tiles/hazard_vent.png` | 16x16 | 间歇喷口（预警后喷发） | GDD §10 A3 陷阱 | 喷发时叠加 fx_explosion |
| `tiles/prop_crystal_pillar.png` | 16x16 | 晶柱（可破坏掩体/激光折射, 8~20HP） | GDD §9.2 签名系统#3 | 碎裂 2 帧后留碎块 |
| `tiles/prop_crystal_pillar_broken.png` | 16x16 | 晶柱碎块（无碰撞贴地） | GDD §9.2 摧毁后留碎块 | — |
| `tiles/prop_debris.png` | 16x16 | 残骸（可破坏掩体） | GDD §9.2 | — |
| `tiles/fusion_forge.png` | 20x18 | 熔铸台（每层 1, 2 武器→配方产物） | GDD §8.3 签名系统#2; 附录 D 15 配方 | 工作时有火光动画 |
| `tiles/event_merchant.png` | 16x18 | 事件：神秘商人（2 HP 换 1 道具） | GDD §11 事件房/附录 F.3; 现为纯文字面板 | — |
| `tiles/event_beggar.png` | 16x18 | 事件：乞丐（投 40 金 70% 返 120） | 附录 F.3 | 脚边碗 |
| `tiles/event_spring.png` | 16x18 | 事件：星髓泉（本局盾上限 +1） | 附录 F.3 | — |
| `tiles/event_graffiti.png` | 18x18 | 事件：涂鸦墙（随机构筑提示） | 附录 F.3 | — |
| `tiles/totem_revive.png` | 16x20 | 复活图腾（Boss 房前 150 金, 一次性） | GDD §14.2 价格锚点 | 图腾眼=红心 |
| `tiles/recycle_rack.png` | 16x16 | 回收架（商店门口, 弃枪 30% 回收） | GDD §8.2 | — |
| `tiles/chest_crit.png` | 16x16 | 暴击宝箱（15% 出现, 三倍掉落/25% 弹 3 波怪） | GDD §11 宝箱房 | 金身+蓝星 |
| `ui/icon_bluecrystal.png` | 12x12 | 蓝晶（局外货币） | GDD §14.1; 现无局外 UI | 死亡保留 50% 提示用同图 |
| `ui/icon_talent.png` | 12x12 | 主菜单入口：天赋树 | GDD §19 局外循环 | — |
| `ui/icon_codex.png` | 12x12 | 主菜单入口：武器图鉴（115） | GDD §19/§8.1 图鉴解锁掉落池 | — |
| `ui/icon_achievement.png` | 12x12 | 主菜单入口：成就（24） | 附录 G.1 | — |
| `ui/frame_medal.png` | 16x16 | 成就勋章框（列表/解锁 toast 用） | 附录 G.1 成就+蓝晶奖励 | 绶带=蓝晶色 |
| `ui/talents/node_empty.png` | 12x12 | 天赋节点（未点亮） | GDD §19 天赋树; 附录 G 天赋异禀 12 节点 | 连线由代码画 |
| `ui/talents/node_filled.png` | 12x12 | 天赋节点（已点亮） | GDD §19 天赋树; 附录 G 天赋异禀 12 节点 | 连线由代码画 |
| `ui/icon_death_source.png` | 12x12 | 死亡回顾：致死弹来源高亮标记 | GDD §19 死亡回顾（来源回放 3s）; M1 death_summary 纯文字 | — |
| `ui/minimap/challenge.png` | 8x8 | 小地图图标：挑战房（灾厄三选一） | GDD §11 挑战房（M2 新房型） | — |

## 缺口与待采购（无法程序生成，需外部获取/委托）

| 项 | 说明 | 建议 |
|---|---|---|
| 像素中文字体 | 全 UI 伤害数字/菜单/对话用默认字体，无像素风格 | 开源可选：缝合怪像素字体 Fusion Pixel Font（OFL）、Zpix（个人免费）；落位 `art/fonts/` |
| 四向行走动画 | **m2-t17 已程序化交付**：`characters/hero_<id>_sheet.png`（4 向 x idle+walk×3, 16px/帧），player.gd 移动方向自动切换 | 正式素材可按此帧表布局连锁重绘；敌人 2 帧动画亦已交付（m2-t21 `enemies/<id>_sheet.png`） |
| 敌人受击/死亡动画 | 目前仅白闪+爆粒子 | 每敌 2-4 帧即可显著提升手感 |
| 雕像四 kinds 精绘 | 通用底 + 4 属性变体已备（shrine_*.png），披肩/徽记方案区分 | 正式素材按变体配色委托精绘即可 |
| 地图整块背景装饰 | 墙沿/悬挂物/裂纹大图 | 可后置，优先级低 |
| 正式 LOGO | 占位为系统字体渲染 | 像素字重绘或外包 |

## 二次排查记录（无需出图/配置项）

- **启动 Splash**：project.godot 未配置 boot_splash，现显示 Godot 默认闪屏 → 建议配置 `application/boot_splash/bg_color=#12141a`（纯配置，非素材）。
- **训练房**（training_room.gd）：木桩/拾取靶为开发用场景，复用 `tiles/prop_crate.png` 与 `pickups/*` 即可，不单独出图。
- **交互浮标**（ui/interact_prompt.gd）：纯文字 Label（action_label），如需键位图标可后补 `ui/key_e.png`。
- **事件面板**（core/interact/events.gd）：纯文字选项卡，暂无图标需求；若做事件插画再补。
- **商店**（shop_logic.gd）：售卖品为 武器/饮料/红心/蓝能 → 图标已全部覆盖（ui/weapons、ui/drinks、pickups/heart、pickups/energy）。
- **武器手持外观**：当前武器只在 HUD/商店以图标出现，手上无武器贴图（元气骑士有持枪图）→ **已备好** `weapons/*.png` 40 张（16x16 朝右、持握点(4,8)、接线约定见清单行）；是否接入由后续决定。
- **小地图**：游戏暂无小地图，`ui/minimap/*` 8 类型图标已按 floor_flow.gd 房间类型全集预留。
- **应用图标**：icon.svg 已是自定义星形（非 Godot 默认）；`ui/icon_app.png` 为像素风备选。

## 三次排查记录（M1 证据图 + 剩余文件复查）

- 方法：逐张复查 `docs/superpowers/reports/m1-evidence/` 10 张实机截图，并补读黑市/延迟爆/死亡结算/门动画等未排查文件。
- **雕像四属性变体已补**：`tiles/shrine_{zhanshen,jingling,fengshen,xingsui}.png`（M1 商店房四尊实景）。
- **延迟爆无预警已补**：`fx/fuse_zone.png`——`delayed_blast.gd` 此前零绘制，72px 爆炸范围对玩家不可见。
- **黑市视觉区分已补**：`ui/icon_blackmarket.png` + `tiles/shopkeeper{,_black}.png`（此前仅标题文字「黑市商人」+ 价格 ×1.8）。
- m1-02 截图中的黄色弧点为子弹流（PLAYER_BULLET_COLOR），非挥砍视觉；melee.gd 仍无挥砍特效，`fx/fx_slash.png` 接线后为新增表现。
- 门动画（floor_scene.gd:378-384 + fx/door_anim.gd）用 `tiles/door_*.png` 即可；死亡结算/事件面板/运行根提示均为纯文字，无素材需求。
- 结论：M1 全部实机内容（含证据图 10 张）与代码视觉点至此均已建档，无未覆盖项。

## 生成参数

- 脚本：`tools/gen_placeholder_art.py`（M1 批次+公共库，自动串联 `tools/gen_placeholder_art_m2.py`）
- M2 批次（附录 A/B/C 驱动）：武器 115 双套图/敌人 40 单帧+2 帧动画表/Boss 6/英雄 6 全家桶/增益 36/三生态地块/事件设施/局外 UI。
- **武器/敌人 id 均以 data/*.json 为唯一权威**（m2-t21 收编，数据驱动出图）；仅 M2 Boss 5 种 slug 为附录 E 暂定名（data 行未落地）。
- Python 3.12 + Pillow 12.3；随机种子固定 42，输出可复现；全量再生=先生成后按本清单清理陈旧（失败不毁库）。
- 联络表：`_preview.png`（4x 放大，人工检查用，勿在游戏内引用）。