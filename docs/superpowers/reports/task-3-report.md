# M2 Task 3 独立评审报告（图鉴解锁 49 条 + 成就接线表 + 增益白名单）

> 评审对象：`.worktrees/m2-t3`（分支 `m2-t3`，单 commit `799dc18` "feat(m2-t3): codex unlock tasks (49) + achievement wiring table"，基于 `1d71bda`）
> 评审日期：2026-08-30。只读评审（未修改任何代码 / 未 commit / 未 merge；评审中 `--import` 触碰的 `icon.svg.import` 已还原，工作树保持 clean）。
> 评审依据：`docs/superpowers/plans/2026-08-30-m2-full-content.md`（Global Constraints + Task 3 卡）、`docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md` 附录 A/C/G（数值唯一出处）。
> 被审产物：附录 J（`数据表附录-J-图鉴解锁.md`）、附录 K（`数据表附录-K-成就接线.md`）、`data/unlock_tasks.json`、`tests/unit/test_unlock_data.gd`。

## 结论

**Approved-with-notes**

规格逐项全部 PASS：49 条与 `data/weapons.json` locked:true 集合双向零差（紫 33+橙 16 独立验证）；条件类型白名单 6 类 + int 阈值 fail-closed；编排者裁定③（4★=craft_x+forge_only 契约）落实；craft_x=5 条中湮灭号角 craft_x 10 系附录 A L11 明文示例照录（已核实原文确有「完成 10 次熔铸解锁「湮灭号角」（橙）」）；成就接线表 24 条（22 M2 + 2 M3）逐条与附录 G 一致，既有 4 信号名+签名与 `event_bus.gd` 逐字一致；TDD 五项齐备。实测 **827/827 全绿（52/52 套件，3min7s）**，`test_unlock_data` 17/17，与自报 +17 一致。

无 Blocker。3 项 Major **全部是文档/接线表层面的勘误**（不涉及本卡数据与代码缺陷，不阻塞合并，但须在 T12 合并及 T20/T25/T33 消费前完成）：① J.7 增益键白名单 10/21 键名与 T12 已实现键分歧（两分支同基并行互不可见所致）；② buy_x 计数源在 K.2 信号清单中缺失（T3 卡「全部可用遥测或 RunState 判定」对此型当前不成立）；③ K.2 新声明 `boss_defeated` 与既有 FloorScene 局部信号同名异签名未注记。另有 3 项 Minor（清点口径/算术/先例引用表述）。

---

## 一、规格符合度逐项表

| # | 规格项（Task 3 卡 + 附录 A/G + 裁定） | 结果 | 证据 |
|---|---|---|---|
| 1 | 49 条 = weapons.json 全部 locked:true（双向一致，紫33+橙16） | **PASS** | 评审员独立解析：115 把（common 9/uncommon 21/rare 36/epic 33/legend 16），locked:true 恰 49（epic 33+legend 16）；`task_ids − locked = ∅`、`locked − tasks = ∅` 双向零差；`test_bidirectional_match_with_weapons_locked_set` + `test_rarity_distribution_33_epic_16_legend` 真实锁定 |
| 2 | 条件类型白名单 kill_x/clear_floor_x/craft_x/resonate_x/collect_gems_x/buy_x | **PASS** | `TYPE_WHITELIST` 恰 6 类；49 行 type 全部落白名单（`test_type_distribution_locked`）；负样本 `headshot_x` 拒收 |
| 3 | 参数+阈值 int | **PASS** | SCHEMA `param/goal: TYPE_INT`；整值还原口径与 `GameDB._normalize_row`（game_db.gd:228-236）逐行核实一致；带小数 goal（300.5）/越界 param（4）/非 floor 带 param（2）负样本真实拒收 |
| 4 | 全部可用遥测或 RunState 判定 | **PASS（带 Major ②）** | kill→`kill` 行、clear_floor→`floor_clear` 行（telemetry.gd:117 既有）、resonate→`EventBus.resonance_triggered`（既有信号）核实存在；craft→`item_forged`（K.2 声明，T25 发射）；**buy→无任何既有/已声明源**（见 Major ②）；collect_gems 半依赖未来口径（层通过已可判，击杀/首杀/成就蓝晶归 T32/T33，J.2 已注明） |
| 5 | 裁定③：4 把★（星陨炮/雷神之锤/斩舰刀/湮灭核心）= craft_x | **PASS** | `FORGE_ONLY_IDS` 4 把全部 craft_x（`test_star_weapons_use_craft_x_per_ruling`）；附录 J.3 规则 2 明文记录裁定 |
| 6 | 附录 J 注明 forge_only 契约（T20） | **PASS** | J.6 专节：解锁后★仍不入普通掉落池、T20 池过滤须查 `unlock_tasks[id].forge_only`、weapons.json「无需也不得加此键」——实测 weapons.json 4★ 无 forge_only 键、locked:true；`test_forge_only_exactly_four_star_weapons` + `test_non_star_weapons_unlock_into_drop_pool` 双向锁定 |
| 7 | 实现者偏差待核：craft_x=5 条、湮灭号角照录附录 A 示例 | **PASS** | 附录 A L11 原文确认：「解锁任务示例：击杀 300 敌人解锁「哑火者」（紫）、**完成 10 次熔铸解锁「湮灭号角」（橙）**」——示例确实存在，照录无误；哑火者 kill_x 300 同样照录；craft 5 = 4★ + 湮灭号角，J.5 分布表明示「5（4★ + 湮灭号角）」 |
| 8 | 成就接线表 24 条 = 22 M2 + 2 M3 试炼 | **PASS** | K.3 恰 24 行，批次列 M3 仅 `trier`/`trial_master`（#21/#22）＝22+2；逐条成就名/条件/蓝晶与附录 G.1 全量一致（24/24） |
| 9 | 信号名与既有代码信号一致性 | **PASS（带 Major ③）** | K.2 标「既有」4 信号与 `event_bus.gd:3-12` 逐字一致：`enemy_damaged(amount,is_crit)`、`enemy_killed(enemy_id)`、`resonance_triggered(reaction,at,payload)`、`room_cleared(room_id)`；12 新声明中 11 个全库无冲突，**`boss_defeated` 除外**（见 Major ③） |
| 10 | 增益白名单专节：21 新键 × 消费卡号 | **PASS（形式）/ 键名交叉有分歧** | J.7 表 21 行 × 消费卡号（M2-T12 落地 + 下游消费卡 T4/T7/T10/T21/T31）齐全；与 T12 交叉核对 11/21 逐字一致、10/21 分歧（见 Major ① 与第三节） |
| 11 | TDD：49 计数/白名单/int/双向一致/分布锁定 | **PASS** | 五项全覆盖且分布锁定到刻度带级：`test_exactly_49_tasks`、`test_type_distribution_locked`（kill15/resonate16/clear7/craft5/gems3/buy3）、`test_param_and_goal_are_int`、双向一致、`test_goal_within_bounds_by_type_and_rarity` + `test_goal_gradient_epic_below_legend`（紫 max < 橙 min ×3 型 + 层号 2<3） |
| 12 | 附录 J.4 表与 data/unlock_tasks.json 一致 | **PASS** | 评审员程序化解析 J.4 全部 49 行（type/param/goal/forge_only 四字段）与 JSON 逐字段比对：**49/49 一致，0 失配，无单边条目** |
| 13 | Global Constraints #3/#8/#6 + conventional commit | **PASS** | 数值唯一出处遵守（两处附录 A 示例照录并标出处）；改 data/*.json 附分布/一致性测试；commit `feat(m2-t3): ...` 带卡号；`.uid` 已随提交；diff 仅 5 文件无噪音 |

## 二、测试实测（评审员本机）

```
godot --headless --path . --import                          → 通过
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
       -a res://tests --ignoreHeadlessMode
→ Overall: 827 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped
  Executed suites (52/52) / cases (827/827) / 3min 7s / exit 0
→ test_unlock_data 套件：17 tests / 0 failures / 0 errors / 3.627s（XML: reports/report_6）
```

与实现者自报 827/827（+17）完全一致。测试质量核验：

- **负样本真实性**：`validate_unlock_row` 为行级校验器实体（非恒真桩），负样本 10 类（坏 type/goal≤0/小数/越界 param/非 floor 带 param/缺键/id≠weapon/空 desc/forge_only 非 bool/空行）全部走真实校验路径拒收。
- **断言非恒真**：计数/分布/刻度带常量与实现者数据独立得出且与附录 A/J 定稿一致；`before_test` 每次重读 JSON 文件（动态计算）。
- **稀有度分布断言实现真实**：join `GameDB.weapons_all` 读 `rarity` 字段（非自证），且 locked 集合双向断言（任务多/少都失败）——「与 weapons.json 稀有度分布一致」规格项为真实实现。
- **整值还原与 trials 卡的差异处理得当**：trials 卡（m3-p0-3）注释「绝不 typeof==TYPE_INT 判断」，本卡改为先还原再断言 typeof（GameDB._normalize_row 同款）——比 trials 更严（带小数即拒收），口径已在文件头声明。

## 三、与 T12 键名交叉核对（重点项）

**背景**：T12（`.worktrees/m2-t12`，commit `137eed1`，同样基于 `1d71bda`）已实现 36 增益 + `GameDB.BUFF_PCT_KEYS/BUFF_INT_KEYS/BUFF_FLAG_KEYS`（game_db.gd:64-85）。两分支同基并行，互不可见对方的键名定稿。

**T12 实际新键 = 25 个**（11 pct + 8 int + 6 flag），非 21：M1 既有 15 键之外，T12 将 J.7 的 3 个单键拆成对键、为复仇者加了时长键、并为视界系拆出幅度键。

**逐键对照（J.7 声明 → T12 实际）**：

| J.7 键（21） | T12 实际键 | 一致？ |
|---|---|---|
| wealth_pct / pickup_radius_pct / heart_sense_pct / haggle_pct | 同名 | ✓（4） |
| vengeance_pct | vengeance_pct（另加 vengeance_ticks 表 3s 窗口） | ✓（1） |
| resonance_radius_pct / resonance_duration_ticks | 同名（共鸣增幅 2 键，双方一致） | ✓（2） |
| phoenix_flag / anti_fire / anti_ice / anti_poison | 同名（T12 命名组为 BUFF_FLAG_KEYS） | ✓（4） |
| big_eater_pct | **drink_effect_pct** | ✗ |
| energy_siphon_pct | **kill_energy_chance + kill_energy_amount**（拆对） | ✗ |
| ammo_convert_energy | **passive_energy_interval_ticks + passive_energy_amount**（拆对） | ✗ |
| element_vision（int 9t） | **element_vision（flag）+ telegraph_bonus_ticks（int）**（类型改 flag、幅度另键） | ✗ |
| resonance_vision_flag | **resonance_vision** | ✗ |
| hunter_vs_status_pct | **dmg_vs_statused_pct** | ✗ |
| nerve_reflex_ticks | **hurt_iframe_bonus_ticks** | ✗ |
| bullet_resist_pct | **bullet_dmg_taken_pct**（名+符号向不同） | ✗ |
| thorns_dmg | **thorns_contact_dmg** | ✗ |
| dash_extend_pct | **roll_distance_pct** | ✗ |

**小结**：11/21 逐字一致；10/21 分歧；T12 另引入 vengeance_ticks（J.7 未收录）——T12 的 25 新键中有 13 键不在 J.7 白名单内。J.7 声称「键名与 T12 卡已声明聚合键（haggle_pct, heart_sense_pct, pickup_radius_pct, phoenix_flag, anti_fire/ice/poison, element_vision, vengeance_pct, wealth_pct…）逐字对齐」——对计划卡 T12 行**明文列出的 9 个键成立**（全部核对一致），分歧全部落在省略号部分。

**T12 侧数据顺带核实**：36 条、稀有度 common 15/uncommon 11/rare 10——与附录 C 实际清点（白15/绿11/蓝10）逐档一致（计划卡行文「白14/绿12/蓝10」本身有误，T12 数据正确）；J.7 的「剩余 20 条」算术（36−16）正确。

## 四、质量发现

### Major（3 项，均为文档/接线表勘误级，不阻塞合并）

**Major ① J.7 增益键白名单与 T12 实现已分歧（10/21 键名 + 拆键结构）**
- 证据：第三节对照表；`.worktrees/m2-t12/autoload/game_db.gd:64-85` vs 附录 J.7。
- 影响：T15（天赋 effects 键白名单「复用 buff_manager 键」）、T20/T33 若按 J.7 取键名将找不到 T12 代码中的键；两份「定稿」并存会在后续卡产生权威歧义。
- 定性：两分支同基并行（均基于 1d71bda），非任何一方单方过错；J.9 逃生条款（「键须落入本白名单或由 T12 卡补宣言」）只覆盖「第 21 条增益」场景，未覆盖改名/拆键。
- 建议：T12 合并后对附录 J.7 出勘误节，**以 T12 实际键为权威**（T12 命名更贴 M1 既有习惯：drink_effect/kill_energy/roll_distance/bullet_dmg_taken 均沿用既有构词），J.7 表逐键标注映射；若编排者裁定反向（以 J.7 为准），则 T12 需改名 10 键——成本更高且会破坏 T12 已绿的测试，不推荐。

**Major ② buy_x 计数源在 K.2 信号清单中缺失**
- 证据：J.2 buy_x 行判定数据=「商店/饮料机成交事件 → counters.purchases_total」，但 K.2 的 16 信号（4 既有 + 12 新声明）无任何购买信号；`grep` 证实 `shop.gd`/`shop_logic.gd`/`drink_machine.gd` 现无 EventBus 发射、无遥测行；K.2 遥测扩展行（death/heart_pickup/prop_destroyed/roll_dodge/crit）亦不含购买；K.5 只把 `counters.purchases_total` 的**写入方**标给 T25（聚合入档），未定义**发射点**。
- 影响：T3 卡规格明文「全部可用遥测或 RunState 判定」——buy_x（3 条任务）当前不成立；T20 实现进度判定时将发现无源可取，届时需临场发明信号，违背接线表防错接线的初衷。
- 建议：K.2 增补一行新声明信号（如 `item_purchased(kind: String)` → 商店/饮料机成交点，发射责任卡标 T25 或 T33），并在 J.2 buy_x 行回链该信号名；同时建议在 J.2 collect_gems_x 行注明「击杀/首杀/成就蓝晶入账依赖 T32/T33 口径」（当前仅层通过蓝晶可判）。

**Major ③ K.2 新声明 `boss_defeated(boss_id: String, floor_idx: int)` 与既有 FloorScene 局部信号同名异签名**
- 证据：`core/rooms/floor_scene.gd:69` `signal boss_defeated(room_id: int)`（boss 房清时 emit，`run_root.gd:115` 消费中）；K.2 将 EventBus 侧新信号标为「新声明」且未提及既有局部信号。
- 影响：T33 接线时存在误接（听错对象/错签名）与双源混淆（FloorScene 局部信号在 boss 房清发、K.2 信号在 BossBase/RoomCombat 死亡点发——语义相近但参数完全不同）。
- 建议：K.2 该行加注：既有 `FloorScene.boss_defeated(room_id: int)` 局部信号的存在、两者的关系（建议明确 EventBus 新信号为 T33 唯一订阅源，FloorScene 局部信号保留现状仅作层间流转，或由 T33 发射点直接复用 RoomCombat 死亡上下文）。

### Minor（3 项）

**Minor ① J.3 规则 3 元素武器清点口径错误（12 vs 实际 13）**
- J.3：「weapons.json 中 element != none 的 12 把（紫 11 + 橙 1 电磁轨道）」；实测 locked 且 element≠none 为 **13 把**（epic 11 + legend 2：电磁轨道 **shock、雷神之锤 shock**）。雷神之锤是★、已被规则 2（裁定③ craft_x）先行覆盖，分配结果自洽（resonate_x 16 条 = 12 元素 + 4 特性绑定），但「12 把」的清点表述与数据不符。建议改为「13 把中 12 把走 resonate_x（★雷神之锤被裁定③ craft_x 覆盖）」。

**Minor ② K.3 脚注蓝晶合计算术错误**
- 「蓝晶合计：M2 22 条 = 3350；M3 2 条 = 300」——M3=300 正确；M2 逐条求和实为 **4050**（100×8 + 150×5 + 300×2 + 200×2 + 500×2 + 400 + 50×2）。逐条数值与附录 G 一致无误，仅合计错。若 T33 以「合计」做经济校验会出错，建议勘误。

**Minor ③ J.5 前言「照抄 T2 test_talents_data.gd 模式」表述不准**
- T2 先例是 GameDB 装载 + `load_ok` + GameDB 校验器模式；本卡测试的装载机制（FileAccess 直读 + 测试内 static 校验器）实为 m3-p0-3 trials 卡先例（commit `bfc16a8`，m3-prelude 分支，未合 main）——测试文件头自己写对了（「数据卡先行模式，同 trials 卡」），附录 J.5 前言与文件头口径不一。fail-closed 精神与负样本风格确与 T2 一致。建议 J.5 前言改为「同 trials 卡的独立校验模式 + T2 的 fail-closed/负样本风格」。

### Info（不计缺陷）

- K 表引用的代码实体经逐一核实全部存在且签名一致：`Telemetry.session_summary()`（kills/hurt_count/rooms/peak_dps/run_time 五字段，telemetry.gd:80-87）、`RunState.run_time_frames/coins/next_floor()`、`SaveSystem.unlocked_heroes/add_gems()/unlock_hero()`、kill 行 boss 标记+武器 id（telemetry.gd 头注释+room_combat.gd:216）、fire 行武器 id（player_driver.gd:42/45，近战/远程均带）、「speedrunner 72000 ticks = 20min×60fps」换算正确。
- desc 文案含阈值数字（clear_floor 另含层号）由测试锁定——图鉴 UI 直读安全，好实践。
- J.5 节奏校准的速率假设明确标注来源（M1 门禁实测口径），未冒充已验证事实；「20h 解锁 80% ≈ 39/49」换算正确。
- J.6 对 T20 的掉落池过滤契约（`locked && id ∉ unlocked`、★例外须查 `unlock_tasks[id].forge_only`）可编码性良好，且与 T6 已交付的 `weapons_all`/locked 机制（game_db.gd:131-147）严丝合缝。
- K.2 将 `victory_achieved`（T18）、`item_forged`（T25）、`weapon_unlocked`（T20）、`talent_purchased`（T15）、`challenge_cleared`（T30）的发射责任正确指回各卡明文（与计划卡逐一对得上）。
- 工作树卫生：commit 无 import 噪音；评审产生的 `icon.svg.import` 变更已还原。

## 五、修复建议汇总（按优先级）

1. **（随 T12 合并单）** 附录 J.7 勘误：以 T12 实际 25 新键为权威重排白名单表，逐键标注与 J.7 原名的映射（Major ①）。
2. **（本卡补文档提交，建议随 merge 前完成）** K.2 增补购买信号声明 + J.2 buy_x 回链；J.2 collect_gems_x 注明 T32/T33 依赖（Major ②）。
3. **（同上）** K.2 `boss_defeated` 行加注与既有 FloorScene 局部信号的关系（Major ③）。
4. （可选）J.3「12 把」→「13 把中 12 把」、K.3 脚注 3350→4050、J.5 前言先例表述（Minor ①②③）——三项均可并入上述同一勘误提交。
