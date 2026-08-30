# M2 全内容 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task-by-task, organized by the Wave table (roadmap §2.1 并行波次规范). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 交付 GDD §20 全量内容——3 层生态、6 Boss+小 Boss 池、6 角色、武器 115、敌人 40、增益 36、熔铸、天赋树/图鉴/成就、音频全套、胜利结算——达成 M2 门禁（1000 种子×3 生态、§18.3 性能预算、§14.3 可量化节奏）。

**Architecture:** 延续 M0/M1 既有架构（60Hz 逻辑帧、数据驱动 JSON、RngSvc 分盐、池化、preload 原型映射、纯逻辑类+薄场景层）。新增：生态机制组件层（A 束）、SummonBase 召唤框架（B 束）、熔铸/图鉴/成就/天赋树四大 meta 系统（C/E 束）、audio_mgr（G 束）。

**Tech Stack:** Godot 4.7.2 / GDScript / GdUnit4 6.2.1（锁定，勿升级）。

## Global Constraints（继承 M1 + M2 增补）

1. 60Hz 逻辑帧（`TimeConst.ticks`）；伤害固定值，暴击唯一随机乘区；480×270 nearest；场景零硬编码玩法数值；代码英文/文案中文；conventional commits 带卡号。
2. RNG 只经 `RunState.stream(salt)` 派生；**盐常量一律收敛到 RunState**（新盐必须加 const，禁止调用点字面量）；**同盐禁多处派生**（M1 终审 Issue 3）——每设施独立盐或常驻流。
3. 数值唯一出处 = 数据表附录 A~H + 新增附录 I（天赋树）；实现者发现矛盾→停止上报编排者。
4. 敌弹单独上限 400 / 池总 500；房间 JSON 走 GameDB schema 校验 fail-closed；EnemyBase 用 preload 映射。
5. 热路径零分配：**禁止在 `_process`/`_physics_process` 内拼接字符串路径或新建 Dictionary**（M1 终审 Important ①）；纹理查 ArtLookup 必须走缓存接口。
6. 合并进 main 后必须 `godot --headless --path . --import` 再跑全量测试；`.import`/`__pycache__` 已入 .gitattributes/.gitignore，勿提交噪音。
7. TDD：可测逻辑先 RED 后 GREEN；场景卡附手动验证清单；worktree 隔离 + 每波 ≤3 实现者。
8. **每束末卡显式承担集成收口**（M1-T27 教训）；改 `data/*.json` 的卡须附分布/一致性测试。

## 波次总表（依赖 + 文件所有权摘要）

| 波 | 卡 | 依赖 | 独占文件（摘要） |
|---|---|---|---|
| W0 | T1 S0 加固 | — | core/art/art_lookup.gd, autoload/run_state.gd(盐), tests/unit/test_skills.gd |
| W0 | T2 天赋树全表定稿 | — | docs 附录 I(新), data/talents.json, tests/unit/test_talents_data.gd |
| W0 | T3 图鉴 49 条+成就接线表+增益白名单 | — | docs 附录(新增节), tests/unit/test_unlock_data.gd |
| W1 | T4 A2 暗视野+冰面 | — | core/rooms/biome_fx.gd, core/rooms/floor_scene.gd(挂点), fx/dark_vision.gd |
| W1 | T5 音频管理器+sfx | — | autoload/audio_mgr.gd, project.godot, core/player/weapon_rig.gd(1 行), core/enemies/enemy_base.gd(1 行) |
| W1 | T6 武器扩至 115 | — | data/weapons.json, tests/unit/test_weapons_pool.gd |
| W2 | T7 A2 地刺+晶柱折射+A1 补全 | T4 | core/rooms/hazard_*.gd, core/enemies/laser.gd(新敌用), data/enemies.json(A2 行) |
| W2 | T8 召唤框架+工程师 | — | core/summons/summon_base.gd, core/player/skills/turret.gd, data/heroes.json(工程师行) |
| W2 | T9 敌人补齐 40 | — | data/enemies.json, tests/unit/test_enemy_ai.gd(追加) |
| W3 | T10 A3 机制 | T7 | core/rooms/hazard_magma.gd 等, data/rooms/a3_*.json |
| W3 | T11 法师+守护者技能 | T2,T8 | core/player/skills/arcane_nova.gd, life_tide.gd |
| W3 | T12 增益 +21 → 36 | — | data/buffs.json, core/meta/buff_manager.gd(聚合键) |
| W4 | T13 刺客+守护者数据+选角扩展 | T8,T11 | data/heroes.json, ui/hero_select.gd(列表自动) |
| W4 | T14 D-1 宝石蜂后+晶棱魔像 | T7 | core/enemies/bosses/gem_queen.gd, prism_golem.gd |
| W4 | T15 E-1 天赋树系统落地 | T2 | core/meta/talent_system.gd, ui/talents.tscn |
| W5 | T16 D-2 寒渊蛛母 | T14 | core/enemies/bosses/frost_widow.gd |
| W5 | T17 I-1 英雄行走帧 | — | tools/gen_placeholder_art.py, art/generated/characters/** |
| W5 | T18 F-1 胜利结算完整 | T15 | ui/victory_summary.tscn |
| W6 | T19 D-3 寒渊蛛母收口+熔核暴君 | T16 | core/enemies/bosses/magma_tyrant.gd |
| W6 | T20 E-2 图鉴+解锁引擎 | T3,T6 | core/meta/codex_system.gd, ui/codex.tscn |
| W6 | T21 I-2 敌人 2 帧动画 | T17 | tools/gen_placeholder_art.py, art/generated/enemies/** |
| W7 | T22 D-4 星陨先知+隐藏门 | T13,T19 | core/enemies/bosses/starfall_prophet.gd, core/rooms/floor_scene.gd(隐藏门) |
| W7 | T23 G-2 音乐 5 曲+Boss 切层 | T5 | tools/gen_placeholder_sfx.py 或 musicgen, autoload/audio_mgr.gd |
| W7 | T24 F-2 死亡回顾完整(3s 回放+DPS 采样) | T18 | core/meta/death_recorder.gd |
| W8 | T25 熔铸台场景接线 | T12,T16 | core/rooms/floor_scene.gd(熔铸房), ui/forge.gd |
| W8 | T26 挑战房灾厄+房型复核 | T10 | core/rooms/floor_scene.gd(挑战房), core/interact/** |
| W8 | T27 A2/A3 瓦片接线验证+元素弹分化 | T10 | art/generated/tiles/**(核对), core/art/art_lookup.gd(分化贴图) |
| W9 | T28 H-1 Balance Bot 全层回归 | T25 | tools/balance_bot.gd, tests/scenes/ |
| W9 | T29 H-2 §18.3 全指标压测 | T27 | tests/scenes/perf_probe.gd, docs/superpowers/reports/m2-perf.md |
| W9 | T30 H-3 Windows 导出冒烟+Android 链预通 | — | export_presets.cfg, tools/export_smoke.cmd |
| W10 | T31 蓝晶结算+E-4 存档 migration v2 | T15,T17 | autoload/save_system.gd(v2), autoload/run_state.gd |
| W10 | T32 成就系统(22 激活) | T20 | core/meta/achievement_system.gd, ui/toast.tscn |
| W10 | T33 门禁预检（收口复核+全部移交项闭环） | 全部 | docs/superpowers/reports/m2-precheck.md |
| W11 | T34 M2 门禁 | 全部 | docs/superpowers/reports/m2-gate-*.md |

> 计 34 卡（W0×3 + 各束 31 + 门禁）。束内细分见各卡；所有卡实现时另附 `.uid` 提交。

---

### Task 1: S0 加固微卡（M1 终审 Important ①③ + 移交项收口）

**Files:** Modify `core/art/art_lookup.gd`、`autoload/run_state.gd`、`core/interact/shop.gd`、`core/interact/shrine.gd`、`core/interact/drink_machine.gd`、`core/rooms/inter_floor.gd`、`core/rooms/floor_scene.gd`、`tests/unit/test_skills.gd`、`tests/unit/test_art_lookup.gd`

**契约（Produces）：** `ArtLookup.bullet_texture(faction: int, element: int) -> Texture2D`（静态字典缓存，热路径零字符串分配）；`RunState.SALT_SHOP/SALT_SHRINE/SALT_DRINK/SALT_INTER_FLOOR/SALT_EVENT` 常量；五处 SALT_LOOT 派生全部改为各自独立盐。

- [ ] Step 1 失败测试：`tests/unit/test_art_lookup.gd` 追加——连发 500 次 `projectile_texture_path` 后以 `perf::get_monitor` 或简单计数断言"零新增字符串分配"不可行，改为：暴露 `static var _path_cache_size: int` 并断言同参数二次调用命中缓存（计数不变）。
- [ ] Step 2 实现：`art_lookup.gd` 增 `static var _proj_tex: Dictionary = {}`；`bullet_texture(faction, element)` 先查缓存，miss 才拼路径 + `load()`；删除/保留旧 `projectile_texture_path` 为私有。
- [ ] Step 3 SALT_LOOT→独立盐：`run_state.gd` 加 5 个盐常量；`shop.gd/shrine.gd/drink_machine.gd/inter_floor.gd/floor_scene.gd` 各调用点换 `RunState.stream(RunState.SALT_SHOP)` 等；**删净所有 `SALT_LOOT` 残留**（grep 验证）。
- [ ] Step 4 夹具清理：`tests/unit/test_skills.gd` 移除 testgun_cost5 注入并加 `after_test` 恢复断言（镜像 test_weapon_rig.gd 模式）。
- [ ] Step 5 全量绿 → Commit `fix(m2-t1): artlookup texture memo, per-facility salts, fixture cleanup`。

### Task 2: P0 天赋树全表定稿（设计+数据卡）

**Files:** Create `data/talents.json`、`docs/superpowers/specs/数据表附录-I-天赋树.md`（数据表附录新增节）、`tests/unit/test_talents_data.gd`
**规格（出处 GDD §14.3/§20 + 成就表）：** 24 节点、总蓝晶价 ≈ 满足"10h 点满 60%"经济曲线（蓝晶获取速率按 M1 实测 500~700/小时校准，节点价格梯度 100~800）；每节点 `{id, name(中文), desc(中文), cost:int, requires:Array[String](前置), effects:{...}}`；效果键白名单沿用 buff_manager 既有键 + 新键须在本卡定义并列出消费方（M2-E 落地）。分支结构：红(攻击 8)/蓝(防御 8)/绿(资源 8) 三系各 8 节点串并联。schema 校验 fail-closed（含 requires 引用存在性、无环校验）。
- [ ] TDD：schema 校验（坏行/坏引用/环）+ 24 行计数 + 三系各 8 + 无环拓扑排序成功。
- [ ] Commit `feat(m2-t2): talent tree data table with schema validation`。

### Task 3: P0 图鉴解锁 49 条 + 成就接线表 + 增益白名单

**Files:** Modify 数据表附录（新增"附录 J 图鉴解锁任务"+"附录 K 成就接线表"两节）、`data/unlock_tasks.json`、`tests/unit/test_unlock_data.gd`
**规格：** 49 条 = 全部紫/橙武器（33+16=49）逐一给出解锁条件（条件类型白名单：kill_x / clear_floor_x / craft_x / resonate_x / collect_gems_x / buy_x，参数+阈值，全部可用遥测或 RunState 判定）；成就接线表 = 24 条成就 ↔ 触发信号↔判定数据（22 条标注 M2 激活信号名，2 条试炼标注 M3）；`data/buffs.json` 新增 21 条增益的效果键白名单扩展清单（新键逐一列出并写明消费卡号）。
- [ ] TDD：49 条计数、条件类型白名单校验、参数阈值 int、与 data/weapons.json 稀有度分布一致（49=紫+橙）。
- [ ] Commit `feat(m2-t3): codex unlock tasks (49) + achievement wiring table`。

### Task 4: A2 生态——暗视野 + 冰面

**Files:** Create `core/rooms/biome_aura.gd`（CanvasModulate+PointLight2D 玩家光圈组件）、`core/rooms/ice_floor.gd`（低摩擦区组件）；Modify `core/rooms/floor_scene.gd`（A2 模板挂载钩子）；Create `tests/unit/test_biome_a2.gd`
**规格（GDD §10 A2）：** 暗视野 = CanvasModulate 调暗至 (0.25,0.25,0.35) + 玩家 PointLight2D 半径 140px（能量 1.2，衰减二次）；光圈外敌人仍可见剪影（modulate 0.4 下限，公平性）；冰面 = 玩家 `move_speed` 摩擦系数 ×0.25（进入冰面区域时 MoveMath friction 参数临时替换，离开恢复）、敌人不受冰面影响；两者均可被 A2 模板 `hazards`/`biome` 字段驱动（data/rooms/a1_templates.json 的 A2 对应表后续卡提供 biome 字段）。
- [ ] TDD：暗视野组件纯参数（modulate 值/光半径/剪影下限）单测；冰面摩擦替换进出恢复断言（注入帧驱动 player velocity 序列）。场景手动验证清单：光圈跟随、冰面打滑手感、性能（CanvasModulate 全屏成本，帧率 ≥58）。
- [ ] Commit `feat(m2-t4): a2 dark vision + ice floor biome`。

### Task 5: 音频管理器 + sfx 全套接线

**Files:** Create `autoload/audio_mgr.gd`；Modify `project.godot`(autoload)、`core/player/weapon_rig.gd`(开火 1 行)、`core/enemies/enemy_base.gd`(开火 1 行)、`core/player/melee.gd`(1 行)、`core/rooms/pickup.gd`(1 行)、`ui/*.gd`(按钮音可选)
**规格：** audio_mgr 持 AudioStreamPlayer 池（sfx 8 语音 / music 2 通道）；`play(key: String, pitch_scale := 1.0)`；音源表 = audio/generated/sfx/*.wav（12 个既有 WAV）；接线点：player 开火→shoot_player、enemy 开火→shoot_enemy、melee 挥击→melee_swing、命中→hit_enemy、暴击→crit_hit(pitch 1.15)、拾取→pickup_*、死亡→death。`set_music_volume/get` 接 SaveSystem.settings（M3 补 UI）。不做 music（T23）。
- [ ] TDD：play 池复用（8 语音轮转断言）、未知 key push_warning 不崩、音量设置持久化读取。接线点手动验证清单（每处触发 1 次听音）。
- [ ] Commit `feat(m2-t5): audio manager with sfx wiring`。

### Task 6: C 数据-1 武器扩至 115

**Files:** Modify `data/weapons.json`、`tests/unit/test_weapons_pool.gd`
**规格：** 附录 A 全量 115 把逐字转录（schema v2 全键；新类别 rifle/shotgun/smg/laser/staff 等按附录 category 字段；紫/橙按解锁规则默认锁定标记 `locked:true` 可选键——GameDB 载入时跳过进掉落池但仍可图鉴展示）；断言：总数 115、稀有度分布逐档（白 13/绿 30/蓝 32/紫 25/橙 15——按附录 A 实际清点）、4 元素覆盖、id 唯一、逐行 validate、掉落池排除 locked。
- [ ] TDD（数据卡：RED=计数不足）→ 全量绿 → Commit `feat(m2-t6): full 115 weapon pool per appendix a`。

### Task 7: A2 地刺 + 晶柱折射 + A1 危险地块补全

**Files:** Create `core/rooms/hazard_spikes.gd`（周期地刺）、`core/enemies/enemy_laser.gd`（敌方直线激光束组件，供晶柱折射与 A2 岩晶炮台）；Modify `core/rooms/floor_scene.gd`（危险地块实例化读取模板 hazards 字段——藤蔓减速/滚石）、`data/enemies.json`（+rock_crystal_turret/prism_ranger/ice_spider/crystal_rat/magnet_golem 等 A2 行，按附录 B.2 数值）
**规格：** 地刺 = 周期 90t 伸出（预警 24t 地面红纹）伤 4，缩回 60t；晶柱折射 = 敌方激光命中 prop_crystal_pillar → 按 45° 反射再飞（最多 1 次折射，防无限）；藤蔓减速带（A-1 的 vine 数据 → 玩家进入减速 40%，已由 T4 冰面组件复用同一 SlowZone 基类则复用）；滚石 = 从房间一侧直线滚动（预警线 0.5s、速度 200、伤 6、撞墙消失）。
- [ ] TDD：地刺周期边界/伤害窗；折射方向计算（入射 45° 案例）；滚石生命周期；A2 新敌人行 schema+行为抽样。手动：折射在实战可见。
- [ ] Commit `feat(m2-t7): a2 spikes, prism refraction, a1 hazards, a2 enemies`。

### Task 8: B-1 召唤物框架 + 工程师

**Files:** Create `core/summons/summon_base.gd`（SummonBase：`setup(row)`, 生命/存活计时, 索敌用 RunState 玩家引用注入, `combat` 注入）、`core/summons/turret.gd`（工程师炮台：12s 存活、索敌射速 2/s、伤 4、升级版 +3s 导弹）；Modify `data/heroes.json`（+engineer 行：hp7/盾5/蓝120/速78/初始[maodingqiang]/skill turret/召唤物数上限 2）；Modify `ui/hero_select.gd`（heroes 列表自动扩展——已按 GameDB 驱动则零改动，验证即可）
**契约：** SummonBase 挂 RoomCombat 的 combat 引用；死亡/超时走 `queue_free` + 统计；索敌 = 240px 最近敌人（复用 AutoAim.pick_target）。
- [ ] TDD：炮台部署/索敌开火（注入帧）/超时自毁/上限 2。
- [ ] Commit `feat(m2-t8): summon framework + engineer turret`。

### Task 9: C 数据-2 敌人补齐 40

**Files:** Modify `data/enemies.json`（+12 行 A2/A3 剩余敌人，附录 B.2 全量）；Modify `tests/unit/test_enemy_ai.gd`（追加新敌人行为抽样）
**规格：** 按附录 B.2 转录剩余 12 种（A2/A3 特有种——已交付 28 种中含 A2 部分，核对补缺至总数 40）；**含小 Boss 池补齐 ×4**（石盾武僧 stone_shield_monk / 亡灵枪手 undead_gunner / 电磁蛛 volt_spider / 腐沼巨蟾 marsh_toad——data 行 + 专属 archetype 脚本，附录 B.3 数值）；每种若有新 archetype 补预载映射；弹速 ≤150、windup ≥24t 契约复查。
- [ ] TDD：总数 40、新行 schema/行为抽样（暗视野下可辨剪影——剪影校验脚本可选）。
- [ ] Commit `feat(m2-t9): complete 40-enemy roster`。

### Task 10: A3 生态机制

**Files:** Create `core/rooms/hazard_magma.gd`（岩浆 DOT 区/间歇喷口/火雨三组件或单文件分区）；Modify `data/rooms/`（A3 模板占位，同 T4 模式）；`tests/unit/test_biome_a3.gd`
**规格（GDD §10 A3）：** 岩浆区 = 站立 2/s DOT（抗火增益减半，读抗性 meta）；间歇喷口 = 周期 180t 预警 36t 后喷发伤 8；火雨 = Boss/事件驱动全屏红圈落点（预警 48t）。
- [ ] TDD：三组件周期/伤害/抗性减半断言（注入帧）。**Commit** `feat(m2-t10): a3 magma biome mechanics`。

### Task 11: B-2 法师 + 守护者技能

**Files:** Create `core/player/skills/arcane_nova.gd`（奥术新星：120px 冰霜新星 24 伤+冻结 1.2s，CD 10s 耗蓝 20）、`core/player/skills/life_tide.gd`（生命潮汐：治疗法阵 3s 每秒 0.5，CD 14s 耗蓝 30）；Modify `data/heroes.json`（+mage/guardian 两行）
**契约：** 与 T8 SummonBase 同款技能框架（SkillBase 子类）；nova 的冻结复用 status_component 的 freeze 语义（读 status_component 现有冻结接口，若无则新增 `apply_freeze(ticks)` 并列消费方）。
- [ ] TDD：新星半径/冻结时长/蓝耗；法阵治疗总量与周期；升级版参数（+40% 半径/+0.5 heal）。
- [ ] Commit `feat(m2-t11): mage nova + guardian life tide`。

### Task 12: C 数据-3 增益 +21 → 36

**Files:** Modify `data/buffs.json`、`core/meta/buff_manager.gd`（新增聚合键：`haggle_pct, heart_sense_pct, pickup_radius_pct, phoenix_flag, anti_fire/ice/poison, element_vision, vengeance_pct, wealth_pct…`——按附录 C 全量键位对齐）、`tests/unit/test_buffs.gd`（追加）
**规格：** 附录 C 剩余 21 条逐一转录（含 M1 已有 16 条的修正）；新聚合键在 apply_to_player/apply_to_rig 落地并注明消费卡。
- [ ] TDD：36 条计数、稀有度分布（按附录 C 实际：白14/绿12/蓝10 修正后口径）、新键 apply 断言。**Commit** `feat(m2-t12): complete 36 buffs`。

### Task 13: B-3 刺客 + 守护者数据 + 选角扩展

**Files:** Modify `data/heroes.json`（+assassin/guardian 行，附录参数）、`ui/hero_select.gd`（若无自动扩展则补）
**规格：** 刺客（hp6/盾3/蓝100/速84/影袭已存在→挂 ranger_shadowstep？否——刺客技能为影袭变体：`shadowstep_assassin` 沿用 ranger 脚本 + heroes 行参数差异化）；守护者（hp7/盾6/蓝130/速80/生命潮汐）。选角 UI 自动扩展验证（GameDB 驱动则零改动）。
- [ ] TDD：新行 schema/applier 全字段落地。**Commit** `feat(m2-t13): assassin + guardian heroes`。

### Task 14: D-1 宝石蜂后 + 晶棱魔像

**Files:** Create `core/enemies/bosses/gem_queen.gd`、`core/enemies/bosses/prism_golem.gd`；Modify `data/enemies.json`（+2 Boss 行，附录 E 参数）；Create `tests/unit/test_boss_m2_wave1.gd`
**规格（附录 E）：** 蜂后 P1 扇形蜂群弹（8 发×3 轮）/俯冲；P2 蜂巢柱（可破坏掩体 2 根）+环形爆蜂 16 发留缺口；P3 狂暴三连冲（末段撞墙自晕 1.2s）。晶棱魔像：棱镜射线（命中晶柱 45° 折射，复用 T7 折射组件）+三向扫描+晶柱再生+瞬移弹幕。HP 按附录 E 表（800/1800 换算）。
- [ ] TDD（注入帧）：阶段招式门控/弹环计数/折射方向/狂暴连段/晶柱再生。手动：战斗时长 90~150s。
- [ ] Commit `feat(m2-t14): gem queen + prism golem bosses`。

### Task 15: E-1 天赋树系统落地

**Files:** Create `core/meta/talent_system.gd`、`ui/talents.gd(+tscn)`；Modify `tests/unit/test_talent_system.gd`
**规格：** 读 data/talents.json（T2 表）；`available()`（前置满足+未购）；`buy(id)`（蓝晶校验→SaveSystem 扣除→持久化 purchased 列表）；`apply_to_player(player)`（购得节点效果全量落地，键 = T2 effects 白名单）；UI = 三系树状排布+购买按钮+蓝晶余额。
- [ ] TDD：前置门控/蓝晶扣减/效果落地/重复购买拒绝/持久化往返。UI 手动。**Commit** `feat(m2-t15): talent tree system`。

### Task 16: D-2 寒渊蛛母

**Files:** Create `core/enemies/bosses/frost_widow.gd`；Modify `data/enemies.json`；`tests/unit/test_boss_m2_wave2.gd`
**规格（附录 E）：** P1 铺冰面（40% 房间冰面化，复用 T4 冰面组件）+蛛网禁锢（落点 0.4s 后禁锢 1s，可打断）；P2 螺旋弹幕（双臂螺旋 4s）+召唤冰蛛×3；P3 冰晶牢笼（玩家周围 8 根冰柱留 1 缺口）+全屏冰刺阵（缝隙安全线）。HP 1800。
- [ ] TDD：阶段招式/蛛网禁锢打断/螺旋弹幕计数/牢笼缺口。**Commit** `feat(m2-t16): frost widow boss`。

### Task 17: I-1 英雄行走帧

**Files:** Modify `tools/gen_placeholder_art.py`（hero 四向×idle/walk 2~4 帧生成）、`art/generated/characters/**`、`core/player/player.tscn`（AnimatedSprite2D 或帧动画切换）
**规格：** 6 英雄 ×4 向 ×(idle 1 + walk 3) 帧；接 player 移动方向自动切换动画；受击帧沿用白闪不变。
- [ ] 验证：生成器重跑确定性（seed 42 逐字节一致）；游戏内行走动画视觉确认（截图）。测试：帧表完整性断言（生成 MANIFEST 比对）。**Commit** `feat(m2-t17): hero walk animation frames`。

### Task 18: F-1 胜利结算完整

**Files:** Create `ui/victory_summary.tscn(+gd)`；Modify `core/rooms/inter_floor_flow.gd`（victory 桩→真实触发信号 `victory_achieved`）、`core/rooms/run_root.gd`（接信号→切胜利场景）
**规格：** 全屏中文胜利面板：通关统计（RunState 全量+Telemetry.session_summary+总时长）+ 蓝晶全额入账 + 「M2 将开放第 3 层」预告 + 任意键回主菜单。
- [ ] TDD：触发链（floor3 boss 死→victory_achieved）+统计字段。UI 手动。**Commit** `feat(m2-t18): victory summary`。

### Task 19: D-3 熔核暴君

**Files:** Create `core/enemies/bosses/magma_tyrant.gd`；Modify `data/enemies.json`；`tests/unit/test_boss_m2_wave3.gd`
**规格（附录 E）：** P1 岩浆喷发（4 块区 5s）+火拳；P2 火雨 12 红圈×3 波+怒气（弹幕密度 ×1.5 移速+20%）；P3 地裂火浪（环形火浪可被掩体挡）。HP 3200。
- [ ] TDD：阶段/火浪环形扩散/怒气倍率/掩体遮挡。**Commit** `feat(m2-t19): magma tyrant boss`。

### Task 20: E-2 图鉴 + 解锁引擎

**Files:** Create `core/meta/codex_system.gd`、`ui/codex.tscn(+gd)`；Modify `tests/unit/test_codex.gd`
**规格：** 读 data/unlock_tasks.json（T3 表）；`progress(task_id) -> {cur, goal}`（从 RunState/Telemetry 取数）；解锁达成→SaveSystem.unlocked + 武器进掉落池（GameDB 载入时按 unlocked 过滤 locked——读 T6 的 locked 键）；UI = 115 格图鉴墙（已解锁亮/未解锁灰+条件文案）。
- [ ] TDD：进度判定各类条件（kill_x/craft_x/resonate_x…）；解锁后掉落池过滤；未解锁不掉落。UI 手动。**Commit** `feat(m2-t20): codex + unlock engine`。

### Task 21: I-2 敌人 2 帧动画

**Files:** Modify `tools/gen_placeholder_art.py`（敌人 idle/walk 各 1 帧，40 种）、`art/generated/enemies/**`、`core/rooms/room_combat.gd`（enemy Sprite → AnimatedSprite2D 或帧切换）
**规格：** 同 T17 模式；移动中播放 walk 帧、静止 idle；帧表 MANIFEST 同步。
- [ ] 生成器确定性复跑 + 游戏内视觉确认 + MANIFEST 断言测试。**Commit** `feat(m2-t21): enemy 2-frame animation`。

### Task 22: G-2 音乐 5 曲 + Boss 动态切层

**Files:** Modify `tools/`（musicgen 脚本或 gen_placeholder_sfx.py 扩展）、`audio/generated/music/**`、`autoload/audio_mgr.gd`（`play_music(key)` + Boss 层淡入淡出）
**规格：** 菜单 1 + 生态 3 + Boss 1（程序化芯片风，2 分钟无缝循环，seed 可复现）；Boss 战进入→Boss 曲淡入 0.5s、结束→生态曲恢复。
- [ ] 手动听音验证清单 + 曲目文件存在断言 + 切层时序测试（模拟 boss_phase 信号）。**Commit** `feat(m2-t22): 5 music tracks + boss layer switch`。

### Task 23: F-2 死亡回顾完整

**Files:** Modify `core/meta/death_recorder.gd`、`ui/death_summary.gd`；`tests/unit/test_death_recorder.gd`（追加）
**规格：** 致死 3s 高亮回放 = 确定性重放（§18.2 种子化架构）：死亡时记录 `run_seed+floor+死亡帧号`，回放 = 以同参数重建 FloorScene 快速前进至死亡帧（GDD §19）；+ 最高 DPS 采样（Telemetry 每 60t 采样瞬时 DPS 窗口峰值，终审移交项）。
- [ ] TDD：回放参数记录/重放一致性（同种子同帧同怪位置断言）/DPS 峰值窗口。**Commit** `feat(m2-t23): death replay + dps sampling`。

### Task 24: D-4 星陨先知 + 隐藏门

**Files:** Create `core/enemies/bosses/starfall_prophet.gd`；Modify `core/rooms/floor_scene.gd`（隐藏门：携带任意共鸣状态击杀 A3 小 Boss → 开启星陨门）、`data/enemies.json`
**规格（附录 E）：** P1 元素轮回弹幕（火环/冰针/毒云/电链四轮）+星陨 3 颗追踪（可近战反弹）；P2 单元素领域 8s+共鸣斩（对已有异常玩家强制附加第二状态）；P3 星河滚筒弹幕墙×3 波（缺口口罩间）。HP 3200。
- [ ] TDD：轮回序列/领域切换/共鸣斩强制附加/滚筒缺口。**Commit** `feat(m2-t24): starfall prophet + hidden gate`。

### Task 25: E-4 蓝晶结算 + 存档 migration v2

**Files:** Modify `autoload/save_system.gd`（SAVE_VERSION=2：+unlock_tasks 进度/purchased_talents/成就字段迁移）、`tests/unit/test_save.gd`（追加）
**规格：** v1→v2 migration（旧档 gems/unlocked_heroes 保留，新增字段默认）；migration 幂等；蓝图鉴进度字段与 T20 对接。
- [ ] TDD：v1 档载入→自动迁移→字段完整；二次载入不重复迁移。**Commit** `feat(m2-t25): save migration v2`。

### Task 26: C-5 A2/A3 房间模板 ×16

**Files:** Modify `data/rooms/`（+a2_templates.json ×8 + a3_templates.json ×8，含 biome 字段与 A2/A3 危险地块）；`tests/unit/test_room_templates.gd`（追加 A2/A3 断言）
**规格：** 每生态 8 战斗模板（布局差异化原则同 T4）+ 各 1 起始/Boss 模板（4 门完备）；validate_room_row 全过；A2 含冰面/地刺/晶柱、A3 含岩浆/喷口字段。
- [ ] TDD：16 模板计数+schema+危险字段抽检。**Commit** `feat(m2-t26): a2/a3 room templates`。

### Task 27: H-1 Balance Bot 全层回归

**Files:** Create `tools/balance_bot.gd`（无头自动游玩：启发式走位+索敌开火+翻滚概率+买药+三选一贪心）、`tests/scenes/`；产出 `docs/superpowers/reports/m2-balance-<date>.md`
**规格：** 基于 m1_loop_smoke 模式扩展：随机种子 ×10 局全 3 层自动游玩，统计胜率/死亡热房/TTK/时长 → 对照 GDD §14.3 带值出报告。挂 tools/run_balance.cmd。
- [ ] 验收：10 局无崩溃全走完 + 报告产出 + 胜率带（目标 20~40% 区间首次校准）。**Commit** `feat(m2-t27): balance bot full-floor regression`。

### Task 28: I-3 A2/A3 瓦片接线验证 + 元素弹阵营分化

**Files:** Modify `core/art/art_lookup.gd`（A2/A3 地板/墙/门按 floor_idx 映射 crystal/magma 套）、`art/generated/projectiles/`（元素弹玩家/敌方各一套，阵营分化——终审移交项）
**规格：** floor_idx→生态映射表驱动（1=cave/garden, 2=crystal, 3=magma）；元素弹敌方加暗边框区分。
- [ ] 断言：映射表全键覆盖 + 贴图存在；游戏内三层切换视觉截图。**Commit** `feat(m2-t28): biome tile mapping + element bullet split`。

### Task 29: H-2 §18.3 全指标压测

**Files:** Create `tests/scenes/perf_probe.gd`、`docs/superpowers/reports/m2-perf.md`
**规格：** 压测场景：3 层各最密房间 + 500 弹 + 40 敌人 + 全特效，采样 帧耗时（逻辑 ≤6ms/渲染 ≤10ms）、实体数、draw call（`RenderingServer.get_frame_setup_time` + 性能监视器）；产出报告对照 §18.3 预算表逐项 PASS/FAIL。
- [ ] 验收：开发机 60fps 全达标；超标走风险预案（降粒子→降实体→上报）。**Commit** `feat(m2-t29): perf probe + budget report`。

### Task 30: F-3 挑战房灾厄收口 + 房型复核

**Files:** Modify `core/rooms/floor_scene.gd`（挑战房灾厄选择 UI + 3 波强化 + 必得紫奖励）、`tests/unit/test_floor_scene.gd`（追加）
**规格：** 灾厄 4 选 1（敌速+30%/视野-35%/治疗无效/弹速+25%，仅本房生效）→ 3 波强化怪 → 必得紫武器 + 大量金币；房型接线复核 = 8 房型 ×3 生态矩阵走查表 + 层内去重复核（同模板 ≤2 次/层断言已有则复核触发条件）。
- [ ] TDD：灾厄应用/失效边界/紫奖励必得。手动：矩阵走查 24 组合抽查 6 组。**Commit** `feat(m2-t30): challenge room calamities + room matrix review`。

### Task 31: Windows 导出冒烟 + Android 导出链预通

**Files:** Create `export_presets.cfg`、`tools/export_smoke.cmd`
**规格：** Windows 导出 preset（icon/版本/主场景）→ 导出 exe → 启动冒烟（进主菜单+进局 30s 无错）；Android preset 建立（导出链预通即可，签名/商店配置 M3）；导出产物进 `user_export/`（已 gitignore）。
- [ ] 验收：exe 产出+启动截图；Android 导出命令跑通（允许 keystore 为 debug）。**Commit** `feat(m2-t31): export presets + windows smoke`。

### Task 32: 蓝晶结算 + E-4 存档 migration v2（若 T25 已含 v2 则本卡=结算接线）

**Files:** Modify `core/rooms/inter_floor_flow.gd`（蓝晶结算完整口径：层通过+击杀+首杀奖励）、`tests/unit/test_inter_floor.gd`
**规格：** 层通过 +[60,120,200]（已有）+ 击杀蓝晶（精英 5/小 Boss 20/Boss 50，M2 新增口径——GDD §14 允许）写入 RunState 并在死亡/胜利时经 SaveSystem 入账。
- [ ] TDD：各来源累加/死亡减半入账/胜利全额。**Commit** `feat(m2-t32): gem settlement completion`。

### Task 33: 成就系统（22 激活）

**Files:** Create `core/meta/achievement_system.gd`、`ui/toast.gd(+tscn)`；Modify `tests/unit/test_achievements.gd`
**规格：** 读 T3 接线表 22 条 M2 激活成就：信号/数据源→判定→SaveSystem.unlocked_achievements→右下 toast（中文「成就解锁：xxx」+蓝晶数）。与 T20 图鉴共享解锁引擎的计数源。
- [ ] TDD：5 类代表成就判定（击杀类/通过类/收集类/熔铸类/无伤类）+ toast 信号 + 持久化。**Commit** `feat(m2-t33): achievement system (22 active)`。

### Task 34: M2 门禁

**Files:** Create `docs/superpowers/reports/m2-gate-integration.md`、`m2-gate-playtest.md`、`m2-gate.md`
**规格：** 集成守卫（全量绿+启动+3000 种子×3 生态+§18.3 压测报告对照+存档 v2 往返+卫生）+ 试玩员（真人鼠标**完整 3 层通关**：三层 Boss 各三阶段+全部房型+三选一+熔铸实操作+图鉴/成就触发抽查+主观评分）+ 编排者裁定 → GREEN 则 tag `m2`。
- [ ] 双报告 + 裁定 + tag。

---

## 附：M1 终审 MUST-FIX 闭环核对表（T1 已含①③，其余随卡）

| 终审项 | 承接卡 |
|---|---|
| ArtLookup 逐帧字符串分配 | T1 ✅ |
| SALT_LOOT 重派生 | T1 ✅ |
| testgun 夹具泄漏 | T1 ✅ |
| 真人试玩（Boss 三阶段+商店实买+三选一生效确认） | T34 门禁试玩员第 1 项 |
| scratch 产物/.gitattributes | 已完成（82ab73c 前置提交） |
| ShopLogic 过期注释 | 已完成 ✅ |
