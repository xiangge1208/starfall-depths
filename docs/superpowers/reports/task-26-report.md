# T26 独立评审报告（m2-t26 @ 569d79e）

- 评审对象：`m2-t26` 分支，提交链 `2e08aa8`(wip 抢救) → `df68ea1`(merge main) → `759c2f7`(M1 灾厄) → `d203c6c`(M2 模板×16) → `8be3c92`(M3 矩阵复核) → `569d79e`(M4 移交项)
- 评审方式：只读代码 + diff 逐项核实 + `git merge-tree` 合并面预判 + 全量测试复跑
- 结论：**NEEDS FIXES**（Critical 0 / Important 3 / Minor 4；其中 Important-3 为已披露项追认，需立卡跟踪）

## 1. 概述

T26 交付四块：挑战房灾厄（4 选 1 → 3 波强化 → 必得紫+80~120 金币，仅本房生效）、A2/A3 战斗模板 ×16（+各层 start/boss，biome 字段 + 冰面/地刺/晶柱 + 岩浆/喷口）、房型矩阵复核（9 角色 ×3 生态，容量 8×2=16 ≥ 11 池房/层）、T25/T9/T7/T4 移交项（miniboss 抽取池按层 + B.3 HP 表、晶柱 kind 拆分、冰面视觉 biome 驱动、summons 跨房重接）。半成品走查脚本修复后转正为 `test_challenge_full_run_on_real_build`。整体实现质量高：测试均为真断言、盐纪律严格（新增 `calamity`/`miniboss` 独立无状态盐流）、数据 fail-closed 路径完整。三处既有测试契约更新（披露⑥）核实为**加强而非放松**。合并面 `git merge-tree --write-tree main m2-t26` 无文本冲突，但有一处语义破坏（见 §5）与两份手工证据脚本漏改（Important-2）。

## 2. 规格符合度（逐项核实）

### 2.1 灾厄数值对照 GDD §11（通过）

`ui/calamity.gd:12-17` 目录四条中文逐字对齐设计表（敌速+30% / 视野-35% / 治疗无效 / 弹速+25%）；落地常量 `core/rooms/floor_scene.gd:60-63`：`CALAMITY_SPEED_MULT=1.3` / `CALAMITY_BULLET_MULT=1.25` / `CALAMITY_VISION_FACTOR=0.65` / heal meta。敌速覆盖 `speed/walk_speed/dash_speed` 键族（charger 无 speed 键的兜底，`floor_scene.gd:64`）。3 波强化 = 波1/波2/波1 轮转 + 行 hp ×1.25（`challenge_waves_for`，`floor_scene.gd:1534-1541`）。清房必得紫（`_roll_challenge_epic_weapon` 取 weapons_all 全量 epic、排 forge_only）+ 80~120 金币（`_loot_rng` 确定性）。奖励置零防重复发放。挑战房承载方式（combat 房行级标记）与裁定⑭一致（`docs/superpowers/reports/m2-progress.md:119`）。

**偏差（均为实现者已披露，核实属实）**：① A2/A3 挑战房波次仍 A1 名录（`waves_for` 无条件用 `A1_TRASH`，`floor_scene.gd:1490-1496`）；② 精英嘉宾无楼层 HP 缩放（`_spawn_real_guest` 仅 miniboss_charger 走 `miniboss_hp_for_floor`，`floor_scene.gd:1075-1078`）；③ Boss 三层恒 vine_colossus（`waves_for` "boss" 分支）→ 已立 T36；④ 熔铸台模板字段 defer（main 侧 T25 代码 `--build_shop` 内注释自认「数据驱动模板字段由后续卡扩 schema」，本卡不复读）；⑤ A2 视野灾厄与生态暗视野双实例（见 Important-3）。

### 2.2 miniboss HP 对照数据表 B.3（通过）

`MINIBOSS_FLOOR_HP := {1: 180, 2: 400, 3: 870}`（`floor_scene.gd:70`）对齐附录 B.3「HP=A1 基准 180 / A2 400 / A3 870」；抽取池 6 行 = B.3 全名录（`floor_scene.gd:75-79`），`"miniboss"` 盐流按层确定性取一，表外楼层 clamp。测试 `test_miniboss_hp_floor_scaling_table` / `test_miniboss_pool_per_floor_deterministic` 断言 6 行 hp=180 + drops 一致 + 同种子同层恒同体。`miniboss_override` 测试接缝使既有 M1 走查钉 zibao 口径不漂移。

### 2.3 模板 schema 与 ×16 计数（通过，亲测）

- `data/rooms/a2_templates.json` / `a3_templates.json` 各 10 行 = 8 combat + start + boss；合计 16 张新战斗模板，`GameDB.rooms.size()==30`（`test_room_templates.gd:19`）。
- `validate_room_row`（`autoload/game_db.gd:363`）全过：`test_all_rows_pass_room_validation` 遍历全表断言 errors 为空（复跑绿）。biome optional 键 + `BIOME_TAGS=["", "crystal", "magma"]` 白名单；`HAZARD_KINDS` 扩 ice/spikes/rock（ice 需 radius）；跨文件 id 冲突 fail-closed（`_load_room_tables`）。
- biome 字段抽检：A2 全行 `crystal`、A3 全行 `magma`、A1 缺省 `""`（`test_biome_field_driven_by_template`）。
- A2 hazards 抽检：ice ≥8（radius 形状）、spikes ≥12、每张 A2 战斗模板 ≥1 根 crystal_pillar（props kind，hp=20）；A3：magma ≥8（radius）+ geyser ≥10、每张 ≥1 岩浆系。实测 JSON：A2 ice 10 处 / spikes 21 处 / crystal_pillar 34 根；A3 magma 18 处 / geyser 23 处（`python -c json` 逐行核对）。
- 4 门完备：六张 start/boss 模板 doors == [N,S,E,W]（断言钉死，未用门为封闭门框）。
- 门对齐/去重：`test_a2_a3_floors_fully_validate_and_dedupe` 40 种子 × floor 2/3 全过 `validate_build` + 同层 combat 模板 ≤2（`MAX_TEMPLATE_USES=2` 复核属实，`dungeon_builder.gd:31` + `_pick_fit`）+ 模板不跨层串用。容量论证 8×2=16 ≥ 11 池房/层 成立。

### 2.4 房型矩阵（通过）

9 角色（start/combat/elite/miniboss/treasure/shop/event/boss + 挑战房=combat 择一）× 3 生态无模板空洞：非 start/boss 房型全部从当层 combat 池取几何（`dungeon_builder.gd:5-7`），A2/A3 池落库后三层齐备。注：商店/宝箱/事件房沿用战斗模板 → 会带 ice/magma hazards（商店带岩浆池），设计上可接受但值得后续用设施专用模板收紧（Minor 不另列，归入矩阵备注）。

### 2.5 M4 移交项（全部真实落地）

- **summons 跨房重接**（T25 评审 Important-2）：`_wire_room_combat`（`floor_scene.gd:895-902`）对 `summons` 组存活体重接 `combat = room.combat`，duck-typed 同 ShieldSpirit；新测试 `test_scene_summons_rewire_combat_on_room_switch` 真断言两次换房重接。
- **晶柱 kind 拆分**（T7）：`crystal_pillar` 入 `EnemyLaser.PILLAR_GROUP`，石柱（pillar）不再折射（`floor_scene.gd:458-466`）；贴图 `art/generated/tiles/prop_crystal_pillar.png` 在盘且被 `test_art_lookup` 全表存在性断言覆盖；`test_stone_pillars_do_not_refract` 钉 A1 石柱 0 折射。A2 模板 props 只用 crystal_pillar+crate、A3 只用 pillar+crate（JSON 核对），无混排回归。
- **冰面 + biome 模板驱动**（T4）：`_apply_template_biome`（crystal → `mount_biome_a2(false)` 无演示补丁）+ `_build_ice`（IceZone 域 + `hazard_ice.png`，缺图回落淡蓝圆）；`set_biome_a2` 演示契约保留（`mount/unmount_biome_a2` 拆分为共用底座）；挂载先于 hazards 保证冰面行落进容器。测试覆盖幂等挂载 / zone 数=数据行数 / magma 无全局组件 / 玩家摩擦 0.25↔1.0。
- **披露④熔铸 defer**：核实正当——main 的 forge 代码（+12 行 `_build_shop`）在 t26 分支基线上不存在，此时接线必是重复实现。

### 2.6 披露⑥三个既有测试契约更新（核实：加强，非放松）

1. `test_dungeon_builder.gd::test_combat_pool_matches_room_template_accessor`：`combat_pool(2)` 空池断言 → 三层等价断言 + floor 4 空池 fail-closed（保留了防静默回退语义）。
2. `test_hazards_m2.gd::test_hazards_vine_data_only`（原 hazard 全库 vine）：收窄到 A1 行全 vine r24 + count>0——A1 生态唯一 hazard 契约不变，只是不再错误地断言全库（A2/A3 行本就不该是 vine）。
3. `test_m1_integration.gd::test_boss_death_opens_inter_floor_and_door_enters_floor_two`：A2 存根断言（overlay 显示/floor_scene 为 null）→ 真建层断言（floor_idx=2、13 房、combat 房模板 combat_a2_ 前缀）——由「桩在场」改为「真层在场」，断言面更宽。乞讨用例同步改为真金额/挂账断言（BEGGAR_PAYOUT / pending_investment=0）。

## 3. 灾厄边界纪律（「仅本房生效」核查）

- **进门 → 面板 → 开战**：`enter_room` 挑战房未选灾厄只开面板不刷怪；门锁在进房即生效（`test_challenge_entry_holds_waves_until_choice` 断言 `flow.is_locked()` + 门关），玩家不可能在选择前面板开着时离房。
- **清房还原**：`_on_enemy_died` 清房分支先发奖励再 `_restore_calamity`（状态位 + fx 卸载 + meta 摘除，幂等 no-op）；门开后重进走 `_emit_room_clear` 幂等门，面板不重开（`calamity_id` 已清）。
- **灾厄房内死亡**：换层/场景销毁兜底 `_exit_tree`（`floor_scene.gd:271-276`）摘除 heal meta（玩家不被收养的宿主路径防泄漏），fx 随树释放且 `BiomeFx._exit_tree` 自行恢复敌人剪影与玩家摩擦。`test_calamity_meta_removed_on_scene_exit` 钉死。
- **death replay 接缝**（披露⑦）：致死房为挑战房时自动代选 `enemy_speed`（`ui/death_summary.gd:275-278`），否则波次被面板挂起回放无战斗——核实合理（回放是演示性重建，不追求复现当时所选）。
- **视野公平性下限**：复用 BiomeFx → `silhouette_modulate` 保留 0.4 剪影下限（T4 先例延续）。但光圈 `texture_scale ×0.65`（91px）与剪影函数默认半径 140px 口径不一致（见 Minor-1）。

## 4. 转正走查测试核查（挂死修复说法属实）

- **修复机理核实**：WIP 版（`2e08aa8:tests/unit/t26_manual_walk_tmp.gd`）的 `_await_until` 在条件瞬时满足时 `await` 一个非协程返回值**不让帧**——内层 `while not cleared: _kill_all → _await_until` 在波次调度依赖 `_physics_process` 推进时会零让帧自旋饿死物理帧。转正版 `_clear_room`/`_run_challenge_room` 改为 `_kill_all → await _wait_frames(20)` 无条件固定让帧 + guard<60 上限，机理与自述一致。
- **稳定性**：DFS 带回溯走 13 房（真实构建 `DungeonBuilder.build(SEED,1)` + `validate_build` 干净）；纯物理帧驱动无墙钟等待；guard 上限合计约 20s/房封顶。实测单测 5.96s（自述 5.99s），test_calamity 套件 17 例 7.96s，全量 67 套件 58s——对套件总耗时影响约 10%，可接受。CI 时间敏感风险低（无 sleep/墙钟依赖）。
- 走查断言完整：门锁/面板/未刷怪 → 视野灾厄 fx 挂载 → 3 波全清 → epic 武器（get_weapon rarity 断言）+ 80~120 金币 → fx 卸载 + calamity_id 清空。

## 5. 合并面预判（main @ c72e54e，只标注不解决）

`git merge-tree --write-tree main m2-t26` → 单树 OID、exit 0：**零文本冲突**。两侧对 `floor_scene.gd` 的改动落在不同区域（main：`_build_shop` 熔铸台 + `_on_enemy_died` 击杀蓝晶；t26：挑战房/miniboss/biome/summons），合并树人工检视语义自洽：挑战房杂兵无 guest_kind → T31 蓝晶路由不受影响；miniboss 抽取行保留 `guest_kind="miniboss"` → +20 档照常生效；Forge 用 `SALT_FORGE` 独立盐流不与 calamity/miniboss 冲突。`ui/death_summary.gd` 双侧改动合并后 codex 落盘与灾厄代选共存。

需要标注的合并后续：

1. **语义破坏（= Important-2）**：`tests/scenes/m1_evidence.gd:113`、`tests/scenes/m1_loop_smoke.gd:147` 仍 `await run_root.a2_entry_active()`——A2 模板落库后 `_floor_data_available(2)` 为真，run_root 真建第 2 层，里程碑存根永不再出现。两脚本为有窗手工证据流（非 GdUnit 套件，CI 绿不报警），合并后将以 900 帧超时记 FAIL、exit 1。解法：照 `test_m1_integration` 新契约改为断言真 floor 2。
2. `reports/report_*`（GdUnit 产物）与 `user://telemetry.csv` 为运行产物，已在 ignore/用户目录，无提交风险。
3. 合并后需全量复跑（main 1199 + t26 净增 ≈ 72+ 例），并确认 main 的 headless 存档重定向使本报告 §7 的 save.json 污染不再发生。

## 6. 质量发现

### Critical（0）

无。

### Important

1. **「治疗无效」未拦截玩家技能治疗，面板承诺落空** — `ui/calamity.gd:15` 承诺「本房内一切治疗无效」，但实现只有红心掉落截断（`floor_scene.gd:1215-1218` 的 `_spawn_pickup` heart 门）+ meta 标志；`Player.heal()`（`core/player/player.gd:301`）不读 meta，守护者主动技生命潮汐（`core/player/skills/life_tide.gd:42` 瞬回 2 HP、`:64` 法阵每秒 0.5）在挑战房内照常回血。灾厄是自选惩罚，选 heal_disable 的守护者玩家实质无惩罚。修复建议（二选一，均小）：`Player.heal()` 开头 `if has_meta("calamity_heal_disabled"): return`（meta 名收常量于一处）；或 LifeTide `_activate`/tick 前查同一 meta（保持「不侵入 player.gd」的设计约束）。补一条守护者视角的断言。
2. **里程碑存根退役漏改两份场景证据脚本** — 见 §5-1。`tests/scenes/m1_evidence.gd:113`、`tests/scenes/m1_loop_smoke.gd:147`。属披露⑥同类契约更新（GdUnit 侧改了、有窗侧漏了）。修复：随本卡或合并时改为真 floor 2 断言（floor_scene 非空 + floor_idx=2）。
3. **【披露⑤追认】A2 挑战房视野灾厄双 BiomeFx 实例叠加，方向为「变亮」** — `_apply_calamity`（`floor_scene.gd:1660-1667`）在 A2 层会再挂一个 BiomeFx：两个 CanvasModulate 同画布后挂者胜 → 灾厄的 0.65 灰**替换**生态的 0.25 暗色（画面反而变亮），两只 PointLight2D 同位叠加再增亮；两个 `_process` 逐帧互相覆写敌人 modulate（幸同参数无害）。剪影 0.4 公平下限仍在。已披露、可接受 defer，但需立卡跟踪（建议并入 T36 或新卡）：解法为把 0.65 因子**复合进既有 biome_fx 实例**（canvas 颜色相乘 + light scale 相乘）而非二次实例化。

### Minor

1. 视野灾厄光圈半径（140×0.65=91px）与剪影判定半径（默认 140px）口径不一致：91~140px 环带内敌人按「光圈内」提亮但实际无光——惩罚弱于设计。`floor_scene.gd:1666-1667` vs `core/rooms/biome_fx.gd:silhouette_modulate`。建议剪影计算传 `LIGHT_RADIUS_PX * 0.65`。
2. 挑战房金币 80~120 不随层 ×1.6（GDD §14.1 清房金币 A1 基准 ×1.6/层）。与全库 `waves_for` 金币恒定一致（全局缩放是 M2 遗留事项，非本卡引入），挂账到全局经济缩放卡即可。
3. `_apply_calamity` vision 分支玩家缺失时先置 `room.calamity_id` 再 push_error 返回（`floor_scene.gd:1657-1660`）：灾厄记录已落但 fx 未挂。仅宿主滥用可达，幂等守卫防重入，建议把 `room.calamity_id = id` 移到 match 成功后。
4. 清房一次性铺最多 120 个 Pickup 节点（`_spawn_challenge_rewards`）：一次性爆发可接受，若后续性能走查吃紧可改少量高面额金币。

### 质量杂项（通过）

- 盐纪律：`RngSvc.stream(floor_idx, "calamity"/"miniboss")` 无状态派生，不扰动既有流（`rng_svc.gd:22-25`）；挑战奖励走 `_loot_rng` 沿既掉落习语。
- `.uid`：`ui/calamity.gd.uid`、`tests/unit/test_calamity.gd.uid` 在库；删除的 `t26_manual_walk_tmp.gd(.uid)` 成对移除。
- 热路径零新增分配：`_physics_process` 未变；summons 重接的 `get_nodes_in_group` 仅换房时执行。
- 中英文：注释/文案中文与库内风格一致；面板标题注明「仅本房生效」。
- 测试真断言抽查全过（无恒真断言；契约测试均带失败样例反向断言）。

## 7. 测试复跑记录

- 环境：Godot 4.7.2.stable headless，`--import` exit 0；GdUnitCmdTool `-a res://tests --ignoreHeadlessMode`。
- 结果：**1127/1127 通过（67 套件，0 errors / 0 failures / 0 flaky / 0 orphans），总耗时 58.1s**，与自述一致。`test_challenge_full_run_on_real_build` 5.96s PASSED。
- 存档污染如实记录：分支基线的 SaveSystem 为旧版直写真档，复跑把 `~/AppData/Roaming/Godot/app_userdata/StarfallDepths/save.json` 由 475B（version 2，gems 696，含 boss_first_kills/unlock_tasks）重写为 296B（version 1，gems 710，字段丢弃）——本就是测试残留档（696 gems 等），未还原；main 的 headless 重定向（save_headless.json）合入后此污染路径消失，T31 迁移可处理 v1→v2。

## 8. 结论

**NEEDS FIXES**——四块交付与七项披露全部核实属实、无 Critical；但 Important-1（治疗无效未覆盖技能治疗，挑战房核心特性的规格承诺落空）与 Important-2（存根退役漏改两份场景证据脚本）应在合并前修复（均为小改动）；Important-3 已披露可 defer 但需立卡。修复后连同 main 合并（零文本冲突）做一次全量复跑即可放行。
