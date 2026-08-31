# Task 32 评审报告：成就系统 22 激活（分支 m2-t32）

- **被审对象**：`.worktrees/m2-t32`，提交 `e18f3be` `feat(m2-t32): achievement system (22 active)`（基线含 salvage 提交 `b1527b9` + main 合并 `2260796`；分支全量 diff = 10 文件 +1222/-10）
- **评审员**：独立评审（只读；除本报告外未修改任何文件）
- **评审日期**：2026-08-31
- **规格唯一出处**：`docs/superpowers/specs/数据表附录-K-成就接线.md`（K.1–K.5）+ `2026-08-28-starfall-depths-data-tables.md` 附录 G.1
- **测试实测**：`python -c "import PIL"` 通过（Pillow 12.3.0）→ `godot --headless --import` 通过 → GdUnit4 全量 **1131/1131 通过**（61 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans）——与实现者自报 1097+34=1131 一致，其中 `test_achievements.gd` 单套件 34 用例全绿

---

## 一、结论

# APPROVED

24 条判定器与附录 K 全表逐字段一致（全量比对，非抽样）；M2 22 条蓝晶合计 4050 独立复算吻合并被 schema 测试钉死；2 条试炼 M3 三重守卫拒解锁；17 条待发射成就缺信号/缺数据源路径全部 fail-closed（不误解锁、不崩溃，逐类抽验 + 测试实证）；自述的 5 项半成品修复全部属实且在 wip 基线上有可复算的 RED 证据；两项披露（shop_purchase 无消费方、SAVE_VERSION 撞号 T31）核实为真且并集可解。发现 0 Critical / 0 Important / 5 Minor（均为协调面与热路径微开销，不阻塞合并）。

---

## 二、规格符合度（附录 K 逐条，全量 24/24 比对）

评审员从附录 K.3 原文独立录入 24 条（id/中文名/条件/蓝晶/批次/触发/判定式），与 `core/meta/achievement_system.gd:55-133` DEFS 表逐字段比对——**非抽样，24/24 全部一致**。抽查展示 12 条代表：

| # | id | 名称 | K 蓝晶 | 实测 | K 判定式 | 实测 | 结果 |
|---|---|---|---|---|---|---|---|
| 1 | first_lamp | 初次点灯 | 100 | 100 | `floor_idx == 1` | pred 同 | PASS |
| 2 | delver | 深入者 | 150 | 150 | `floor_idx >= 3` | pred 同 | PASS |
| 5 | forge_smith | 熔铸匠 | 100 | 100 | `counters.crafts_total >= 10` | `counter:crafts_total` goal 10 | PASS |
| 7 | deadeye | 弹无虚发 | 100 | 100 | `crits/shots > 0.35 && shots >= 50` | 交叉乘 `crits*100 > 35*shots` + `shots >= 50` | PASS |
| 9 | collector | 藏品家 | 150 | 150 | `codex_seen size >= 50` | `save:codex_seen` goal 50 | PASS |
| 13 | speedrunner | 速通者 | 150 | 150 | `run_time_frames < 72000` | `run:run_time_frames` op `<` 72000 | PASS |
| 14 | moneybags | 财神 | 100 | 100 | `floor_idx==1 && coins > 500` | pred + `run:coins > 500` | PASS |
| 15 | nitpicker | 鸡蛋里挑骨头 | 100 | 100 | `floor_idx==1 && category=="throw"` | pred + `sig:weapon_category == "throw"` | PASS |
| 17 | dodge_master | 走位大师 | 100 | 100 | 会话计数 `>= 100` | counter dodges goal 100 | PASS |
| 20 | nightmare_dawn | 噩梦黎明 | 300 | 300 | `floor_idx==3 && deaths==0` | pred + `session:deaths==0` | PASS |
| 21 | trier | 试炼者 | 100 **M3** | 100, `active:false` | `trials_total >= 1` | 判定器在表但不接线 | PASS |
| 24 | overflowing | 满溢之光 | 500 | 500 | `purchased_talents size >= 24` | `save:purchased_talents` goal 24 | PASS |

其余 12 条（night_watcher/element_scholar/bare_hands/slum_king/grand_collector/full_roster/flawless_elite/demolition/no_heal/challenger/trial_master/gifted）同样逐字段一致。判定数据夹具独立核验：`data/enemies.json` `shuangdao_lizardman.elite_affixes=["swift","berserk"]` 非空、`kuli_bug` 无该键；`tiejian→melee`、`shoulei→throw`、`laohuoji→pistol`；weapons.json 恰 115 把。

- **蓝晶合计复算**：M2 22 条 = 100×8 + 150×5 + 300×2 + 200×2 + 500×2 + 400 + 50×2 = **4050**，与附录 K.3 注（勘误口径）及 DEFS 表逐条求和一致；`test_defs_ids_unique_schema_and_gem_total_4050`（test_achievements.gd:83-98）以测试钉死。
- **M3 试炼拒解锁**：三重守卫——`_route` 跳过 `active:false`（achievement_system.gd:265）、`recheck` 跳过（:384）、`_unlock` 拒绝（:364）；且无任何 trigger 挂 `trial_completed`。`test_trial_achievements_not_unlockable_in_m2` 直调 `_unlock("trier"/"trial_master")` 实证拒绝入档、零蓝晶。
- **四类判定器**：event_once×3 / event_count×3 / state_threshold×8 / composite×10，与 K.3 触发/判定数据一一对应；每类均有专属测试组。
- **K.1 混合判定**：事件驱动（信号到达即判）+ 结算点轮询（`recheck()` 扫 state_threshold，挂 codex 解锁点与 item_forged/hero/talent/challenge 通知点）符合契约。
- **解锁链**：`_unlock` → `SaveSystem.unlock_achievement`（幂等，save_system.gd:220-230）→ `add_gems` → `achievement_unlocked` 信号 → toast（achievement_system.gd:360-371），顺序与 K.1 一致；重复事件不重复入账有测试（:388-403）。

---

## 三、fail-safe 正确性（17 条待发射成就逐类抽验）

当前实时激活路径核实：EventBus 既有 5 路订阅（resonance_triggered/enemy_damaged/enemy_killed/player_hit_resolved/room_cleared，签名与 `autoload/event_bus.gd` 逐一比对一致）+ CodexSystem.weapon_unlocked → recheck。实时可达 5 条（元素学者/弹无虚发/无伤精英 + 藏品家/大收藏家的触发路径），其余 17 条判定引擎就绪、发射点按文件边界推迟 T35——与自述一致。

| 缺席路径 | 保守分支 | 证据 |
|---|---|---|
| `counters` 键缺席（T25 v2 前） | 占位 0 → forge_smith/challenger 不可达 | `_state_value` :422-426 + 测试 :223-233（含落键后可达的正例） |
| `codex_seen` 键缺席 | 回落 `unlocked_weapons().size()`（任务解锁 ⊆ 已见，保守低估） | :402-410 + 测试 :191-203；键在场即切权威口径有专项测试 :206-220 |
| boss_slain 带未知武器（`weapon_id=""`） | cat="" → 字符串比较 fail-closed 不解锁；`if weapon_id != ""` 守卫避免无谓查表 | :435-440 + 测试 cs4 :369 |
| 未知 enemy_id | `GameDB.enemies.get(id,{})` → elite_affixes 空 → is_elite=0 | :503-506；`get_weapon` 对未知 id 返回 `{}` 非 null（game_db.gd:215-219），`.get("category","")` 无崩溃面 |
| 未知 op / 字符串配非等值 op | COND_OPS 白名单外 return false；字符串仅 ==/!=，其余 fail-closed | :310-317 |
| save 缺席（直构未注入） | `is_unlocked`/`_unlock`/`recheck` 全部前置判空返回 | :186-189, :361-362, :378-379 |

- **shop_purchase 复核**：附录 K.2 明示该信号为 T20 buy_x 计数源、发射归 T35 接线卡；K.3 全表 24 条触发信号清单（boss_slain/floor_reached/victory_achieved/resonance_triggered/item_forged/floor_cleared/enemy_damaged/weapon_unlocked/hero_unlocked/enemy_killed/prop_destroyed/roll_dodge/challenge_cleared/talent_purchased/trial_completed）确无 shop_purchase 消费方；代码中亦无 `notify_shop_purchase` 死 API。自述属实。
- **精英口径**：`is_elite` = DB 行 `elite_affixes` 非空，与 `core/enemies/enemy_base.gd:47,53`（引擎自身判定精英的同一表达式）同权威，非另造口径。

---

## 四、半成品修复复核（RED 证据 + T31 衔接点）

对照 wip 基线 `b1527b9` → `e18f3be` 全量 diff，逐项核实：

1. **int 强转恒真（属实，实现 bug，wip 测试可复算 RED）**：wip `_cond_met` 先 `var value := int(cond.get("value", 0))` 再 `_cmp(_src_value(...), op, value)`——nitpicker 条件下 `int("pistol")==int("throw")==0` 恒真，任意 A1 Boss 击杀即误解锁；wip 测试 `notify_boss_slain("vine_colossus", 1, REMOTE_ID)` 断言 `is_false` 必然失败（RED）。修复为字符串值走 `_src_text` type-strict 分支（仅 TYPE_STRING 通过，类型不符/源缺席 → ""），且仅允许 ==/!=（:312-318, :332-342）。修复后测试转 GREEN。
2. **deadeye 分母（属实，测试数学 bug）**：wip 测试 50 非暴击 + 17+1 暴击 = 68 发 18 暴（26.5%），注释却按 17/50、18/50 计算，`is_true` 断言必然失败。修复后 32+17+1 = 50 发 18 暴 = 36% > 35%，另补 50 发 17 暴 = 34% 严格不达的边界用例（:251-260）。
3. **dodge_master 独立计数（属实，测试数学 bug）**：wip 实现的 `dodges`/`props` 本就是独立计数器（wip `_absorb` 已逐键累加），wip 测试却按 30 props + 70 dodges 凑 100——dodges 止步 70 < 100，`is_true` 必然失败。修复为 99 不达 / 第 100 次达成的边界断言。
4. **6+ 用例同触发共判定隔离（属实）**：victory/floor_cleared/boss_slain 是多成就共享触发点。wip 速通者用例在全新实例上断言 `notify_victory()==false`，但守夜人（无条件的 event_once）同触发必解锁使返回值为 true——必然失败。修复后逐用例显式破掉邻居条件（拾红心/钉 72000 边界/预解锁 first_lamp/金币钉 0）并把共解锁计入 gems 精确断言（如 speedrunner 300→450）。
5. **collector/grand_collector 数据源改 codex_seen + 回落（属实）**：wip 用 `save:unlocked_weapons`，修复后 `save:codex_seen` + 键缺席回落 unlocked_weapons 子集。
6. **toast.tscn 补齐（属实）**：wip 只有 `load(TOAST_SCRIPT).new()`；修复后 TOAST_SCENE 优先、`packed is PackedScene` 判型失败回落脚本直构（headless 兜底），并有场景实例化专项测试。
7. **API bool 化（属实）**：notify_* 全部 `_notify_and_report`/`_recheck_and_report` 返回本次是否新解锁。

**T31 衔接点核查（重要事实澄清）**：m2-t31 分支的 `record_unlock_tasks` 快照 = `CodexSystem.snapshot_counters()` = `counters.duplicate(true)`（六类标量计数 + floor_clears 分桶，m2-t31 core/meta/codex_system.gd:177-178）——**不含 codex_seen 或等价已见集合键**；且 m2-t20 / m2-t25 / m2-t31 / main 四分支 grep 均**无人写 codex_seen**。因此「T31 合并后自动切权威」不成立：T31 合并后回落口径仍生效（继续保守低估）。`_state_value` 的切换条件是「存档 `data["codex_seen"]` 键在场」（:403-410），该键的写入方按 K.5 标注为 T20（现未落）——衔接点为 **T25 v2 counters/codex_seen 落键卡或 T20 后续补写**，届时无需改本文件即自动切换。当前回落上限 = unlocked_weapons 至多 49 < 50，藏品家/大收藏家在写键方落地前事实不可达（fail-safe，不误解锁），建议编排者在 T35/T25 简报中把这两条一并列出发射/数据源双缺口，见 Minor ③。

---

## 五、质量发现

**PASS 项**：autoload 注册于 CodexSystem 之后（project.godot 第 12 位，SaveSystem/CodexSystem 均在前，`_ready` 探测 /root/* 与订阅 weapon_unlocked 时序安全）；toast 场景实例化兜底完备；三个新文件 .uid 齐全且 uid 无冲突（toast.tscn 内嵌 uid 与 toast.gd.uid 引用一致）；中文文案符合 GDD §17（「成就解锁：xxx +N 蓝晶」右下角、3s+0.5s 淡出、同屏 3 条挤老）；save_system.gd 改动最小（achievements id→true 归一 + 三访问器 + v2 版本戳，v1 档迁移有测试）；测试真断言（72000 严格 <、501 vs 500、99/100、34%/36% 交叉乘、挤序 contains_exactly、gems 精确累计、跨档 roundtrip）。

**Minor（5 项，均不阻塞）**：

1. **Minor ①｜热路径分配**：`enemy_damaged` 每次命中经 `_notify_and_report` 前后各构建一次 `unlocked_achievements()` 数组（两次字典遍历 + Array[String] 分配/次），战斗高频路径有不必要开销。 Roguelike 量级可承受，T35 接线时可改为比较路由 id 的解锁态或维护计数。`core/meta/achievement_system.gd:520-523`。
2. **Minor ②｜deadeye「射击」口径**：分母 = 每次有效命中（amount>0）计 1，穿透/多段武器会放大分母使 >35% 更难；K.2 已明示「复用 enemy_damaged(is_crit) 聚合」为合法口径，属规格容忍的近似，提请 T35 接线时知悉。`:230-234`。
3. **Minor ③｜「实时激活 5 条」口径偏差**：藏品家/大收藏家的触发路径（weapon_unlocked→recheck）确已激活，但数据源（codex_seen 回落上限 49）在写键方落地前永远够不到 50/115 阈值——事实效果与另外 17 条同为休眠。不误解锁（fail-safe 方向正确），但移交清单宜将其标注为「触发就绪 + 数据源待 T25/T20」。`:392-410`。
4. **Minor ④｜reset_session 无运行时调用方**：单局清零按计划挂 DeathRecorder.reset/T35 生命周期，当前无调用点——T35 落地前长驻进程内单局计数跨局累计（如元素学者 30 次共鸣可能跨两局凑满）。已在头注释披露为移交项，非本卡缺陷。`:198-214`。
5. **Minor ⑤｜SAVE_VERSION=2 与 T31 撞号**：m2-t31:autoload/save_system.gd:19 同为 `SAVE_VERSION := 2`，双方 v2 载荷不同（T31：unlock_tasks + boss_first_kills；T32：achievements 归一）。核实两分支的 `_merge_saved` 增量均为逐键 additive 且互不重叠，文本冲突仅限常量声明与注释——「同值并集可解」的自述成立，合并时取并集即可；建议合并者在合并提交中显式注明 v2 = 两卡载荷之并。

---

## 六、测试复跑记录

- 环境：Godot 4.7.2.stable.official.ed1daf0bf，win32；Pillow 12.3.0 就绪。
- `godot --headless --path . --import`：exit 0。
- `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`：exit 0，**Overall Summary: 1131 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans，Executed (1131/1131)**，61 套件；`test_achievements.gd` 34 用例全绿（自报 34 新增吻合），`test_save.gd` 3 处版本戳断言更新（1→2）后全绿。
- 退出尾行 `ERROR: 1 resources still in use at exit` 为引擎退出期资源持有提示，全绿前提下不影响判定（与本仓库历次全量跑一致现象）。

---

## 七、结论重申

**APPROVED**。可合并；5 项 Minor 中 ③④⑤ 属编排协调面（移交 T35/T25/合并人），①② 可在 T35 接线时顺手处理，均不要求本卡返工。
