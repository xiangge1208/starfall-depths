# Task 31（蓝晶结算 + 存档 migration v2）独立评审报告

- **被审对象：** 分支 `m2-t31`（worktree `D:\workspace\thomas\.worktrees\m2-t31`），交付 commit `65a4c27`（前置 wip `9927901` + merge main `7f96801`）
- **评审员：** 独立评审（只读代码；除本报告外未改动任何文件——复跑 `--import` 触碰的 `icon.svg.import` 已 `git checkout` 还原，工作树零漂移）
- **评审日期：** 2026-08-31
- **对照规格：** `docs/superpowers/plans/2026-08-30-m2-full-content.md` Task 31 卡（W10：蓝晶结算 + E-4 存档 migration v2）+ GDD §14（`docs/superpowers/specs/2026-08-28-starfall-depths-design.md`）

## 一、结论

**APPROVED（通过，附合并面预警）** —— 实现者自述**逐项核实全部属实**：存档 v2 纯增量迁移幂等、蓝晶击杀档位/死亡减半/胜利全额口径与 GDD §14 一致、半成品「进门全额入账」已正确回退、floor_scene 编译错误与真实 Boss 行覆盖缺口均已修复、Boss 首杀 +300 披露**有据**（出处见三-6，注意原文在设计稿而非数据表附录）。实测 **1117/1117 全绿**（66/66 套件，0 失败/0 错误/0 flaky/0 跳过），与自报 1097+20=1117 精确吻合。无 Critical/Important 发现；Minor 6 项（含 2 项前瞻性口径注记）。**合并面有 2 个已实证的冲突点**（prophet 静态重复 `add_gems` 会无声产出编译错误、T32 与本卡同改 SAVE_VERSION 行），已在第五节标注并集解法，供合并协调人执行——不构成本卡扣分。

## 二、验证环境与实测

| 项 | 命令 | 结果 |
|---|---|---|
| PIL 前置 | `python -c "import PIL"` | OK |
| 导入 | `godot --headless --path . --import` | exit 0，无错误 |
| 全量测试 | `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode` | **1117/1117 通过**（Overall Summary：1117 test cases，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans；66/66 套件；53s 380ms；exit 0） |
| 新增测试清点 | wip+final 两 commit 的 `func test_` 增删 diff | 净 +20（wip +10，final +13/−3），与自报分项**逐一吻合**：save v2×5、boss 名录×4、run_state×5、codex 持久化×4、floor_scene 路由×1、胜利含击杀蓝晶×1 |
| v1 旧档手验 | `test_v1_save_migrates_to_v2_preserving_all_fields`（构造覆盖全部 7 个 v1 键的旧档） | gems=77 / heroes×2 / talents / weapons / achievements / boss_first_kills / settings 全保留，`unlock_tasks` 默认空，版本戳盖 2 —— 断言为真比对，非桩 |

## 三、规格符合度（逐项）

| # | 规格项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 层通过 +[60,120,200] 既有口径未动 | **PASS** | `git diff main..m2-t31 -- autoload/run_state.gd` 对 `next_floor`/`settle_death_gems` **零触碰**（净增仅 KILL_GEMS/BOSS_FIRST_KILL_GEMS 常量 + `add_gems`/`settle_kill_gems` 两方法）；`test_next_floor_returns_new_index_and_gems_boundaries` 改为相对基线断言（g0+60/180/380/580），边界与 clamp 语义不变 |
| 2 | 击杀档位：精英+5 / 小Boss+20 / Boss+50 | **PASS** | `run_state.gd:37` `KILL_GEMS`；档位识别 = 敌行 `guest_kind`（A1 嘉宾三档，`floor_scene.gd:947` 写入）+ **boss_script 兜底**（`floor_scene.gd:1002-1004`：guest_kind 空且 `boss_script` 非空 → 归 boss 档，口径镜像 `room_combat.gd:293 kill_source`）。全部 5 条真实 Boss 行（enemies.json:48-52）都有 `boss_script`，覆盖成立；杂兵两键皆空 = 0 |
| 3 | 死亡减半 / 胜利全额 / 防双入账 | **PASS** | 死亡 `settle_death_gems`（floor 半除+归零，`run_state.gd:102-105`）+ `_confirmed` 守卫（`death_summary.gd:130-133`）；胜利面板直读 `RunState.gems` 全额+归零（`victory_summary.gd:91-94`）。数学有真断言：`test_death_settlement_halves_pool_with_kill_gems`（过层60+击杀5+50=115→57，二次结算=0）、`test_confirm_awards_kill_gems_full_amount`（5+20=25 全额）、既有 `test_victory_full_amount_contrasts_death_half`。入档单点：全库仅 death/victory 两面板调 `SaveSystem.add_gems(局内池)`（天赋购买走 `SaveSystem.add_gems(-cost)` 是局外余额，不相干） |
| 4 | 存档 v2：SAVE_VERSION=2、v1→v2 纯增量、字段全保留 | **PASS** | `save_system.gd:19,140-143`；`_migrate` v1→v2 为显式 no-op（additive 无搬移），`_merge_saved` 默认骨架回落 `unlock_tasks`/`boss_first_kills`；手验见表二 |
| 5 | 幂等（v2 二次载入零迁移） | **PASS** | `load_save:76-78` 仅 `from_version < SAVE_VERSION` 进 `_migrate`；`test_migration_v2_idempotent_double_load`（二次载入数组不翻倍、字段不丢）+ `test_migration_v2_no_replay_for_v2_save`（SpySaver `migrate_call_count==0`）双面钉死 |
| 6 | Boss 首杀 +300 披露查证 | **PASS（出处勘正）** | 原文在 `docs/superpowers/specs/2026-08-28-starfall-depths-design.md:254`（§14.1 货币）：「蓝晶（局外）：每层通过 +60/120/200，**Boss 首杀 +300**，成就 +50~500，试炼模式 ×1.5。死亡也保留 50%」。注意：数据表附录 `...data-tables.md` 无 §14（仅附录 A-H，附录 H 只有「层通过蓝晶 60/120/200」一行）——任务书给的查证文件有误，**设计稿 §14 才是真出处**，披露内容本身属实，不构成 Important |
| 7 | `boss_slain` 信号不存在（自述核实项） | **PASS** | `grep -rn boss_slain --include=*.gd` 零命中（exit 1）；挂 `FloorScene._on_enemy_died` 是卡面允许的等价单点路径 |
| 8 | 抢救决策：回退「进门全额入账」 | **PASS** | wip `9927901` 的 `_bank_pending_gems`（进门全额入档+清池）在 `65a4c27` 已删净（`run_state.gd` 现无此函数）；回退理由成立——GDD §14「死亡也保留 50%」作用于本局全部待结算蓝晶，进门入账会使已过层蓝晶免疫死亡折半，违反口径 |
| 9 | 抢救决策：修复 wip 编译错误 | **PASS** | wip `floor_scene.gd` 在 `var enemy_id := ...` 声明前一行调用 `settle_kill_gems(..., enemy_id)`（GDScript 同块先用后声明=编译错误）；final 已把声明上移（`floor_scene.gd:996`） |
| 10 | 抢救决策：真实 Boss 行 0 蓝晶缺口 | **PASS** | wip 只传裸 `guest_kind` → gem_queen/prism_golem/frost_widow/magma_tyrant（无 guest_kind）得 0；final 补 `boss_script` 兜底，`test_scene_kill_gem_routing_guest_and_boss_script_rows` 真场景端到端覆盖（嘉宾 50+300 → frost_widow 50+300 → 杂兵 0，含临时档重定向守卫） |
| 11 | CodexSystem 计数器经 `record_unlock_tasks`/`unlock_tasks` 读写，三个落盘点 | **PASS** | 写：`codex_system.gd:263`（层进入，挂 `run_root.gd:191`）、`:203`（解锁达成搭车）、`death_summary.gd:139`/`victory_summary.gd:97`（终局确认）；读：`_init` 注入即恢复 + `_ready` autoload 探测恢复（`:48,54`）。autoload 顺序 SaveSystem(project.godot:24) 先于 CodexSystem(:30)，读档时序正确 |
| 12 | `floor_clears` JSON 字符串键归一化回 int | **PASS** | `_normalize_unlock_tasks`（`save_system.gd:149-165`）：标量 float→int、分桶键 `int(fk)`、脏键 fail-SOFT 回落；`test_unlock_tasks_progress_roundtrip` 钉死往返，`..._dirty_save_filtered` 钉死脏档 |
| 13 | T24 移交：run_seed 入 `_saved_run` 快照 | **PASS** | `test_death_recorder.gd:33,51`（测试夹具跨用例保真，防 run_seed 泄漏） |

## 四、质量发现

### Critical / Important

无。

### Minor（6 项）

**m-1 首杀标记即时落盘 vs +300 留池：异常退出永久损失首杀奖励**
`run_state.gd:122-129`：Boss 首杀时 `record_boss_first_kill` **立即写盘**（`save_system.gd:274-281` 含 `save_now`），但 +300 进入本局待结算池，仅在死亡/胜利面板确认时入账。若进程在局中崩溃/被杀（未走终局面板），标记已持久而蓝晶全损——该 Boss 的 +300 此后无法再获得。死亡折半的交互已披露，崩溃损失这半边未披露。属 fail-SOFT 设计取舍（标记先行是防死亡重试重刷的必要代价），建议在 T33 门禁口径里记一笔即可。

**m-2 精英/小Boss 档位识别仅覆盖 A1 嘉宾路径（前瞻）**
`guest_kind` 只有 `floor_scene.gd:947`（A1 占位嘉宾）一个生产者；真实敌行（enemies.json 51 行）无 elite/miniboss 字段，B.3 小 Boss 池（6 行）尚未落地。当前游戏内容下无实际缺口（A1 嘉宾三档 + 5 真实 Boss 全覆盖），但 A2/A3 精英/小 Boss 内容卡（T26 房型复核等）接入时若沿用数据行直生成，击杀蓝晶将静默得 0——届时需数据字段约定（如 `tier` 列）或生成侧补 `guest_kind`。建议移交清单记录。

**m-3 注释不精确：vine_colossus 被列为「只有 boss_script 无 guest_kind」**
`floor_scene.gd:999-1000`。实际 vine_colossus 作 A1 嘉宾生成时**两个键都有**（`floor_scene.gd:947` 会写入 `guest_kind="boss"`）；作数据行直生成时才只有 `boss_script`。两条路径都归 boss 档、行为无差，纯注释措辞问题。

**m-4 `unlock_tasks()` 返回活引用**
`save_system.gd:285-289` 直接返回 `data["unlock_tasks"]` 字典本体（非 duplicate），调用方误改会静默污染档内视图。与既有 `achievements` 的口径一致（历史习语），当前唯一调用方 `codex_system.gd:_restore_counters` 只读，风险低。仅记录。

**m-5 层进入落盘为无条件写**
`codex_system.gd:263`：`on_floor_entered` 每次必 `persist_counters()`（即使计数零变化），解锁达成的同一调用还会经 `check_unlocks:203` 再写一次（同帧双写）。每层一次的 IO 量级可忽略，非热路径（击杀路径 `settle_kill_gems` 杂兵 0 档位零 IO），仅记录。

**m-6 `gems_earned_total` 不含击杀/首杀蓝晶（跨卡依赖，已披露）**
`codex_system.gd:17-18,241`：J.2 口径下 collect_gems_x 只计过层蓝晶，击杀/首杀/成就蓝晶归 T32/T33 补 `count_gems` 调用。本卡未越权扩口径（正确），但合并 T32 后需记得回补，否则图鉴「累计获得蓝晶」目标永久低估。

### 质量正面确认

- **复用而非第二套**：CodexSystem 持久化完全经 SaveSystem 新访问器（`record_unlock_tasks`/`unlock_tasks`），无平行存储；T15 `record_talent_purchase`、T20 `unlock_weapon` 路径零改动零旁路；T32 的 achievements 归一化与本卡 `unlock_tasks` 归一化互不侵入（同函数不同键，见第五节并集解法）。
- **盐/确定性**：本卡零新 RNG 消耗（档位纯常量表），不触盐流；`record_boss_first_kill` 的写盘时序不影响任何随机序列。
- **.uid**：commit 15 文件全为 M 无 A（`git show --name-status` 证实），无新脚本 → 无 .uid 需求。
- **中英文**：注释中文、测试名英文，符合仓库既有规范；无新增玩家可见字符串（面板文案未动）。
- **测试真断言**：幂等（双载入 + spy 计数双面）、减半数学（115→57、7→3 对照）、往返（int 键归一化）、路由（真场景 take_hit 击杀）均为行为断言，非桩非 tautology；`test_floor_scene.gd` 新用例带临时档重定向 + 还原 + 清理，不触真实 user://save.json。

## 五、合并面预警（只标注，供合并协调人执行）

用 `git merge-tree --write-tree`（只读模拟）实证两处：

**P-1（高危：无声编译错误）m2-prophet 静态重复 `add_gems`**
模拟合并 m2-t31 × m2-prophet：git 报 **0 冲突**，但合并树 `autoload/run_state.gd` 同时含**两个** `func add_gems`（第 116 行=T31 版、第 139 行=prophet 版，插入位置不同所以 git 自动并收）→ GDScript「函数重复声明」编译错误，**测试套件会当场炸**。另 prophet 在 `_on_enemy_died` 的 `counts_for_wave` 早退块与函数尾部挂隐藏门（`_maybe_open_starfall_gate`），与本卡头部改动同函数不同区段，文本可自动合并、语义独立。
**并集解法**：合并时二选一保留单个 `add_gems`（建议留 T31 位置与注释，prophet 的 gem 拾取语义不变——池累积+终局结算恰好覆盖 prophet 注释里「过层全额入账」的旧说法，顺手把该注释口径更新为「终局死亡减半/胜利全额」）；`starfall_prophet` 数据行带 `boss_script`，并集后自动落 boss 档 +50 与首杀 +300，与其自带 gems3 掉落叠加，无需额外接线。

**P-2（中危：文本冲突）m2-t32 与本卡同改 save_system.gd 版本区**
模拟合并 m2-t31 × m2-t32：**CONFLICT** 于 `autoload/save_system.gd` 与 `tests/unit/test_save.gd`。冲突点：① `SAVE_VERSION := 2` 同行不同注释（T31：unlock_tasks/boss_first_kills 正式化；T32：achievements 字段正式化）；② `_merge_saved` 内 T31 在 weapons 与 achievements 之间插入 `unlock_tasks` 归一化、T32 重写 achievements 块（值归一 true）；③ test_save.gd 5 处版本断言同行不同尾注。
**并集解法**：单一 `const SAVE_VERSION := 2` + 合并双理由注释；`_merge_saved` 同时保留 `unlock_tasks` 归一化（T31）与 achievements 值归一（T32）——两键独立、无交叉；`_migrate` 保留 T31 的 `if from_version < 2: pass` 分支骨架（T32 透传版是其子集）；测试断言统一 `is_equal(2)`。并集后 v1 旧档一次迁移同时获得两卡语义，幂等性不受影响（两卡都只靠 load_save 的版本门）。

## 六、结论

**APPROVED**。规格 13 项核对全 PASS（含自述五大抢救/披露项逐条实证），质量无 Critical/Important，Minor 6 项（m-1 崩溃损失披露缺口、m-2 前瞻档位覆盖、其余为注记级）。实测 1117/1117 全绿。合并前必须处理第五节 P-1（prophet 重复 `add_gems` 是无声编译炸弹）与 P-2（T32 版本区冲突），解法均为机械并集，已给出。
