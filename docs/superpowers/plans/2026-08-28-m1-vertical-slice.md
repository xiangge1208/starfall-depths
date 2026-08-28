# M1 垂直切片（A1 完整一局）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task, organized by the Wave table below (parallel dispatch per §2.1 of the roadmap). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 A1「翠绿遗迹」完整一局：种子化地牢生成（1000 种子校验）、8 种房型+全设施、骑士+游侠全技能、武器 40+增益 15、藤蔓巨像+2 小 Boss、层间三选一、死亡结算+回顾 v1、存档桩——新玩家 30 分钟完整体验并想开第 2 局。

**Architecture:** 延续 M0 的数据驱动 + 60Hz 逻辑帧 + autoload 服务架构；新增 DungeonGraph（纯逻辑图生成→校验→装配）、SkillBase 技能框架、BuffManager 局内增益聚合器、RunState 局状态 autoload、BossBase 三阶段框架。场景卡以「节点树+wiring 规格+验收清单」为准（M0 经验：行为规格+测试规格优于逐行参考代码）。

**Tech Stack:** Godot 4.7.2 / GDScript / GdUnit4 6.2.1（沿用，勿升级）。

## Global Constraints（每卡隐含继承）

- 沿用 M0 全部约束：逻辑固定 60Hz（`TimeConst.ticks`）、伤害固定值+暴击唯一随机、逻辑随机只经 `RngSvc.stream(idx, salt)`、弹幕/粒子池化、场景零硬编码玩法数值、480×270 nearest、代码英文/文案中文、conventional commits 带卡号（`feat(m1-t7)`）。
- **数值唯一出处**：GDD 附录（`docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md`）——武器附录 A、敌人附录 B、增益附录 C、Boss 招式附录 E、经济附录 H。实现者发现表内矛盾 → 停止上报编排者，不得自行改表。
- **M1 新增（M0 终审裁定，必须遵守）**：①`RngSvc.setup_run` 必须在开局由 RunState 调用（种子链激活）；②RNG 流分盐常量定义在 RunState：`SALT_PROJECTILE="proj_crit"`、`SALT_RIG="rig"`、`SALT_LOOT="loot"`、`SALT_DUNGEON="dungeon"`（替换 M0 的双 `"combat"` 共seed）；③敌弹单独上限 400（GDD §7.5），池总上限 500 不变——CombatSystem.spawn_projectile 按 faction 检查；④房间配置 JSON 必须走 GameDB schema 校验（fail-closed）；⑤EnemyBase 原型挂载改 preload 映射（弃 set_script）。
- **并行纪律**：每波 ≤3 实现者；同波文件所有权互不相交；评审与下一波派发并行；合并后必须 `godot --headless --path . --import` 再跑测试（新 class_name 注册）。

## 波次与依赖总表

| Wave | 卡 | 依赖 | 文件所有权（独占） |
|---|---|---|---|
| W1 | T1 地牢图生成 | — | core/dungeon/dungeon_graph.gd, tests/unit/test_dungeon_graph.gd |
| W1 | T2 技能框架+骑士 | — | core/player/skills/**, core/player/player.tscn(挂1技能节点), core/player/player.gd(rampage字段+盾破emit), core/player/weapon_rig.gd(dual_wield字段+life/radius/muzzle读表), core/combat/combat_system.gd(仅加 player_crit_landed 转发), autoload/event_bus.gd(加2信号), tests/unit/test_skills.gd |
| W1 | T3 武器 schema v2+清理 | — | data/weapons.json, autoload/game_db.gd, tests/unit/test_game_db.gd |
| W2 | T4 房间模板库 | T3 | data/rooms/a1_*.json, core/dungeon/room_template.gd, autoload/game_db.gd, tests/unit/test_room_templates.gd |
| W2 | T5 游侠影袭 | T2 | core/player/skills/ranger_shadowstep.gd, tests/unit/test_skills.gd(追加) |
| W2 | T6 交互系统 | — | core/interact/**, core/rooms/training_room.tscn(武器架E化+木桩无碰撞), core/enemies/archetypes/dummy.gd, tests/unit/test_interaction.gd |
| W3 | T7 地牢装配+校验 | T1,T4 | core/dungeon/dungeon_builder.gd, tools/validate_dungeon.gd, tests/unit/test_dungeon_builder.gd |
| W3 | T8 BossBase | — | core/enemies/boss_base.gd, tests/unit/test_boss_base.gd |
| W3 | T9 增益系统 | — | data/buffs.json, core/meta/buff_manager.gd, ui/buff_pick.tscn(+gd), tests/unit/test_buffs.gd |
| W4 | T10 楼层场景流 | T7 | core/rooms/floor_scene.gd(+tscn), tests/unit/test_floor_scene.gd |
| W4 | T11 heroes+选角 | T2,T5 | data/heroes.json, ui/hero_select.tscn(+gd), tests/unit/test_heroes.gd |
| W4 | T12 小Boss×2+词缀+原型映射 | — | core/enemies/elites/**, core/enemies/enemy_base.gd(原型映射改造+fire_bullet radius读表), data/enemies.json, tests/unit/test_elites.gd |
| W5 | T13 藤蔓巨像 | T8 | core/enemies/bosses/vine_colossus.gd, data/enemies.json(boss行), tests/unit/test_vine_colossus.gd |
| W5 | T14 商店+黑商+回收 | T6 | core/interact/shop.gd, core/meta/shop_logic.gd(纯函数), tests/unit/test_shop.gd |
| W5 | T15 RunState | — | autoload/run_state.gd, autoload/project.godot(注册), tests/unit/test_run_state.gd |
| W6 | T16 雕像+饮料机 | T6,T9 | core/interact/shrine.gd, core/interact/drink_machine.gd, data/drinks.json, tests/unit/test_facilities.gd |
| W6 | T17 存档桩 | T15 | autoload/save_system.gd, tests/unit/test_save.gd |
| W6 | T18 Juice v1.5+遥测集中化 | — | fx/**, core/meta/telemetry.gd, autoload/event_bus.gd(enemy_damaged 启用), core/combat/combat_system.gd(敌弹400上限+emit enemy_damaged), tests/unit/test_telemetry.gd(追加) |
| W7 | T19 事件房 | T6 | core/interact/events.gd, tests/unit/test_events.gd |
| W7 | T20 层间流程 | T9,T15 | core/rooms/inter_floor.gd(+tscn), tests/unit/test_inter_floor.gd |
| W7 | T21 三端输入 | T11 | ui/virtual_joystick.gd(+tscn), core/player/auto_aim.gd, project.godot(inputmap), tests/unit/test_auto_aim.gd |
| W8 | T22 死亡结算+回顾 | T15,T18 | ui/death_summary.tscn(+gd), core/meta/death_recorder.gd, tests/unit/test_death_recorder.gd |
| W8 | T23 主菜单+路由 | T11,T15 | ui/main_menu.tscn(+gd), autoload/scene_router.gd, tests/unit/test_scene_router.gd |
| W8 | T24 HUD 完整 | T15 | ui/hud.gd(+tscn 扩展), tests/unit/test_hud.gd |
| W9 | T25 武器扩至 40 | T3 | data/weapons.json, tests/unit/test_weapons_pool.gd |
| W9 | T26 M1 门禁 | 全部 | docs/superpowers/reports/m1-gate-*.md |

---

### Task 1: DungeonGraph 地牢图生成（纯逻辑）

**Files:** Create `core/dungeon/dungeon_graph.gd`、`tests/unit/test_dungeon_graph.gd`
**Interfaces (Produces):** `class_name DungeonGraph`；`static func generate(rng: RandomNumberGenerator, floor_idx: int = 1) -> Dictionary` 返回 `{"nodes": Dictionary(id→{id:int,type:String,grid:Vector2i,depth:int,next:Array[int]}), "start_id": int, "boss_id": int}`；`static func validate(graph: Dictionary) -> Array[String]`（空数组=通过）。节点类型常量 `const TYPES := ["start","combat","elite","shop","treasure","event","miniboss","boss"]`。

- [ ] **Step 1 失败测试**（先写，断言以下全部）：
  - `generate` 用注入 rng：12 节点、start 恰 1 个 grid=(0,0)、boss 恰 1 个且为全图 depth 最大者、类型计数 = start1/boss1/miniboss1/shop1/treasure1/event1/elite1/combat6、`validate(g) == []`。
  - 结构规则：全图从 start 沿 next 可达（BFS）；无环（沿 next 走不回访）；相邻节点 grid 曼哈顿距离 == 1（房间贴邻，走廊一格）；miniboss 在 start→boss 最短路径上且 depth == boss.depth-1；shop 在主路径上且 2 ≤ depth ≤ boss.depth-2；treasure 与 event 是非主路径叶子（next 为空）。
  - 确定性：同 rng seed 两次 generate 产生完全相同的图（逐字段比较）。
  - 生成算法（实现规格）：主路径先行为主——从 (0,0) 沿随机方向链走 miniboss→boss（boss 深度 = 主路径长，取 7~9）；主路径中段放 shop、depth≥ max(2, boss深度-4) 的主路径节点挂 elite；剩余节点作为 combat 链从主路径随机节点侧向生长；treasure/event 挂在 combat 叶子上；grid 冲突（重叠/非邻接）时换向重试，整体失败重掷（rng 消耗无所谓，确定性由 seed 保证）。
- [ ] **Step 2** `tools/run_tests.cmd` 确认 RED。**Step 3** 实现。**Step 4** GREEN（全套件绿）。
- [ ] **Step 5** Commit `feat(m1-t1): dungeon graph generator with structural validation`。

### Task 2: 技能框架 + 骑士「狂潮」

**Files:** Create `core/player/skills/skill_base.gd`、`core/player/skills/vanguard_rampage.gd`、`tests/unit/test_skills.gd`；Modify `core/player/player.tscn`（挂一个 `Skill` 节点，脚本由角色数据注入——见 T11）、`core/combat/combat_system.gd`（仅：暴击命中玩家武器时 emit 新信号 `player_crit_landed`）、`core/player/weapon_rig.gd`（仅：`dual_wield_until:int = -1` 字段+try_fire 时若 `frame < dual_wield_until` 同时对副手 `_spawn` 镜像弹且跳过两武器蓝耗）、`core/player/player.gd`（仅：护盾破碎时机 emit——在 take_hit_ctx 中当 `shield 之前>0 且现在==0` 时 emit 既有 `EventBus.player_damaged`? 否——新信号挂 EventBus? 用 `EventBus.shield_broken` 新信号）、`autoload/event_bus.gd`（加 `signal shield_broken`、`signal player_crit_landed`）。
**Interfaces (Produces):** `class_name SkillBase extends Node`：`setup(player: Player, data: Dictionary)`、`can_cast(frame: int) -> bool`、`cast(frame: int) -> bool`、`tick(frame: int)`（子类按需）、`cooldown_ticks: int`、`energy_cost: int`、`cooldown_remaining(frame: int) -> int`（HUD 用）。`class_name VanguardRampage extends SkillBase`：data 可带 `"upgraded": bool`。
**行为规格（GDD §6）：** 狂潮 CD 840t（14s）、持续 480t（8s）：cast 成功 → `player.weapon_rig.dual_wield_until = frame + 480`；期间 try_fire 双武器免蓝。升级版：期间玩家受伤 -30%（player.take_hit_ctx 里查询 `player.rampage_active_until > frame`，字段由技能写在 player 上）。被动「坚守」（挂 player）：EventBus.shield_broken 时对 60px 内敌人 1 伤+击退 8px+眩晕 30t（眩晕：EnemyBase 增加 `stun_until:int`，brain_tick 顶部 `if frame < stun_until: return`）。
- [ ] TDD：测试断言（注入帧）：can_cast 受 CD/耗蓝门控；cast 后 dual_wield_until==frame+480；CD 期间 cast false；cooldown_remaining 边界；盾破→EventBus.shield_broken 发出（用 Player.take_hit_ctx 打空盾验证）；坚守对 60px 外敌人无效。蓝耗跳过用 RigProbe 模式（沿用 tests/unit/test_weapon_rig.gd 的覆写手法）。
- [ ] RED→实现→GREEN→Commit `feat(m1-t2): skill framework + vanguard rampage dual wield`。

### Task 3: 武器 schema v2 + GameDB 清理（M0 终审 handover）

**Files:** Modify `data/weapons.json`、`autoload/game_db.gd`、`tests/unit/test_game_db.gd`、`tests/unit/test_weapon_rig.gd`（本卡不碰 weapon_rig.gd/enemy_base.gd——读表改造归 T2/T12，见各卡）
**规格：** ①WEAPON_SCHEMA 增加必填 `bullet_life: TYPE_FLOAT`、`bullet_radius: TYPE_FLOAT`、`muzzle: TYPE_FLOAT`（枪口偏移 px；近战为 0）；现有 6 行补齐（远程 1.2/3.0/8，近战 0/0/0）；**读表改造分工：weapon_rig.gd（life/radius/muzzle 读行）由 T2 顺带完成，enemy_base.fire_bullet 的 radius 读行由 T12 完成**。②删除测试注入的 `testgun/testgun3` 夹具后必须清理：test_weapon_rig.gd 每个用例结束 `GameDB.weapons.erase("testgun")` 等（用 GdUnit 的 after_test 钩子或 finally）。③补 loader 覆盖缺口测试：缺文件（不存在路径→空+load_ok false）、坏 JSON（"{"）、id 不匹配行、可选默认填充（新行省略可选键→默认值生效）、小数入整型字段被拒（2.5 → validate 报错）。④`Elements.from_name` 与 `Resonance.resolve` NONE 路径补测（新增 test_elements.gd：from_name("fire")==FIRE、未知串→NONE、resolve(NONE,x)==NONE）。
- [ ] TDD 逐项 RED→GREEN。**Commit** `feat(m1-t3): weapon schema v2, fixture cleanup, loader coverage`。

### Task 4: 房间模板库 + rooms 加载

**Files:** Create `data/rooms/a1_templates.json`、`core/dungeon/room_template.gd`、`tests/unit/test_room_templates.gd`；Modify `autoload/game_db.gd`（rooms 表加载，复用 _load_table）。
**规格：** 模板行 schema：`{id, size:[22,14], doors:[N/S/E/W 子集], spawn_points:[[x,y]...], props:[{kind:"pillar"|"crate"|"bush", grid:[x,y], hp:int}...], hazards:[{kind:"vine", grid, radius}]}`。8 个 A1 战斗房模板（手写布局，风格：中央掩体/四角柱/横墙分割/灌木丛等，符合 GDD §9.2 修饰规则）+ 1 起始房（无敌人，安全区）+ 1 Boss 房（空旷+两侧柱）。校验：spawn 点距任一门 ≥64px；doors 1~4 个；props 不堵门。`RoomTemplate.get(id) -> Dictionary`。数量校验测试：combat 模板 ≥8。
- [ ] TDD：schema 校验失败样例（spawn 距门 <64px 的坏行被拒）+ 8 模板全过 + 属性读取。**Commit** `feat(m1-t4): a1 room templates with schema validation`。

### Task 5: 游侠「影袭」+「鹰眼」

**Files:** Create `core/player/skills/ranger_shadowstep.gd`；Modify `tests/unit/test_skills.gd`（追加）。
**规格（GDD §6）：** 影袭 CD 540t（9s）：瞬步 140px（沿 aim 方向，位移分 1 帧完成+iframes 15t——复用 player 的 `_iframe_until`），后 240t（4s）内射击必暴+弹速 +20%（rig 增加 `crit_boost_until`/`speed_boost_until` 字段，try_fire 时 crit_chance 覆盖 1.0、bullet_speed ×1.2——实现于 rig 的 angle/speed 计算处）。升级版：瞬步后无敌延至 36t。被动「鹰眼」：角色 crit 基础 0.15（ heroes 注入，见 T11）；暴击落地 50% 返 1 蓝（监听 T2 的 `EventBus.player_crit_landed`）。
- [ ] TDD：瞬步位移/无敌窗/必暴窗边界/返蓝（crit_landed 两次→期望 +1 蓝一次近似——用注入信号直接测监听逻辑）。**Commit** `feat(m1-t5): ranger shadowstep + hawk eye passive`。

### Task 6: InteractionSystem + 武器架 E 化 + 木桩无碰撞

**Files:** Create `core/interact/interactable.gd`（基类 Area2D）、`core/interact/interaction_system.gd`、`ui/interact_prompt.gd`（浮标 Label）；Modify `core/rooms/training_room.tscn`（6 武器架挂 Interactable）、`core/enemies/archetypes/dummy.gd` 与其场景实体（碰撞层改不含玩家，木桩可穿过）。
**规格：** Interactable：`action_label: String`（中文，如"拾取 老伙计"）、`can_interact(player) -> bool`、`interact(player)`；InteractionSystem（房间挂载）：每帧查询玩家 24px 内最近可交互物，显示浮标于其上方（文案=action_label），E 按下→interact。武器架 interact = `player.weapon_rig.equip(id)`。验收：训练房走近武器架出现"拾取 X"浮标，按 E 换枪；木桩不再阻挡走位。
- [ ] 逻辑可测部分：最近可交互物选择（两个重叠范围取近者）、can_interact false 时不显示。TDD 这两点（headless 构造 Area2D 替身）。**Commit** `feat(m1-t6): interaction system, e-key weapon racks, non-solid dummies`。

### Task 7: 地牢装配 + 1000 种子校验

**Files:** Create `core/dungeon/dungeon_builder.gd`、`tools/validate_dungeon.gd`（SceneTree 脚本）、`tests/unit/test_dungeon_builder.gd`
**规格：** `DungeonBuilder.build(seed: int, floor_idx: int) -> Dictionary`：`DungeonGraph.generate` → 每节点从 RoomTemplate 按 type 抽模板（combat 层内去重 ≤2 次）→ 输出 `{"rooms": Dictionary(id→{graph_node, template_id, world_pos: Vector2}), "corridors": [...], "start_room_id", "boss_room_id"}`（world_pos = grid × 房间跨度 26 格）。`validate_build(build) -> Array[String]`：模板 doors 与图邻接方向一致（北邻的房子南门存在等）、spawn/props 合法。`tools/validate_dungeon.gd`：无头跑 1000 种子（seed=floor 种子链派生），全部 build+validate 通过输出 PASS 统计，任一失败列出种子。
- [ ] TDD：3 个种子样本的 build 结构断言 + 门对齐校验（人为错配的图被拒）+ 去重规则（同一 combat 模板 ≤2 次/层）。**Step** 手动跑 `godot --headless --path . --script tools/validate_dungeon.gd` → `1000/1000 PASS`。**Commit** `feat(m1-t7): dungeon builder + 1000-seed validation`。

### Task 8: BossBase 三阶段框架

**Files:** Create `core/enemies/boss_base.gd`、`tests/unit/test_boss_base.gd`
**规格：** `class_name BossBase extends EnemyBase`：行数据含 `"phases":[1.0,0.6,0.3]`（血量线）、`"hp"`；血线跨越→`_on_phase_enter(i)`（子类覆写）前 72t 无敌（`_phase_invuln_until`，take_hit 期间直接 return）+ EventBus 发 `boss_phase(boss, i)`（新信号，HUD/演出用）；脑层契约沿用 brain_tick（子类写 `_engage`，按当前 phase 分支）。`phase() -> int`。
- [ ] TDD：注入帧+直接改 hp：800 血 Boss 打到 481→仍 P0；480→P1 进入（无敌窗内 take_hit 无效）；100→P2；阶段只前进不回退；死亡路径（die）不受影响。**Commit** `feat(m1-t8): boss base with phase gates`。

### Task 9: 增益系统（15 条 + BuffManager + 三选一 UI 桩）

**Files:** Create `data/buffs.json`、`core/meta/buff_manager.gd`、`ui/buff_pick.tscn(+gd)`、`tests/unit/test_buffs.gd`
**规格：** buffs.json 取附录 C 子集 15 条（白 8：火焰/冰霜/毒素/电弧附魔、弹速强化、精准、强健、护盾调谐、蓝能上限；绿 5：迅捷扳机、致命、状态侵蚀、快速充能、翻滚大师；蓝 2：散弹扩张[唯一]、暴虐回响[唯一]）。schema：`{id, name, rarity, desc, effects:{...}}`，effects 键白名单：`move_speed_pct, crit_pct, crit_dmg_pct, atk_speed_pct, bullet_speed_pct, hp_max, shield_max, energy_max, shield_delay_ticks, roll_cd_pct, element_enchant(int Elements.Id), status_rate_pct, extra_projectiles(int,唯一), crit_detonate_pct(唯一)`。`BuffManager`（每局实例，持有已取列表）：`roll_three(rng) -> Array[String]`（从未取池按稀有度权重白55/绿30/蓝15抽 3，唯一抽后移除）、`pick(id)`、聚合 getter `apply_to_player(p)`/`apply_to_rig(rig)`（一次性把数值写上去；附魔类存 `rig.enchant_element`，暴虐回响存 `rig.crit_detonate_pct`）。ui/buff_pick：全屏三卡（名称/稀有度色/描述），点击→pick+关；纯展示桩，接键盘 1/2/3。
- [ ] TDD：roll_three 权重分布 sanity（固定 seed 抽 1000 次，白占比 50~60%）；唯一移除；apply_to_player 数值落地（+2HP 等）；附魔写入 rig。UI 手动验证。**Commit** `feat(m1-t9): buff system with 15 buffs and pick UI`。

### Task 10: 楼层场景流（按图进房）

**Files:** Create `core/rooms/floor_scene.gd`(+tscn)、`tests/unit/test_floor_scene.gd`
**规格：** FloorScene（房间挂载的编排者）：`setup(build, player)`；玩家从 start 房出生；按图邻接放置房间实体（world_pos 来自 build）；门只在与已清空的相邻房间之间开放（未达房间门显示锁形）；进入战斗房→复用 M0 RoomCombat 流程（锁门→波次→奖励）；清空当前房后相邻门开。combat 房敌人波次从模板 spawn_points 生成（wave 数据 = enemies.json 按 floor 预算组合 2 波，每波 3~4 只，floor=1 用 A1 名录）。event/treasure/shop/elite/miniboss 房：本卡只放占位交互（treasure=宝箱武器掉落[用掉落权重白绿蓝]、elite=1 精英词缀怪[T12 后接入]+2 红心、miniboss=强化怪、event/shop 留 C 线接入的空 Interactable 桩）。
- [ ] TDD（纯逻辑部分抽 `FloorFlow` 类）：当前房清空→邻接门状态更新；boss 房门需 miniboss 已清（`boss_door_locked_until_miniboss` 规则，GDD §9.1 主路径）；房序去重。场景手动验证：走通 start→combat×2→清房开门。**Commit** `feat(m1-t10): floor scene flow over generated dungeon`。

### Task 11: heroes.json + 选角界面

**Files:** Create `data/heroes.json`、`ui/hero_select.tscn(+gd)`、`tests/unit/test_heroes.gd`
**规格：** 两行：vanguard（HP8/盾4/蓝100/速80/初始[laohuoji,tiejian]/被动坚守/技能 vanguard_rampage/crit 0.05）与 ranger（HP6/盾4/蓝110/速88/初始[duangong]/被动鹰眼 crit 0.15/技能 ranger_shadowstep）。schema 校验（GameDB HERO_SCHEMA：id/name/hp/shield/energy/speed/start_weapons:Array[String]/skill_script:String/crit_chance:float/passive:String）。选角 UI：两卡（名字/面板/技能描述），点击选择→`RunState`（若未合并则先落 `selected_hero` 静态暂存，T15 合并时收编）+ 换场景到训练房所在局。
- [ ] TDD：schema 校验、heroes 数量 2、start_weapons 都存在于 GameDB。UI 手动。**Commit** `feat(m1-t11): hero data + select screen`。

### Task 12: 小 Boss×2 + 精英词缀 + 原型映射改造

**Files:** Create `core/enemies/elites/elite_affix.gd`、`tests/unit/test_elites.gd`；Modify `core/enemies/enemy_base.gd`（原型映射改 preload：`const ARCHETYPES := {"charger": preload(...), ...}`，setup 时直接 `script = ARCHETYPES[row.archetype]` 或构造对应类——消除 set_script 脆弱性；保留对外行为/测试契约不变，test_enemy_ai.gd 全部保持绿）、`data/enemies.json`（加 shuang_dao_lizardman 双刀蜥人、zibao_wangchong 自爆王虫，附录 B.3 参数：HP=A1 基准 180）。
**规格：** EliteAffix（词缀枚举+应用）：迅捷 speed×1.3 / 坚甲 hp×3 / 分裂 die 时 2 小怪（原型同 row，hp 减半）/ 虹吸（攻击吸血——M1 无敌人吸血语义，改为击杀玩家? 简化：虹吸=接触伤害命中时自回等量 hp）/ 弹幕大师 / 狂暴（50% 血后攻速 ×1.3——shooter/charger windup 缩短 30%）。`apply(elite: EnemyBase, affix_id: String)`。小 Boss=EnemyBase+固定 2 词缀+体型 1.25+必掉武器+2 红心。
- [ ] TDD：词缀数值应用（迅捷/坚甲数值断言）；分裂（die 后 pending spawns 计数）；双刀蜥人三连冲锋（脑层帧参数）；自爆王虫死亡延迟 1s 大爆（复用 die() 爆炸，延迟 60t——用延迟爆炸字段）；原型映射改造后 M0 全部敌人测试保持绿。**Commit** `feat(m1-t12): elite affixes + 2 minibosses + preload archetype map`。

### Task 13: 藤蔓巨像（A1 Boss）

**Files:** Create `core/enemies/bosses/vine_colossus.gd`；Modify `data/enemies.json`（vine_colossus 行：HP800、phases[1.0,0.6,0.3]、radius 16、contact 5）；Create `tests/unit/test_vine_colossus.gd`
**规格（附录 E.1 逐参数）：** P1：巨掌拍击（前摇 30t，扇形 90°、射程 70px、伤 5、击退）与种子弹环（前摇 36t，以 Boss 为心 12 发环形 ×2 轮、弹伤 3、弹速 110）交替；P2：+藤蔓横扫（前摇 42t，全宽地面藤蔓预警条从左→右 36t 后伤害 5）+召唤蘑菇孢子手（场上 ≤2，每 240t 补）；P3：+毒雨（前摇 60t，全场效果 360t，每 30t 对玩家 1 伤除非在 3 个半径 48px 安全区之一——安全区位置每轮随机、区域画绿圈）。所有招式前摇 ≥0.4s 且地面效果有预警视觉（红纹/绿圈）。
- [ ] TDD（脑层注入帧，沿用 test_boss_base 手法）：阶段切换招式集变化；拍击扇形判定；毒雨安全区内不掉血；召唤上限 2；弹环 12 发计数。场景手动验证：可击败、三阶段演出、战斗 90~150s。**Commit** `feat(m1-t13): vine colossus three-phase boss`。

### Task 14: 商店 + 黑商 + 回收

**Files:** Create `core/meta/shop_logic.gd`（纯函数）、`core/interact/shop.gd`、`tests/unit/test_shop.gd`
**规格：** `ShopLogic.price(rarity: String, floor_idx: int, black: bool) -> int`：基准表 {common:20,uncommon:42,rare:85,epic:155,legend:260}（附录 H 锚点中值）×floor 系数 [1.0,1.6,2.56][floor_idx-1]，black ×1.8，四舍五入到 5。货架生成 `roll_stock(rng, floor_idx) -> Array`：3 武器（掉落权重表 per floor，附录 §8.2）+2 道具（M1 用饮料占位/红心+蓝瓶）+1 饮料；黑商 25% 替换整个货架（紫/橙为主——M1 无橙池则取紫+回退蓝）。支付：金币不足拒绝（提示音+浮标变红）。回收架（shop 门口）：卖当前副手 30% 价格。商店 UI：货架横排卡片（图标桩+名称+价格），点击购买，Esc 关闭。
- [ ] TDD：price 表逐项断言（含 floor2/3 与 black）；roll_stock 数量与稀有度分布（固定 seed）；支付成功/失败扣款路径（RunState 桩注入）。**Commit** `feat(m1-t14): shop with black merchant and recycle`。

### Task 15: RunState autoload（种子激活 + 分盐）

**Files:** Create `autoload/run_state.gd`；Modify `project.godot`（注册 RunState）；Create `tests/unit/test_run_state.gd`
**规格：** 字段：`run_seed:int, floor_idx:int, hero_id:String, coins:int, gems:int, buffs:Array[String], weapons:Array[String](双槽), selected_slot:int, kills:int, rooms_cleared:int, run_time_frames:int`。方法：`start_run(hero_id: String) -> void`（run_seed = hash(Time.get_ticks_usec() ^ randi())——**此处允许非确定源**（开局玩家点击时刻，GDD §9.1），随后 `RngSvc.setup_run(run_seed)`；floor_idx=1；清空 buffs/coins；全字段重置）、`next_floor()`（floor_idx+1，蓝晶结算 +[60,120,200][min(floor_idx-1,2)]）、`salt_streams()` 预定义常量 `const SALT_PROJECTILE/SALT_RIG/SALT_LOOT/SALT_DUNGEON`。全局访问 `RunState.stream(salt) -> RandomNumberGenerator`（= RngSvc.stream(floor_idx, salt)）。
- [ ] TDD：start_run 重置一切并调用 setup_run（用 RngSvc.run_seed 断言）；next_floor 蓝晶结算边界（floor 1→2 给 60）；stream 与 RngSvc 一致性。**Commit** `feat(m1-t15): run state with seed activation and salt constants`。

### Task 16: 雕像×4 + 饮料机

**Files:** Create `data/drinks.json`、`core/interact/shrine.gd`、`core/interact/drink_machine.gd`、`tests/unit/test_facilities.gd`
**规格：** drinks.json 8 行（附录 F.1 逐条：生命苏打+2HPmax…神秘混合=随机）。饮料机：每层 3 次，购买扣金币（价格行内）、效果 apply（经 BuffManager 或直接 player 数值——统一走 BuffManager 临时增益表）。雕像 4 种（附录 F.2：战神 600t 攻速+25%[rig atk_speed_boost_until]、精灵挡 3 弹[召唤护盾精灵跟随，拦截 3 发敌方弹后消失]、风神 300t 移速+30%免蓝、星髓 3600t 随机元素附魔），各 25 金限 1 次。金币不足拒绝。
- [ ] TDD：饮料效果逐条断言（效果应用器纯逻辑）；雕像一次性+扣费；神秘混合从 8 选 1（注入 rng）。**Commit** `feat(m1-t16): shrines and drink machine`。

### Task 17: 存档桩

**Files:** Create `autoload/save_system.gd`、`tests/unit/test_save.gd`；Modify `project.godot`（注册）
**规格：** `user://save.json` `{"version":1, "gems":int, "unlocked_heroes":[], "achievements":{}, "settings":{screen_shake:1.0, damage_numbers:true, colorblind_shapes:false, auto_aim:true}}`。API：`load_save() -> Dictionary`（不存在→默认档）、`save_now()`、`add_gems(n)`、migration 桩（version<1 视为默认）。RunState 结算时 `SaveSystem.add_gems(...)`+save_now。损坏文件→push_error+默认档（fail-soft，玩家存档比 quit 更重要——与 GameDB 相反的有意选择，注释说明）。
- [ ] TDD：往返一致；损坏 JSON→默认档；add_gems 持久化（临时 user:// 路径注入，测后清理）。**Commit** `feat(m1-t17): save system stub with migration hook`。

### Task 18: Juice v1.5 + 遥测集中化（M0 handover 收口）

**Files:** Modify `fx/**`（门动画统一组件 `fx/door_anim.gd`）、`core/meta/telemetry.gd`、`autoload/event_bus.gd`、`core/combat/combat_system.gd`；Create `tests/unit/test_telemetry.gd` 追加用例
**规格：** ①遥测集中化：新增 `Telemetry` 缓冲（内存数组，每 60t 或 32 行 flush 一次；hurt 事件从 CombatSystem/玩家路径发——不再只在 TrainingRoom）；kill 行加来源列（`killer_weapon_id` 或 "contact"/"dot"）；提供 `Telemetry.session_summary()`。②`EventBus.enemy_damaged(amount, is_crit)` 在 EnemyBase.take_hit 中 emit（启用死信号）。③敌弹 400 上限：spawn_projectile 时 ENEMY 阵营在飞数 ≥400 → 新弹替换最旧敌弹（公平性规则沿用）。④门动画组件：开/关 Tween 统一（RoomCombat/楼层门共用）。⑤死亡掉帧防护：hitstop 期间不叠屏震（Fx 内部互斥）。
- [ ] TDD：缓冲 flush 边界；kill 来源列存在；400 上限替换最旧敌弹；enemy_damaged 发出。**Commit** `feat(m1-t18): telemetry centralization, enemy bullet cap, door anim`。

### Task 19: 事件房（4 选 1）

**Files:** Create `core/interact/events.gd`、`tests/unit/test_events.gd`
**规格：** 事件房进房触发 4 选 1 面板（每局随机 4 抽 1）：神秘商人（2HP 换随机饮料效果，可拒绝）；乞丐（投 40 金→70% 下层返 120——记账在 RunState.pending_investment）；星髓泉（本局盾上限+1，每局 1 次）；涂鸦墙（随机构筑提示文案池 10 条，纯叙事）。全部经 Interactable/面板交互，Esc 拒绝。
- [ ] TDD：每事件的效果路径（血换/记账/盾上限/文案池）；拒绝路径无副作用；星髓泉二次无效。**Commit** `feat(m1-t19): event room with 4 events`。

### Task 20: 层间流程

**Files:** Create `core/rooms/inter_floor.gd`(+tscn)、`tests/unit/test_inter_floor.gd`
**规格：** Boss 死亡→`InterFloor.open()`：①增益三选一（复用 T9 UI）②治疗喷泉（回 2 HP，免费一次）③下一层门（进入→`RunState.next_floor()`→按新 floor 种子重建楼层场景）。状态机纯逻辑类 `InterFloorFlow`（阶段：BUFF→FOUNTAIN→DOOR）可无头测试。第 3 层（floor_idx==3）Boss 后→直接胜利结算桩（M2 接完整）。
- [ ] TDD：流程阶段推进/跳过规则；next_floor 触发；胜利桩触发条件。**Commit** `feat(m1-t20): inter-floor flow with buff pick and fountain`。

### Task 21: 三端输入（手柄+触屏+自动瞄准）

**Files:** Create `ui/virtual_joystick.gd`(+tscn)、`core/player/auto_aim.gd`、`tests/unit/test_auto_aim.gd`；Modify `project.godot`（手柄映射：左摇杆移动/右摇杆瞄准射击/RB 技能/A 翻滚/LB 切枪/X 交互）、`tools/setup_input.gd`（追加手柄绑定，幂等）。
**规格：** 触屏（`OS.has_feature("mobile")` 或设置开关）：左摇杆移动、右摇杆推=瞄准+射、技能/翻滚/切枪按钮；auto_aim.gd 纯逻辑：`pick_target(player_pos: Vector2, facing: float, enemies_pos: Array[Vector2], cone_deg := 60.0) -> int`（锥内最近者索引，-1 无）；无右摇杆输入时自动向 pick_target 开火。桌面行为完全不变。
- [ ] TDD：pick_target 锥形选择（锥内近者优先/锥外忽略/空数组 -1）；joystick 输出向量死区处理。真机/触屏手动验证项记入报告（本机无触屏则声明）。**Commit** `feat(m1-t21): gamepad + touch input with auto aim`。

### Task 22: 死亡结算 + 死亡回顾 v1

**Files:** Create `core/meta/death_recorder.gd`、`ui/death_summary.tscn(+gd)`、`tests/unit/test_death_recorder.gd`
**规格：** DeathRecorder（ autoload 或 RunState 挂载）：滑动窗口记录玩家受击事件（帧/伤害/来源类型/来源 id/位置），容量 3s（180t）；死亡时生成 `DeathReport`：本局统计（房数/击杀/金币/时长/最高 DPS 采样）+ 致死来源高亮（最近一次受击的来源）。DeathSummary UI：统计面板 + 「致死原因：弩兵的弹幕」大字 + 任意键回主菜单；蓝晶按 §14（死亡保留 50%）入账（调 SaveSystem）。
- [ ] TDD：窗口滚动淘汰；致死来源提取；报告统计正确性（注入事件序列）。UI 手动。**Commit** `feat(m1-t22): death summary with cause recap`。

### Task 23: 主菜单 + 场景路由

**Files:** Create `ui/main_menu.tscn(+gd)`；Modify `autoload/scene_router.gd`（实现 goto_scene(path) 封装 change_scene_to_file，带淡入淡出 0.2s）、project.godot main_scene→main_menu.tscn
**规格：** 主菜单：开始（→选角）、图鉴/天赋/成就（M2 占位灰按钮）、设置（屏震/伤害数字开关，读写 SaveSystem.settings）、退出。路由表常量 `ROUTER := {menu, hero_select, game, death}`。
- [ ] TDD：路由表完整性（每个键存在 tscn 路径）；scene_router 切换后当前场景名正确（headless scene runner 或直接断言封装逻辑）。UI 手动走通：主菜单→选角→进局→死亡→回主菜单。**Commit** `feat(m1-t23): main menu and scene router`。

### Task 24: HUD 完整版

**Files:** Modify `ui/hud.gd`(+tscn)；Create `tests/unit/test_hud.gd`
**规格：** 在 M0 基础上增加：金币计数（RunState.coins）、层号+种子号（左上小字）、双武器槽图标+当前槽高亮、技能 CD 环（SkillBase.cooldown_remaining）、翻滚 CD 点、Buff 图标行（RunState.buffs）。数据全部每帧从 RunState/Player/Skill 读取，不缓存。低血量（≤2）红晕呼吸提示。
- [ ] TDD：读数绑定函数纯逻辑抽取（`hud_snapshot(player, run) -> Dictionary` 断言各字段映射）；CD 环比例计算。视觉手动。**Commit** `feat(m1-t24): full hud with run state binding`。

### Task 25: 武器扩至 40（数据管家卡）

**Files:** Modify `data/weapons.json`；Create `tests/unit/test_weapons_pool.gd`
**规格：** 按附录 A 增至 ≥40 把：新增 34 把从 A.1~A.8 选取（白→绿→蓝为主，含 8 把元素附魔武器：熔火手枪/霜牙/电雀/燃烧弹链/冻结核/龙息/冰晶射线/毒云杖——确保 4 元素各 ≥2 把，元素共鸣链路可玩）。全部行符合 schema v2（T3）。测试：总数 ≥40；4 元素各有 ≥2 把；rarity 分布白 ≥8 绿 ≥12 蓝 ≥15；全部 id 唯一且 name 非空；逐行 validate 通过。
- [ ] 实现（JSON 转录）→ 测试全绿 → 分布报告写入提交说明。**Commit** `feat(m1-t25): expand weapon pool to 40 with element coverage`。

### Task 26: M1 门禁

**Files:** Create `docs/superpowers/reports/m1-gate-integration.md`、`m1-gate-playtest.md`、`m1-gate.md`
**规格（双角色并行，同 M0 模式）：**
- 集成守卫：全量测试绿；无头启动；`tools/validate_dungeon.gd` 1000/1000；存档往返；工作树干净。
- 试玩员（computer-use）：完整一局——主菜单→选角骑士→A1 全层（战斗/精英/商店/宝箱/事件/小Boss/Boss）→层间三选一→第 2 层进入； checklist：①30 分钟能完成一局到 A2（超时也算体验完整）②死亡有回顾③商店可买可卖④三选一出现且生效⑤藤蔓巨像三阶段⑥Boss 战 90~150s⑦主观"想开第 2 局"≥3/5。
- 编排者裁定出 `m1-gate.md` → GREEN 则 tag `m1`。
