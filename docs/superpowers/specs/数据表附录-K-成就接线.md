# 数据表附录 K：成就接线表（M2-T3 定稿）

> GDD 契约出处：数据表附录 G.1「成就（24）与试炼模式」、设计文档 §17（图鉴/天赋/成就从主菜单进入，解锁即时右下角 toast 不打断战斗）、§20（成就 24 条中 22 条 M2 激活，试炼相关 2 条随 M3 激活）。
> 本文为成就接线表定稿：24 条成就 ↔ 触发信号 ↔ 判定数据（22 条 M2 激活 + 2 条试炼标注 M3）。
> 系统落地消费方：M2-T33（`core/meta/achievement_system.gd` + `ui/toast.tscn`：信号订阅 + 轮询判定 → `SaveSystem.unlocked_achievements` → 右下角中文 toast「成就解锁：xxx」+ 蓝晶入账 `add_gems`）。计数源与 M2-T20 图鉴解锁引擎共享（计划卡 T33 明文；计数器持久化归 M2-T25 存档 v2，字段映射见 K.5）。

## K.1 接线契约

- 判定模式混合：**事件驱动**（信号到达即判）+ **结算点轮询**（victory/floor_cleared 时读会话汇总）。 AchievementSystem 订阅 K.2 信号；每条成就按 K.3 判定式求值，达成 → 入档 + toast（一次性，靠 `unlocked_achievements` 集合去重）。
- 蓝晶奖励（附录 G.1 原值）经 `SaveSystem.add_gems` 入账；试炼模式 ×1.5 加成（M3）。
- 判定数据三源：**Telemetry**（行事件与会话计数 `session_summary()`：kills/hurt_count/rooms/peak_dps/run_time）、**RunState**（floor_idx/coins/run_time_frames/weapons 等）、**SaveSystem**（unlocked_heroes/purchased_talents/unlocked/codex_seen/counters.*）。单局口径用会话计数（`reset_session` 清零），累计口径用存档计数器（T25 v2）。

## K.2 信号清单（既有可复用 4 + 新声明 13）

| 信号 | 状态 | 声明/发射责任卡 |
|---|---|---|
| `enemy_damaged(amount, is_crit)` | 既有（event_bus.gd） | —（M0 起） |
| `enemy_killed(enemy_id)` | 既有 | —（kill 行同步落遥测） |
| `resonance_triggered(reaction, at, payload)` | 既有 | —（共鸣引擎） |
| `room_cleared(room_id)` | 既有 | —（RoomCombat） |
| `boss_slain(boss_id: String, floor_idx: int)` | 新声明（EventBus） | M2-T33（BossBase/RoomCombat 死亡点发射） |
| `floor_reached(floor_idx: int)` | 新声明 | M2-T33（RunState.next_floor 后发射） |
| `floor_cleared(floor_idx: int)` | 新声明 | M2-T33（InterFloor 层通过点发射） |
| `victory_achieved` | 新声明 | **M2-T18**（inter_floor_flow 桩→真实信号，卡内明文） |
| `item_forged(recipe_id: String)` | 新声明 | **M2-T25**（熔铸台成交点） |
| `weapon_unlocked(weapon_id: String)` | 新声明 | **M2-T20**（CodexSystem 解锁点） |
| `hero_unlocked(hero_id: String)` | 新声明 | M2-T33（SaveSystem.unlock_hero 成功点） |
| `talent_purchased(talent_id: String)` | 新声明 | **M2-T15**（TalentSystem.buy 成功点） |
| `prop_destroyed(prop_kind: String)` | 新声明 | M2-T33（FloorScene 可破坏物破坏点） |
| `roll_dodge` | 新声明 | M2-T33（Player 翻滚无敌帧内躲弹计数点） |
| `challenge_cleared` | 新声明 | **M2-T30**（挑战房三波收口） |
| `shop_purchase(kind: String)` | 新声明（**待发射**） | **M2-T35 接线卡**（shop.gd/drink_machine.gd 当前无购买信号/遥测——buy_x 计数源缺口，发射点由 T35 补线；T20/T33 按本表同名对接，kind 如 `weapon`/`drink`） |
| `trial_completed` | 新声明 | M3（试炼系统，随试炼模式落地） |

> **boss_slain 命名注记（评审 Major ③）**：既有实例级局部信号 `FloorScene.boss_defeated(room_id: int)`（`core/rooms/floor_scene.gd:69`，m1-t27，boss 房清时发射、`RunRoot` 消费中作层间流转）与成就侧信号**同名异签名**，故后者更名为 `boss_slain(boss_id, floor_idx)`。两者关系：FloorScene 局部信号保留现状仅作层间流转；EventBus 侧 `boss_slain` 为 M2-T33 成就判定**唯一订阅源**（发射点在 BossBase/RoomCombat 死亡上下文，携带 boss_id + 层号），T33 不得误接 FloorScene 实例信号。

遥测行事件扩展（T33 发射点）：`death`（玩家死亡）、`heart_pickup`（红心拾取）、`prop_destroyed`、`roll_dodge`、`crit`（或复用 `enemy_damaged(is_crit)` 聚合）。既有 `kill` 行已带 boss 标记与玩家武器 id（v1/v2/v3 列契约），`fire` 行带武器 id——直接支撑鸡蛋里挑骨头/赤手空拳判定，无需新列。

## K.3 全表（24 条）

| # | id | 成就 | 条件（附录 G 原文） | 蓝晶 | 批次 | 触发信号 | 判定数据 | 判定式 |
|---|---|---|---|---|---|---|---|---|
| 1 | `first_lamp` | 初次点灯 | 首次击败 A1 Boss | 100 | M2 | `boss_slain` | 信号参数 `floor_idx` | `floor_idx == 1` |
| 2 | `delver` | 深入者 | 首次抵达 A3 | 150 | M2 | `floor_reached` | 信号参数 `floor_idx`（RunState.floor_idx 同源） | `floor_idx >= 3` |
| 3 | `night_watcher` | 守夜人 | 任意角色通关 | 300 | M2 | `victory_achieved`（T18） | 信号即达成 | 到达即 true |
| 4 | `element_scholar` | 元素学者 | 单局触发 30 次共鸣 | 150 | M2 | `resonance_triggered`（既有） | Telemetry 共鸣会话计数 | `>= 30` |
| 5 | `forge_smith` | 熔铸匠 | 完成 10 次熔铸 | 100 | M2 | `item_forged`（T25） | `SaveSystem.counters.crafts_total`（与图鉴 `craft_x` 同源） | `>= 10` |
| 6 | `bare_hands` | 赤手空拳 | 单层仅用近战通关 | 200 | M2 | `floor_cleared` | Telemetry `fire` 行武器类别（本层窗口） | 远程开火 `== 0` 且近战挥击 `>= 1` |
| 7 | `deadeye` | 弹无虚发 | 单局暴击率 >35%（≥50 次射击） | 100 | M2 | `enemy_damaged`（既有） | Telemetry 射击/暴击会话计数 | `crits / shots > 0.35 && shots >= 50` |
| 8 | `slum_king` | 贫民窟之王 | 0 死亡通过 A1 | 100 | M2 | `floor_cleared` | Telemetry `death` 会话计数 | `floor_idx == 1 && deaths == 0` |
| 9 | `collector` | 藏品家 | 图鉴累计 50 把武器 | 150 | M2 | `weapon_unlocked`（T20） | `SaveSystem.codex_seen`（T20 维护：默认池首次获取 ∪ 解锁） | `size >= 50` |
| 10 | `grand_collector` | 大收藏家 | 图鉴集齐 115 把 | 500 | M2 | `weapon_unlocked`（T20） | 同上 | `size >= 115` |
| 11 | `full_roster` | 全员集合 | 解锁全部 6 角色 | 400 | M2 | `hero_unlocked` | `SaveSystem.unlocked_heroes` | `size >= 6` |
| 12 | `flawless_elite` | 无伤精英 | 无伤击败任一精英 | 50 | M2 | `enemy_killed`（既有） | 精英房上下文 + Telemetry `hurt` 本房窗口增量 | 精英死 && 窗口 `hurt == 0` |
| 13 | `speedrunner` | 速通者 | 单局 <20 分钟 | 150 | M2 | `victory_achieved`（T18） | `RunState.run_time_frames` | `< 72000`（20min × 60fps） |
| 14 | `moneybags` | 财神 | 单局携带 >500 金币通关 A1 | 100 | M2 | `floor_cleared` | `RunState.coins` | `floor_idx == 1 && coins > 500` |
| 15 | `nitpicker` | 鸡蛋里挑骨头 | 用投掷武器击败 A1 Boss | 100 | M2 | `boss_slain` | `kill` 行武器 id → `GameDB.weapons_all[..].category` | `floor_idx == 1 && category == "throw"` |
| 16 | `demolition` | 拆迁办 | 单局破坏 30 个可破坏物 | 50 | M2 | `prop_destroyed` | Telemetry `prop_destroyed` 会话计数 | `>= 30` |
| 17 | `dodge_master` | 走位大师 | 单局翻滚躲过 100 发弹幕 | 100 | M2 | `roll_dodge` | Telemetry `roll_dodge` 会话计数 | `>= 100` |
| 18 | `no_heal` | 拒绝治疗 | 不拾取红心通关 | 200 | M2 | `victory_achieved`（T18） | Telemetry `heart_pickup` 会话计数 | `victory && heart_pickup == 0` |
| 19 | `challenger` | 挑战者 | 完成 5 个挑战房 | 100 | M2 | `challenge_cleared`（T30） | `SaveSystem.counters.challenge_rooms_total` | `>= 5` |
| 20 | `nightmare_dawn` | 噩梦黎明 | A3 无死亡击败 Boss | 300 | M2 | `boss_slain` | 信号 `floor_idx` + Telemetry `death` 会话计数 | `floor_idx == 3 && deaths == 0` |
| 21 | `trier` | 试炼者 | 完成 1 次每日试炼 | 100 | **M3** | `trial_completed`（M3） | `SaveSystem.counters.trials_total` | `>= 1` |
| 22 | `trial_master` | 试炼大师 | 累计 10 次每日试炼 | 200 | **M3** | `trial_completed`（M3） | 同上 | `>= 10` |
| 23 | `gifted` | 天赋异禀 | 天赋树点亮 12 节点 | 150 | M2 | `talent_purchased`（T15） | `SaveSystem.purchased_talents`（T2 全表 24 节点） | `size >= 12` |
| 24 | `overflowing` | 满溢之光 | 天赋树全部点亮 | 500 | M2 | `talent_purchased`（T15） | 同上 | `size >= 24` |

> 蓝晶合计：M2 22 条 = **4050**（100×8 + 150×5 + 300×2 + 200×2 + 500×2 + 400 + 50×2；原文 3350 系合计笔误，逐条数值与附录 G 一致——评审 Minor ②勘误）；M3 2 条 = 300（试炼 ×1.5 后口径归 M3）。

## K.4 判别口径备注

- **单局 vs 累计**：单局条件（元素学者/弹无虚发/赤手空拳/贫民窟之王/速通者/财神/鸡蛋里挑骨头/拆迁办/走位大师/拒绝治疗/无伤精英/噩梦黎明）用 Telemetry 会话计数（`reset_session` 清零）；累计条件（熔铸匠/藏品家/大收藏家/全员集合/挑战者/天赋异禀/满溢之光/试炼×2）用 SaveSystem 持久字段。
- **贫民窟之王/噩梦黎明的「死亡」**：`death` 行（玩家 HP 归零）口径，与「受击」（`hurt`）区分；无伤精英才用 `hurt` 口径（精英血量短窗口，受击即破）。
- **图鉴计数**（藏品家/大收藏家）：`codex_seen` = 默认可用 66 把中获取过的 ∪ 49 条任务已解锁的（T20 维护；115 把全集 = weapons_all 计数）。
- **速通者**：`run_time_frames` 与 `Telemetry.session_summary().run_time` 双口径一致（60fps 换算 72000 ticks）。

## K.5 存档 v2 字段映射（M2-T25 消费）

| 存档字段（v2 新增） | 写入方 | 消费方 |
|---|---|---|
| `counters.kills_total / crafts_total / resonances_total / gems_earned_total / purchases_total / floor_clears[1..3] / challenge_rooms_total / trials_total` | T25（会话结束入档聚合；`purchases_total` 的**事件发射点 = `shop_purchase`（M2-T35 接线）**，T25 只聚合不自采） | T20 图鉴（J.2 六类）+ T33 成就（熔铸匠/挑战者/试炼×2） |
| `unlocked_weapons`（武器解锁集合） | T20 | T20 掉落池过滤（J.6）+ T33（藏品家/大收藏家经 codex_seen） |
| `codex_seen`（图鉴已见集合） | T20 | T33（藏品家/大收藏家） |
| `purchased_talents` | T15 | T33（天赋异禀/满溢之光） |
| `unlocked_achievements` | T33 | T33 去重 + 蓝晶入账幂等 |
