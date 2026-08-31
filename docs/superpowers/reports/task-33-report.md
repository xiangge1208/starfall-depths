# Task 33 报告：门禁预检（分支 m2-t33，基线 main `7320cb6`）

- **执行者**：T33 预检代理（TDD 全程）
- **日期**：2026-08-31
- **范围**：裁定㉗① 17 条成就发射点审计与补线 ＋ 裁定㉔② save_headless 套件密闭（含清档全量复跑）＋ M1 补录 ③④ 核销 ＋ T36 Minor ①②③⑤ / T35 Minor ④⑤⑥ 微修 ＋ 移交表逐项复核
- **测试环境**：Godot 4.7.2 headless，gdUnit 6.2.1，Pillow 12.3.0 就绪（`python -c "import PIL"` 通过）

---

## 一、结论速览

| 项 | 结果 |
|---|---|
| 成就 22 条激活口径 | **21/22 链路完整**（5 条补线前已活 + 16 条本次新接线），**1 条 blocked**（demolition，机制不存在），2 条试炼 M3 不计 |
| save_headless 密闭 | TestSaveSeal 共享档密闭器 + 6 套件逐用例接入；脏档（合成极限污染）全量复跑证据在案 |
| 清档全量复跑（裁定㉔②） | 清 user:// 存档 → 全量 **1368/1368 绿（76 套件）**，无「纯净引导」假设残留 |
| M1 补录 ③ | 死亡确认输入锁已实现（0.5s/30t 吞键吞点击）＋ 3 测试 |
| M1 补录 ④ | 核验结论：**无缺口**（T24 实现已覆盖，telemetry CSV 追加不截断；详见 §四） |
| 微修清单 | T36 ①②③⑤ + T35 ④⑤⑥ 全部落地（file:line 见 §五） |
| 移交复核 | 8 派味特技 **0/8 已实现**（数据行齐全，行为未建，M3/后续清单）；spare_parts/echo/blessing 为英雄被动 data-only，**不在 T35 25 增益键范围内**，M3 承接（详见 §六） |

---

## 二、裁定㉗①：22 条成就发射点审计与补线

### 2.1 审计方法

- 权威对齐：`docs/superpowers/specs/数据表附录-K-成就接线.md`（K.2 信号清单 / K.3 全表）＋ 台账裁定⑧（`boss_slain(boss_id, floor_idx)` 命名；buy_x 计数源 = T35 `shop_purchase(kind)`）。
- 消费侧：T32 的 `core/meta/achievement_system.gd` 判定引擎（notify_* 直调 API ＋ `_ready` 的 EventBus 既有 5 路订阅 ＋ CodexSystem.weapon_unlocked 轮询）——审计确认消费侧全部就绪，**缺口全部在发射侧/数据源侧**。
- 发射侧：全仓 grep `AchievementSystem.` / `notify_` 证实补线前游戏代码**零调用点**（台账「T35 行旧备注」确系简写失实，评审披露属实）。

### 2.2 审计总表（22 条 M2 激活 + 2 条 M3）

| # | id | 触发信号 | 发射点（补线前 → 补线后） | 消费点 | 状态 |
|---|---|---|---|---|---|
| 1 | first_lamp | boss_slain | **无** → `floor_scene.gd:1202`（boss 房清，携路由后行 id + 层号 + 击杀武器） | notify_boss_slain → event_once(pred floor==1) | **新接线 ✅** |
| 2 | delver | floor_reached | **无** → `run_root.gd:226`（过层门，抵达层号） | notify_floor_reached → event_once(floor>=3) | **新接线 ✅** |
| 3 | night_watcher | victory | **无** → `run_root.gd:175`（flow.victory_achieved 桥接） | notify_victory → event_once | **新接线 ✅** |
| 4 | element_scholar | resonance_triggered | `enemy_base.gd:302`（既有） | EventBus 订阅（既有） | 补线前已活 ✅ |
| 5 | forge_smith | item_forged + crafts_total≥10 | **无** → `ui/forge.gd:111`（熔铸成交点）；**数据半边修复**：`_state_value` counter: 权威改读 CodexSystem 活计数器（原读 save.data["counters"] 恒 0 不可达） | notify_item_forged → recheck（crafts_total goal 10） | **新接线 ✅（含数据源修复）** |
| 6 | bare_hands | floor_cleared + 开火窗口 | **无** → `player_driver.gd:72-75`（`_log_fire` 汇口：近战挥击/远程开火成功点）＋ `run_root.gd:225`（本层窗口先判后清） | notify_weapon_used + notify_floor_cleared → composite | **新接线 ✅** |
| 7 | deadeye | enemy_damaged | `enemy_base.gd:135` / `boss_base.gd:59`（既有） | EventBus 订阅（既有） | 补线前已活 ✅ |
| 8 | slum_king | floor_cleared(pred 1) + deaths==0 | **无** → `run_root.gd:225` | 同上 | **新接线 ✅** |
| 9 | collector | weapon_unlocked（轮询） | CodexSystem（T20 既有） | codex.weapon_unlocked → recheck（既有） | 触发已活；**数据源缺口**（codex_seen 无写入方，回落上限 49<50；K.5 写入方 T20 未落，见 §2.4） |
| 10 | grand_collector | 同上 | 同上 | 同上 | 同上 |
| 11 | full_roster | hero_unlocked | **无** → `save_system.gd:228`（K.2 指定发射点 = unlock_hero 成功点） | notify_hero_unlocked → recheck(unlocked_heroes>=6) | **新接线 ✅**（链路完整；M2 无玩法调用 unlock_hero，事件暂休眠，见 §2.4） |
| 12 | flawless_elite | enemy_killed + is_elite + 受击窗 | `enemy_base.gd:159`（既有）＋ room_cleared 窗口重置（既有） | EventBus 订阅（既有） | 补线前已活 ✅ |
| 13 | speedrunner | victory + run_time_frames<72000 | **无** → `run_root.gd:175` | notify_victory → composite(run:run_time_frames) | **新接线 ✅** |
| 14 | moneybags | floor_cleared(pred 1) + coins>500 | **无** → `run_root.gd:225` | notify_floor_cleared → composite(run:coins) | **新接线 ✅** |
| 15 | nitpicker | boss_slain + weapon_category==throw | **无** → `floor_scene.gd:1202`（击杀武器 = `_current_weapon_id()`，与 kill 行 source 同口径） | notify_boss_slain → composite(sig:weapon_category) | **新接线 ✅** |
| 16 | demolition | prop_destroyed | **不可接线**：可破坏物机制不存在（`_build_props` 全为静态 solid/vis，无破坏路径、无伤害入口） | 判定器在表，无事件流 | **BLOCKED**（见 §2.4） |
| 17 | dodge_master | roll_dodge≥100 | **无** → `player.gd:305`（翻滚无敌帧内躲过 source_type=="projectile" 计数；接触/状态/受击 iframe 不计——K.3「躲弹幕」口径） | notify_roll_dodge → event_count | **新接线 ✅** |
| 18 | no_heal | victory + heart_pickups==0 | **无** → `run_root.gd:175` ＋ `pickup.gd:56`（heart 拾取点） | notify_victory/heart_pickup → composite | **新接线 ✅** |
| 19 | challenger | challenge_cleared + challenge_rooms_total≥5 | **无** → `floor_scene.gd:1190-1191`（挑战房清点：新 `CodexSystem.count_challenge()` 持久计数 ＋ notify） | notify_challenge_cleared → recheck(counter 活值) | **新接线 ✅（含新持久计数器）** |
| 20 | nightmare_dawn | boss_slain(pred 3) + deaths==0 | **无** → `floor_scene.gd:1202` | 同 first_lamp 路径 | **新接线 ✅** |
| 21 | trier（M3） | trial_completed | 设计性不接线（active:false，三重守卫拒解锁，T32 已测） | — | M3（不计） |
| 22 | trial_master（M3） | 同上 | 同上 | — | M3（不计） |
| 23 | gifted | talent_purchased | **无** → `talent_system.gd:100`（buy 成功点，T15 未接） | notify_talent_purchased → recheck(purchased_talents>=12) | **新接线 ✅** |
| 24 | overflowing | 同上（>=24） | 同上 | 同上 | **新接线 ✅** |

**清点**：22 条 M2 激活 = 5 条补线前已活（element_scholar / deadeye / flawless_elite / collector·grand_collector 触发路径）＋ **16 条本次新接线** ＋ 1 条 blocked（demolition）。shop_purchase 审计：T35 已在 shop.gd ×3 / drink_machine.gd ×1 发射、CodexSystem.count_buy 消费；24 条成就确无消费方（K.2/K.3 一致），无需就绪检测 ✅。

### 2.3 reset_session（T32 Minor ④ 收口）

`run_root.gd:85`：`_begin()` 内 `DeathRecorder.reset()` 旁 1 行 `AchievementSystem.reset_session()`（K.1/K.4 单局口径同点清零）。测试钉死：`test_achievement_wiring.gd::test_run_begin_resets_achievement_session`（预置会话计数 → _begin → 归零）。

### 2.4 blocked / 缺口（如实入账，不造机制）

| 成就 | 原因 | 去向建议 |
|---|---|---|
| **demolition（拆迁办）** | 游戏事件不存在：props（pillar/crate/bush）是静态阻挡/视觉节点，无「可破坏物」机制（无伤害入口、无破坏结算）。按指示不虚构机制 | M2 门禁报告列 known gap；待可破坏物机制卡落地后 1 行 `notify_prop_destroyed()` 接入（判定器已在表） |
| **collector / grand_collector** | 触发路径已活（weapon_unlocked→recheck，T32 起）；缺口在数据源：`codex_seen` 自 T20/T25/T31/T32 至今**无写入方**（K.5 把写入方标给 T20），回落口径 `unlocked_weapons().size()` 上限 49 < 50，事实不可达。该两条不在「17 条发射点缺口」清单内（T32 评审 Minor ③ 已定性「触发就绪 + 数据源待 T25/T20」） | 数据源写入方（默认池首取 ∪ 任务解锁的已见集合）需横跨掉落/商店/熔铸/初始多个获取点，属图鉴追踪卡范畴，建议 M3 或单列微卡；成就引擎无需改动（写键方落地即自动切权威口径） |
| **full_roster**（披露） | 链路完整（发射点 = K.2 指定的 unlock_hero 成功点），但 M2 无任何玩法流程调用 `unlock_hero`（英雄解锁经济未建）——事件暂不会发生 | 非缺口：发射点权威位置已接线，待 meta 经济卡 |

### 2.5 新增测试（钉死接线）

- `tests/unit/test_achievement_wiring.gd`（新套件，13 用例）：boss 房清→first_lamp（含 100 蓝晶精确入账）；击杀武器投掷→nitpicker；第 3 层→nightmare_dawn（且 first_lamp 不误触）；过层门顺序（floor_cleared 先于 floor_reached：moneybags/slum_king 判定、窗口重置、delver）；_begin 清会话；胜利链三连（night_watcher/speedrunner/no_heal）；挑战房清（count_challenge=5→challenger，全 e2e 走真 3 波）；翻滚躲弹幕计数（接触源不计）；红心拾取计数；开火窗口（近战/远程分流 + 赤手空拳双分支）；天赋购买 12/24 边界；英雄解锁成功点；熔铸计数权威源。
- `test_forge.gd::test_ui_fuse_notifies_achievement_system`：真实 UI 熔铸成交 → 熔铸匠入档（第 10 次熔铸边界）。
- 密闭口径：全局 AchievementSystem（生产同一实例）换临时隔离档 ＋ TestSaveSeal（见 §三），全部 after_test 还原。

---

## 三、裁定㉔：save_headless 套件密闭

### 3.1 根因

无头进程共享 `user://save_headless.json`：场景级测试经真解锁链持久化（unlocked_weapons 回池 ＋ unlock_tasks 计数器快照 ＋ 首杀标记 ＋ 成就/蓝晶）。磁盘残留跨 run 存活 → 下次进程启动 `CodexSystem._ready` 按档回池/恢复计数 → 「纯净引导」假设用例假败（实证 `test_black_stock_prefers_epic_then_rare`；a87605f / df9691a 为逐用例先例）。

### 3.2 修法（套件级，逐用例生效）

新增 `tests/unit/save_seal.gd`（`TestSaveSeal`，静态密闭器）：
- `seal(tag)`：SaveSystem 换临时空档（磁盘残留无关）＋ `GameDB.weapons` 换 M2-T6 纯净池（locked 排除）＋ `CodexSystem.counters` 归零基线；返回还原令牌。
- `restore(token)`：三者引用级还原 ＋ 隔离档删除。**磁盘真档零写入**。
- 语义 = 裁定㉔给出的两个选项合体（套件启动清档 ＋ 测试内还原），且额外保证套内顺序无关。

接入套件（每用例 before/after）：`test_shop`（实证受害套件）、`test_forge`（与既有 crafts 快照/stub 叠加，restore 在后）、`test_balance_bot_calibration`、`test_weapons_pool`、`test_skills_mage_guardian`、`test_achievement_wiring`。
（`test_save` / `test_death_recorder` / `test_run_state` 等既有绝对断言套件本就走临时档，未动。）

### 3.3 证据

1. **极限脏档全量复跑**：合成污染 save_headless.json（115 把全解锁、counters 全满、6 英雄全解锁、成就预置）→ 全量套件首跑暴露 2 处残留敏感点：
   - `test_achievement_wiring`（蓝晶精确断言被 piggyback 解锁扰動）→ 该套件改骑 TestSaveSeal（归零基线）；
   - `test_skills_mage_guardian`（locked 初始武器不入池断言读了运行时池）→ 密闭接入。
   两处修复后复跑全量绿（见 §3.4）。这正是裁定㉔要抓的「其他纯净引导假设测试」——本预检共清出 **6 个池/档敏感套件**。
2. **清档全量复跑（裁定㉔② 正式证据）**：删除 `user://save.json` + `user://save_headless.json` → 全量套件：**1368 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans，76 套件，exit 0**（基线 1358/75 ＋ 本卡 19 新用例 ＋ 套件 1）。确认无其他「纯净引导」假设测试。
3. 复跑前确认：`python -c "import PIL"` 通过（Pillow 12.3.0），无环境假红。

---

## 四、M1 补录 ③④ 核销（e6ed091 附录）

### ③ 死亡确认输入锁 —— **已实现（本卡）**

- 原始诉求：M1-R2 注记①「离散单发按键偶发无响应」→ 建议 0.5s 输入锁。T24 的死亡回顾面板 `_unhandled_input` 对任意键/点击**立即确认**，无锁：致死瞬间按住的火键/连点会直接跳过回顾。
- 实现（`ui/death_summary.gd`）：`CONFIRM_LOCK_TICKS := 30`（0.5s @ 60fps）；`open()` 落 `_opened_frame` 基准帧；锁窗内离散按键/点击 `set_input_as_handled()` 吞掉。锁窗不作用回放退出路径（回放只能先经 Replay 按钮显式启动，GUI 输入先于 `_unhandled_input`）。
- 测试（`test_death_recorder.gd`）：锁窗内按键/点击均不确认且蓝晶零入账（新）；锁过期后任意键确认恰一次（新）；原 `test_any_key_confirms_via_input_path` 更新为注入锁窗已过（钉住过期语义）。

### ④ 跨局遥测留存 —— **核验结论：无缺口，不立项**

- 原始诉求：M1-R2 注记②「DeathRecorder.reset() 清 Telemetry 会话文件导致旧局不可回溯」。
- 现实现核验（`core/meta/telemetry.gd:114-122`）：`reset_session()` 只清**内存**计数（kills/hurt/rooms/peak_dps/伤害窗/回放基准帧），**从不触碰 `user://telemetry.csv`**（文件写入只有 `flush()` 追加路径，`HEADER` 仅在文件不存在时写入）。旧局行全部留盘可回溯。
- 死亡回顾侧：`DeathRecorder.reset()` 只在**下一局 `_begin`** 清 `current_report`/`replay_key`（`run_root.gd:84`）——死亡结算面板在「死亡 → 菜单」期间报告完整可读，回放键同周期有效。
- 结论：T24 已按「会话计数每局清零 + 行文件跨局留存」口径落地，正是补录④要求的「不再静默丢弃」；无代码改动。

---

## 五、微修清单（T36 评审 Minor ①②③⑤ ＋ T35 评审 Minor ④⑤⑥）

| 项 | 内容 | 落地（file:line） | 测试 |
|---|---|---|---|
| T36 ① | cage 豁口 ±40° 窗含邻柱实缘 ~10.6° 披露（atan(12/64) = 10.62°，两端各 ~10.6° 柱体实弧，穿柱宽容口径注释化） | `core/enemies/bosses/frost_widow.gd:61-65` | 注释（无行为变化） |
| T36 ② | `_cage_expire_tick` 全柱到期同步清 `_cage_confine`（原靠空柱守卫 no-op，旗残留至退场） | `core/enemies/bosses/frost_widow.gd:418` | `test_boss_floor_routing::test_widow_cage_expiry_frees_player` 扩断言（RED→GREEN） |
| T36 ③ | `_pick_boss_row` 抽签后直调 `boss_row_for_floor(fl, roll)`，消除 duplicate+sort 双份字典序逻辑 | `core/rooms/floor_scene.gd:1755` | 既有路由套件全绿（行为等价回归） |
| T36 ⑤ | A2 e2e Boss hp 契约钉死：**gem_queen 800 / frost_widow 1800 / prism_golem 1800**（以 `data/enemies.json` 原值为准——任务转述「1800/1800/1800」有误，裁定㉖括号值 800/1800/1800 经表核对一致） | `test_boss_floor_routing::test_scene_a2_boss_room_pool_rows_carry_table_hp`（新，走真实 `_spawn_real_guest` 路径 ×3 行） | 新测试 |
| T35 ④ | `passive_energy_tick(frame)` 未用参数 → `_frame`（仓库 `_param` 惯例），一行 | `core/player/player.gd:229` | 既有套件回归绿 |
| T35 ⑤ | `_reflect_thorns` 目标改**真正就近**（16px 环内距 `ctx.from` 最近者，原取组序首个）；致死接触照常反伤**显式化为设计口径**（附录 C「被接触时反伤 3」无致死例外，结算位于受击收尾） | `core/player/player.gd:370-398` | `test_meta_wiring` 新增 2 用例：组序先远后近钉「就近」；致死接触仍反伤 |
| T35 ⑥ | `test_meta_wiring` 死调用（首个 `set_meta("talent_effects", neutral_effects())` 被下行立即覆写）删除。注：裁定转述「~line 858」系笔误，实际在 line 145（该文件仅 456 行） | `tests/unit/test_meta_wiring.gd:145-147` | 删除后套件全绿 |

---

## 六、移交表复核（逐项 presence/status，不扩 scope）

### 6.1 8 项派味特技（T9 评审移交清单 → T33 门禁核对）

核对基线：`docs/superpowers/reports/task-9-report.md:77-91` 未实现遗留表；本卡以代码 grep（enemies/combat/rooms 全量）＋ `data/enemies.json` 行核对复核。

| 特技 | 敌人（行 id，数据行） | 现状（本次复核） | 判定 |
|---|---|---|---|
| 偷币 | 窃晶鼠群 `crystal_rat` | 仍 suicide 自爆口径，无偷币/逃跑逻辑 | **未实现** |
| 水洼提速 | 苔藓史莱姆 `moss_slime` | splitter 分裂逼近，无水洼 zone | **未实现** |
| 模仿武器 | 深窟回响者 `echo_lurker` | 通用扇弹，无弹形复制 | **未实现** |
| 抛物线 | 荆棘炮台 `thorn_turret` | 直线 3 连发，projectile 无重力/弧线参数 | **未实现** |
| 龟缩 | 硬壳龟 `hardshell_turtle` | 正面减伤 0.8 保留，无龟缩免疫态 | **未实现** |
| 钳击 | 冻土巨蟹 `frost_crab` | heavy 逼近＋正面减伤，无预警扇区横扫 | **未实现** |
| 拉拽 | 磁石傀儡 `magnet_golem` | heavy 逼近，无位移拉拽 | **未实现** |
| 落地生怪 | 种子投手 `seed_pitcher` | 扇形弹，无落地 30% 生怪 | **未实现** |

**结论**：8 项数据行齐全、行为 **0/8 落地**（与 T9 评审口径一致，此后无人承接）。属敌型风味打磨，非门禁链路依赖；建议 M2 门禁报告原样带入 known gap，归 M3/m4 敌型行为清单，防静默丢失（本表即核对凭据）。同表相邻项：幽光水母电弧链/熔岩犬两段咬/火雨祭司火雨区等亦未建（T9 原表「可挂 T28/T10」去向未发生），一并带入。

### 6.2 spare_parts / echo / blessing（T8/T11 移交）

以 T35 评审 25 键结论（裁定㉗：10 个未接线键 = rig 5 + 展示 3 + heart_sense + anti_poison，全部经 grep 证实无消费者、合法移交 M3 combat/resonance 侧）为基准核对：

- **该 25 键口径覆盖的是 T12 的 36 增益键系统**（`buffs.json` / `buff_manager.gd` PLAYER_META_KEYS×20 + RIG_META_KEYS×4 + 公开字段）。**spare_parts / echo / blessing 不在其中**——它们是英雄被动（`data/heroes.json` `passive_id`：engineer=spare_parts、mage=echo、guardian=blessing），另有 ranger=hawk_eye、assassin=shadow_reap 同状态。
- 三者现状：**data-only**（行内 `passive_id` 就位，`test_heroes` 钉住数据），消费代码不存在，且技能卡侧有显式披露注释：`core/player/skills/turret.gd:10`（备件「开局/每层补 1 台」后续卡接线）、`arcane_nova.gd:12`（回响）、`life_tide.gd:13`（祝福）——**非静默丢失**。对照：vanguard `defiance` 已接线（player.gd has_defiance/坚守），即被动接线有既有先例路径。
- **判定**：合法 defer 至 M3（英雄被动接线卡；T8/T11 卡内明示「后续卡接线，本卡不实现」）。建议门禁报告将「英雄被动 5 条（spare_parts/echo/blessing/hawk_eye/shadow_reap）」与 8 派味特技并列为 M3 清单。

---

## 七、偏差与移交

1. **任务卡勘误（不作变动，以数据为准）**：A2 Boss hp 转述「gem_queen 1800」有误——`enemies.json` 为 800；T36 ⑤ 测试按表值钉死（800/1800/1800）。`test_meta_wiring` 死调用实际在 line 145 非 858。
2. **密闭范围扩大**：裁定㉔点名 save_headless 套件；预检以「清档全量复跑」为镜清出 **6 个**池/档敏感套件统一接入 TestSaveSeal（shop/forge/balance/weapons_pool/skills_mage_guardian/achievement_wiring），并顺带以极限脏档全量跑做破坏性验证（抓出 2 处，均已修）。
3. **成就新接线的副作用披露**：场景级测试现在会经真实链路解锁成就 → 蓝晶入账共享 save_headless.json（产品正确行为，裁定㉒口径）。全量两轮（脏档/清档）均绿，无绝对断言受扰。
4. **不立项**（有意识决定，非遗漏）：collector/grand_collector 的 codex_seen 写入方（数据源卡范畴，见 §2.4）；④ 遥测留存（无缺口）。
5. **测试增量**：新增用例 19（wiring 13 + forge UI 1 + 死亡锁 2 + thorns 2 + boss hp 1）＋ 既有用例扩断言 2（cage 旗 / 任意键过期语义）；76 套件 1368 用例全绿。
