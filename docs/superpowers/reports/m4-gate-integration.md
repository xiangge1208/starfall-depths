# M4 Gate — Integration Guard Report（G-1）

- 日期：2026-09-03（门禁守卫执行可自动化项；**GREEN/RED 终裁与 tag `m4` 归编排者**，本报告给建议）
- Repo：worktree `D:\workspace\thomas\.worktrees\m4-gate`，branch `m4-gate`，基线 `00bcce4`（= main，M4 W1~W5 十二卡 + m4-wire 微卡 merge 链全部并入后）
- Godot：`4.7.2.stable.official.ed1daf0bf`；gdUnit 6.2.1；Windows 10.0.26200，i5-14400F / RTX 3050 / 32GB
- 范围声明：G-1 = 集成守卫（本文 Check 1~8）+ 消费端零孤儿审计（Check 2，Global Constraints 约束 10）+ 经济带判定入档核对（Check 6）+ 用户侧条件项盘点（§9）+ 用户自测增补清单（§10）。真人试玩按现行裁定转为用户自测回报。
- 标注约定：各结论标「**本次复跑**」（本机本会话真实运行）或「**引用**」（既有报告数据，未重跑）。
- 工具命令对照（M3 → M4）：全量测试 `cmd //c "tools\\run_tests.cmd"`（照跑）；地牢校验 `godot --headless --path . --script res://tools/validate_dungeon.gd -- --seeds=3000 --floors=1,2,3`（照跑，M2/M3 同参数）；§18.3 抽验 `godot --headless --path . res://tests/scenes/perf_probe.tscn -- --uncapped`（照跑）；存档往返 gdUnit 定向五套件（照跑，用例数 94→99 因 B-3 save 隔离增补）；孤儿审计为 M4 新增（计划约束 10 要求，本门禁以脚本全键扫描执行）。

## 门禁判定（自动化守卫侧建议）

**Check 1~8 全 PASS：全量 1839 绿（×2 复跑）、消费端零孤儿（617 键 0 硬孤儿、M4 焦点键逐键有 gameplay 消费端）、9000 种子地牢 PASS、§18.3 抽验一致、存档 v2 往返 99/99、经济三点判定入档且 md/JSON 数字一致、成就 24/24 全激活、工作树干净 merge 链完整。无 P0/P1 自动化可测缺陷，无未披露孤儿。建议 GREEN（附 §9 用户侧条件项）；终裁与 tag `m4` 归编排者。**

## Check 1 — 全量测试：PASS（本次复跑 ×2）

命令：`cmd //c "tools\\run_tests.cmd"`（内置 import 前置；两次独立进程）。

| 轮 | 结果 |
|---|---|
| 第 1 轮 | **1839 test cases \| 0 errors \| 0 failures \| 0 flaky \| 0 skipped \| 0 orphans**，99/99 套件，(1839/1839)，exit 0，3min 6s |
| 第 2 轮 | **1839 test cases \| 0 errors \| 0 failures \| 0 flaky \| 0 skipped \| 0 orphans**，99/99 套件，(1839/1839)，exit 0 |

测试账目：M3 收口 1654（含暂停菜单补卡 +19）→ M4 执行期逐卡递增，各环有在档记录支撑：C-1 报告「全量 1698/1698 含新 44 用例」（test_signature_moves）→ C-5 提交「1807/1807（基线 1793+14，test_destructible_props）」→ m4-wire「1808」→ B-3 提交「1815（基线 1793+新增 22）」→ B-4 +3（test_economy_sim）等 → **门禁基线 1839**。套件数 90（M3 收口）→ 99，+9 全部为 M4 新卡测试：test_signature_moves（C-1）/ test_buff_consumers + test_codex_seen_writer（C-3）/ test_altar（C-4）/ test_destructible_props（C-5）/ test_hero_passives（C-2）/ test_logo_variants + test_version_consistency（K-1）/ test_economy_sim（B-4）；另 test_art_pipeline（A-2 扩展）、test_save（B-3 增补隔离用例）等既有套件扩展。

## Check 2 — 消费端零孤儿审计（约束 10）：PASS（0 硬孤儿）

方法（本次复跑，脚本全键扫描）：`data/` 全部 14 个 JSON（10 表 + rooms/ 3 模板 + m0_combat）提取全部键——行 id、行内字段键、effects 子键——共 **617 个键**；逐键 grep gameplay 消费端（core/ autoload/ ui/ fx/ 的 .gd/.tscn）；tests/tools 命中单列「仅测试/工具证据」；跨 data 文件引用单列。

| 表 | 键数（含行 id） | gameplay 消费端命中 | 硬孤儿 |
|---|---|---|---|
| balance.json | 30 | 30 | **0** |
| buffs.json | 73 | 61（+12 行 id 走通用池，见下） | **0** |
| drinks.json | 13 | 6（+7 行 id 走通用池） | **0** |
| enemies.json | 136 | 136 | **0** |
| fusions.json | 3 | 3 | **0** |
| heroes.json | 24 | 24 | **0** |
| rooms/a1|a2|a3_templates.json | 74 | 44（+30 行 id 走模板装配） | **0** |
| rooms/m0_combat.json | 5 | 5 | **0** |
| talents.json | 49 | 25（+24 行 id/键走通用池） | **0** |
| trials.json | 19 | 19 | **0** |
| unlock_tasks.json | 56 | 11（+18 行被他表引用 +27 仅测试钉死，全走通用任务系统） | **0** |
| weapons.json | 135 | 30（+105 行 id 全走 `weapons_all` 通用池） | **0** |
| **合计** | **617** | — | **0** |

行 id 级通用池消费端核对（全表迭代=每行可达，非逐行硬编码）：buffs → `core/meta/buff_manager.gd:72`（三选一池）+ `:101`（稀有度过滤）+ 祭坛池；drinks → `core/interact/drink_machine.gd:62` + `core/meta/shop.gd:243`；talents → `core/meta/talent_system.gd:54`（`for id in GameDB.talents` 全树数据驱动 + requires 图）；weapons → `autoload/game_db.gd:238` `weapons_all` 全量 115 把（掉落池 + `core/rooms/floor_scene.gd:2287` 挑战房 epic 池 + 图鉴 CodexSystem 直读）；enemies → 波次/小 Boss 池（`floor_scene.gd` `MINIBOSS_POOL`/`FLOOR_TRASH`/召唤 `summon_row`）；trials → `core/meta/trial_system.gd:59`（因子候选全表）；unlock_tasks → `core/meta/codex_system.gd`（任务目标评估）+ `ui/codex.gd:68`（条件中文直读）+ `core/meta/forge_logic.gd:23`（forge_only 集合权威源）。

### M4 新键逐键核对（本审计重点，全部有 gameplay 消费端）

| 卡 | 键组（data 侧） | 消费端（file:line，本次逐键 grep） |
|---|---|---|
| C-1 | 11 敌行为键族共 31 数据键：`shell_walk_ticks`/`shell_up_ticks`（龟缩）、`arc_shot`（抛物弹）、`puddle_*` 5 键（水洼）、`impact_spawn_*` 3 键（落地生怪）、`pull_*` 4 键（拉拽）、`claw_*` 5 键（钳击）、`steal_coins`（偷币）、`mimic_weapon`（模仿）、`bite_*` 3 键（两段咬）、`firerain_*` 5 键（火雨）、`bullet_element`（电弧链） | 全部命中 `core/enemies/signature_schema.gd`（fail-closed schema）+ 各 archetype（heavy/barrage/splitter/suicide/charger）+ `core/enemies/firerain_zone.gd`/`enemy_base.gd`；遥测 13 事件台账见 m4-c1-smoke.md |
| C-1 微卡（m4-wire） | 4 特技敌波次接线（F2 池）：hardshell_turtle / thorn_turret / moss_slime / seed_pitcher | `floor_scene.gd` F2 池 + `enemy_factory.gd` + `art_lookup.gd`；`test_scene_floor_pool_signature_guests_wired` 钉死（C-1 移交缺口闭合，m4-wire-smoke.md） |
| C-3 | 十增益键：`dmg_vs_statused_pct`、`resonance_radius_pct`+`resonance_duration_ticks`、`vengeance_pct`+`vengeance_ticks`（rig 5）；`element_vision`、`telegraph_bonus_ticks`、`resonance_vision`（展示 3）；`heart_sense_pct`（掉落）；`anti_poison`（免疫） | `core/combat/combat_system.gd` + `core/combat/resonance.gd` + `core/enemies/enemy_base.gd`（telegraph/描边）+ `core/rooms/room_combat.gd`（红心掉率 roll）+ `core/player/player.gd`（仿 anti_ice 模式）；`test_buff_consumers.gd` 钉死 |
| C-3 | `codex_seen` 写入方 | `core/meta/codex_system.gd` + `core/meta/achievement_system.gd`（weapon_seen → recheck 订阅）；`test_codex_seen_writer.gd` 8 例含 collector(50)/grand_collector(115) 权威口径切换断言 |
| C-4 | `altar_chance` / `altar_excludes`（rooms 三模板逐房 0.15 / 五设施互斥） | `autoload/game_db.gd`（schema fail-closed）+ `core/rooms/floor_scene.gd`（掷签生成）+ `core/interact/altar.gd`（交互）；elite_surge 分支读点 `core/meta/trial_mods.gd:111`（单点，禁散读）；`test_altar.gd` 16 例 |
| C-5 | props `hp` / `drops`（pillar 20 / crate 8 + drops ["coin"] 42 行 / bush 4） | `core/rooms/floor_scene.gd:516-545`（`_build_props`/`_build_destructible`：`p.get("hp",1)` 防御缺省 + drops 白名单）+ `core/rooms/destructible_prop.gd`（固定伤害制）+ `game_db.gd` schema（hp 必填正整数、drops 白名单 coin/energy/heart ≤4 条）；`test_destructible_props.gd` 14 例 |

### 已知披露项（非孤儿，报告引用即可）

1. **hero 解锁价 / 技能强化价为 GDD 纸面锚点，无产品字段**：角色价 2000/2000/5000/5000/8000、强化 1500/名在数据表无价格字段，`SaveSystem.unlock_hero` 无扣费、hero_select 无门槛（产品内角色全开放可玩）——m4-economy.md §2/§5 意向台账收口（`intent_in_window`/`intent_only` 处置），接线购买端属功能改动记意向交编排者（见 §9）。
2. **bush 不挡弹 const（C-5 披露）**：bush 保持静态期「仅视觉、不阻挡」语义——`floor_scene.gd:539` `blocks=false`（「灌木不阻挡（静态期语义保持）」）+ `destructible_prop.gd:29` `blocking` 注释；可破坏性本身已生效（`test_destructible_props.gd:188-189`、`:251` take_hit 可拆）。
3. 敌 AI 相位非确定性 / AudioMgr 双轨音量键 / A2 折叠光圈非真实光照 / save 竞态仅限 headless 并行（B-3 已隔离）/ bot 与真人能力差——均为计划「不在 M4 范围的已记录偏差」表在案项，本门禁无新发现。

## Check 3 — 9000 种子地牢校验：PASS（本次复跑）

命令（M2/M3 门禁同款参数化档）：

```
godot --headless --path . --script res://tools/validate_dungeon.gd -- --seeds=3000 --floors=1,2,3
```

结果：**9000/9000 PASS (seeds=3000 floors=[1, 2, 3])**，exit 0，4 秒，零失败种子。与 M2/M3 门禁同口径 9000/9000 一致（含 M4 C-4 祭坛设施缝、C-5 props 数据扩展后的装配校验）。

## Check 4 — §18.3 抽验对照：PASS，与既有数据一致（本次复跑＝抽验口径）

命令（M3 门禁同款）：`godot --headless --path . res://tests/scenes/perf_probe.tscn -- --uncapped` → **PERF VERDICT: PASS**，exit 0，0 SCRIPT ERROR（uncapped 为既定诊断路径，60fps 合成线在该档不判定，同 M3 口径）。

| 指标（GDD §18.3 预算线） | F1 a1_03（密度 18） | F2 a2_01（密度 13） | F3 a3_08（密度 14） | 判定 |
|---|---|---|---|---|
| 逻辑帧 avg（≤6ms） | 0.022ms（max 0.034） | 0.016ms（max 0.028） | 0.022ms（max 0.041） | **PASS**，与 M3 门禁 0.032~0.038ms 同量级 |
| 渲染 CPU avg（≤10ms） | 0.003ms | 0.005ms | 0.003ms | **PASS** |
| draw call（≤150） | 0（头less Dummy 恒 0，不可测） | 0 | 0 | N/A（口径受限于头less）；**以窗口化抽验为准（引用）**：m4-c5-perf.md F2 draw avg 107.6 / max 185 ≤150 预算 PASS；K-3 复测 F2 100.9/149 |
| 活动实体（≤300，非弹幕） | 66（敌峰 51+陈设 14） | 60（敌峰 51+危险 5） | 63（敌峰 49+危险 6+注入 3） | **PASS**，与 M3 门禁 59~66 一致 |
| 同屏弹幕（≤500） | 峰 500 顶格 | 峰 500 顶格 | 峰 500 顶格 | **PASS**（含 M4 敌弹量无回归） |
| 粒子池观测 | 峰 23 / 降级 0 | 峰 16 / 降级 0 | 峰 13 / 降级 0 | **一致**（预算 200 未触顶） |
| 60fps 合成线 | N/A（uncapped 档不判定） | N/A | N/A | 节流窗正式复测维持 X-B 移交口径（引用；用户侧 §9） |

M4 新增可视负担（暴击弹帧切换、伤害数字/FX self_modulate 增亮、可破坏物）在 F2 满压下 draw 无回归（上行引用数据），§18.3 五指标口径与 M3 门禁及 X-B 报告一致，无偏差。

## Check 5 — 存档 v2 往返：PASS（本次复跑＝定向复跑口径，99 用例现行口径）

M3 门禁同款定向五套件（save v2 全字段往返 / v1 迁移 / 幂等 / 设置持久化 / 改键持久化 / 图鉴进度跨档）：

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/test_save.gd -a res://tests/unit/test_settings_ui.gd \
  -a res://tests/unit/test_rebind.gd -a res://tests/unit/test_codex_system.gd \
  -a res://tests/unit/test_trial_records.gd --ignoreHeadlessMode
```

结果：**99 test cases \| 0 errors \| 0 failures，5/5 套件，(99/99)，exit 0**（test_save 28 + test_settings_ui 10 + test_rebind 11 + test_codex_system 23 + test_trial_records 27）。M3 门禁时为 94 → +5 为 B-3 save 并行隔离增补（`test_headless_save_path_convention`、`test_cli_save_suffix_redirects_path_for_valid_suffix`、`test_cli_save_suffix_ignores_invalid_values`、`test_parallel_suffixed_instances_do_not_crosstalk`、`test_set_setting_session_does_not_write_disk`），账目闭合。X-C 点名用例逐条在本次复跑 PASSED：`test_roundtrip_persists_all_fields`、`test_v1_save_migrates_to_v2_preserving_all_fields`、`test_migration_v2_idempotent_double_load`、`test_unlock_tasks_progress_roundtrip`、`test_volume_int_keys_roundtrip_through_disk`、`test_persistence_roundtrip_through_disk`（rebind）。「首次启动建档→重启读档」真人闭环走查归用户自测。

## Check 6 — 经济判定入档核对：PASS（核对＋JSON↔md 数字复算一致）

- **m4-economy.md 三点判定表完整**：P1/P2/P3 各带悲观/目标/乐观三档区间 + 主判定（目标档）+ 区间结论——P1 解锁第 1 角色「到达 2.5~18.4h，主判出带」；P2 天赋 60%「7.7~10.5h，主判带内（10h 56%）」；P3 图鉴 80%「24%~94%，主判带内（65%）」。出带修订台账 5 行完整（P1 悲观 9.01x/P1 目标 1.12x `intent_in_window`/P2 悲观 4.43x/P2 乐观 0.73x/P3 悲观），处置口径三档（`revise_candidate`/`intent_in_window`/`intent_only`）明文，符合「≤±20% 窗口纪律 + 杆位所有权」约束。
- **m4-balance-rerun.md 残差/结局分布完整**：100 局（种子 3401..3500，b4a..b4d 四批并行 `--save-suffix` 隔离）＝死亡 94 / 停滞 6 / 超时 0 / 崩溃 0，**残差率 6%**（B-2 主批 11% → 无回归且改善）；残差种子 6 枚列名；死亡热房分布（combat 68/elite 18/miniboss 6/boss 2）；TTK A1 杂兵 5.2s（P90 10.7，n=1821）；bot 过层能力边界披露（F1 通过率 0% → 时长带维持用户自测口径）。
- **JSON↔md 一致性（本次脚本复算）**：`m4-balance-rerun.json` aggregate（runs 100/wins 0/deaths 94/stalls 6/residual_rate 0.06/f1_clear_rate 0/max_progress 3415·11房·49杀/时长中位 54.5s）与 md §2/§3 逐项一致；gems_curve 100 条带 batch 列。`m4-economy.json` points 三档（P1 18.391/3.561/2.455h；P2 null·13.5%/10.454h·55.9%/7.74h·82.1%；P3 24.5%/65.3%/93.9%）、revision 台账 5 条、curves 20h 值（悲观 2154.2/目标 11770/乐观 15318.2）与 md §4/§5/§6 表逐项一致；calibration 段（runs 100、kills 20.78、局终蓝晶 中位 0/均值 1.9/最大 25）与 md §3 一致。

## Check 7 — 成就口径 24/24 全激活：PASS

- `core/meta/achievement_system.gd` defs **24 条全部 `"active": true`**（grep 计数 24/24，0 条 false）。
- demolition（拆迁办）激活双半边：`:76` 行 active + gems 50；引擎阈值半边 `tests/unit/test_achievements.gd:147`（30 props 事件计数解锁）+ 接线半边 `tests/unit/test_destructible_props.gd:268-277`（破坏 → `notify_prop_destroyed` → 解锁全链路，断言注明「24/24 全激活口径」）。两套件均在 Check 1 全量绿内。
- 账目：M2 末 21/22 非试炼 + M3 试炼 2 条 = 23 → C-5 后 demolition 激活 = **24/24**（m4-c5-perf.md §机制摘要同口径）。

## Check 8 — 工作树/分支盘点：PASS

- 门禁起点 `git status` 干净：m4-gate worktree 仅 `art/fonts/*.ttf.import` + `icon.svg.import` 行尾噪音（M3 门禁同款豁免项）；main worktree 同款噪音豁免后干净。本门禁全部产出 = 本报告一份文件，无 core/、ui/、autoload/、data/、tools/ 触碰。
- merge 链完整（`git log --merges` 核对，70dd070=`m3` → 00bcce4 共 13 连，12 卡 + 1 微卡）：`6d3ce43` m4-a2 → `bee8087` m4-c1 → `390f930` m4-c2 → `7d0c40e` m4-k3 → `611cb7d` m4-a1 → `a0aca56` m4-c3 → `b216c2f` m4-k2 → `c6d03a3` m4-k1 → `62e89f8` m4-c4 → `40d0d13` m4-c5 → `49ae668` m4-wire（微卡：C-1 移交 4 特技敌接 F2 池）→ `9fabf21` m4-b3 → `00bcce4` m4-b4。计划 13 卡中 G-1 为本卡；TTK-R 为数据触发协议卡（非排期，见 §9）。

## §9 用户侧条件项盘点（不阻塞自动化判定，移交编排者/用户）

| # | 项 | 状态与出处 |
|---|---|---|
| 1 | LOGO 三变体定稿 | **待用户选定**：`art/generated/icon/logo_variants_preview.png` 并排预览 + variant_a_gate / variant_b_crystal / variant_c_knight ×3 已产出（K-1，`test_logo_variants.gd` 全绿）；选定后替换 icon.svg/config 为 5 分钟跟进，不阻塞 |
| 2 | Android 真机 60fps + 触屏全流程 | **诚实 SKIP（无设备）**：M3 X-B §9.1 移交延续，M4 未新增 Android 侧改动（K-1 etc2 正式化后 Windows 导出复跑双 PASS 为卡内证据）；有设备时按 M3 自测清单 ⑥ 执行 |
| 3 | TTK-R（A1 杂兵 TTK 校准） | **协议在案、等用户真人体感**：bot 100 局口径 A1 杂兵 TTK 中位 5.2s / P90 10.7s（m4-balance-rerun §4），仍出带（§14.3 ≤2.0s；各卡冒烟 4.2~5.4s 同带外方向）。按计划 TTK-R 协议：用户自测体感 + 死因分布到达 → 编排者提修订方案（幅度/影响面/bot 前后对照）→ 用户明示批准后立卡。**用户反馈到达前不动数值** |
| 4 | 单层/单局时长带 | **维持用户自测口径**：bot F1 通过率 0%（100 局，B-3 改进后仍 0%）＝能力结构性边界（M3-B2 终判既有裁定），时长带首次 bot 可评的条件未达成；真人数据为权威 |
| 5 | 角色购买流接线意向 | **B-4 经济 P1 意向台账**：角色解锁价/技能强化价无数据字段、无购买消费端（产品内全开放）；P1 主判出带 1.12x 收入需求在 ±20% 窗内但杆位在 run_state.gd/购买端（非数据修订窗口），处置 `intent_in_window` 交编排者裁定是否立功能卡 |
| 6 | 核显本真测 / 节流窗 60fps 静默会话复测 | M3 X-B §9.2/§9.3 移交延续，M4 无相关改动面，维持原口径 |

## §10 用户自测增补清单（M4 新增可玩内容 · 真人执行）

> 承接 M3 自测清单惯例（`m3-gate-user-checklist.md`）：严重度 **P0**=崩溃/卡死/无法推进、**P1**=功能坏了或明显伤手感、**P2**=观感/打磨。记录格式同 M3（现象 + HUD 种子 + 感觉三选一）。以下 8 项在 M3 清单 ①（完整通关一局）过程中顺路覆盖即可，建议 +10 分钟。

- [ ] **① 祭坛交互（C-4 新设施）**：战斗房约 15% 概率出现增益祭坛——走近按交互键弹出三选一增益（与层间三选一同池），选中即生效、不弹卡时观察是否与雕像/喷泉/商店同房挤出（互斥）。试炼局遇到 elite_surge 因子日时，祭坛交互改为**追加 1 精英**（不再弹三选一）——感受「更难但可玩」还是纯粹恶心（P1 起评）。
- [ ] **② 特技敌实战观感（C-1 ×11 + 微卡接线）**：F1 旧敌手感不变的前提下，F2 起留意新特技敌——硬壳龟缩壳（正面打不动→绕背）、荆棘炮台抛物弹（弧线可躲）、苔藓史莱姆水洼（敌提速/自己被减速）、种子投手落地生苗（苗不计入清房数）、磁石傀儡拉拽、冻土巨蟹钳击（有预警扇区）、窃晶鼠偷币（**死了会全额还币**）、深窟回响者模仿你的弹形、幽光水母电弧链、熔岩犬两段咬、火雨祭司火雨区。重点感受：每个特技**有没有预告、躲不躲得掉、混战里会不会恶心**（P1 起评；「看不出区别」记 P2）。
- [ ] **③ 暴击弹可视（A-1）**：暴击命中时弹体切换金色变体（玩家弹与敌弹两套都有）——一眼能分辨「这发暴击了」即过（P2）。
- [ ] **④ 伤害数字/FX 增亮（K-3）**：角色踩进 A2 光圈内时，伤害数字与粒子明显变亮、混战可读性提升；光圈外不异常增亮（P2）。
- [ ] **⑤ 英雄四被动体感（C-2，4 英雄各开一局打 1~2 层）**：法师·烬——法杖/激光弹伤害感知 +15%；守护者·萄——每进新层护盾回满、全伤害每层 +5% 最高 4 层；工程师·铆——开局自带 1 台便携炮台、每层补 1 台（与主动技能共库存上限 2）；刺客·蝉——近战击杀返 5 蓝 + 1s 内翻滚无 CD 连翻。任一被动「完全无感」或数值爆表记 P1。
- [ ] **⑥ hero_select 横滚（K-2）**：选角 6 卡横向滑动可滚到全部 6 张、轻点选中不误触、键盘/手柄左右导航到卡 5 后能回绕卡 0；无卡被截断在屏外（P1 起评）。
- [ ] **⑦ 版本号显示（K-1）**：主菜单 → 设置，面板底部一行 `v1.0.0 (100)` 显示完整不截断（P2）。
- [ ] **⑧ 暂停菜单回归抽查（M3 补卡回归）**：Esc/手柄 Start/右上钮呼出——继续/设置/重开/回主菜单四项照常、恢复无顿帧误震屏；呼出门控（三选一/Boss 死亡演出中）不误触发（P0 起评——回归类最优先报）。

---

## 移交编排者

1. **终裁 GREEN/RED 与 tag `m4`**：本报告自动化项全 PASS、无未披露孤儿，守卫侧建议 GREEN（附 §9 六项用户侧条件项，均不阻塞——其中 #3 TTK-R 与 #5 购买流为「等用户输入/裁定」型，#1 LOGO 为「选定后 5 分钟跟进」型）。
2. §9 #5 角色购买流：`intent_in_window` 意向是否立功能卡（B-4 台账：P1 主判出带但收入杆位 1.12x 在窗）。
3. §9 #3 TTK-R：用户自测体感到达后按协议提修订方案（重申：用户批准前不动数值）。
4. 本报告与 tag 后，M4 执行期全部报告（m4-c*/a*/k*/b*/wire + economy/balance-rerun）随链入档。
