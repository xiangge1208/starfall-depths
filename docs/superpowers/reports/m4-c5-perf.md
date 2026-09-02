# M4-C5 perf 抽验 + 可破坏物机制证据（2026-09-02）

- 卡：M4 Task C-5（可破坏物机制 + demolition 成就接线）；分支 `m4-c5`
- 口径：perf_probe 既有档全层窗口运行（GDD §18.3 预算表，热身 120 帧 + 采样 480 帧，
  vsync 关）；F2 draw 抽验对照参考基线 avg ~101、预算 ≤150。

## perf_probe 结果（全层 PASS，`PERF VERDICT: PASS`）

| 层 | 模板 | 逻辑帧 avg/max (ms) | 渲染 CPU avg (ms) | draw avg/max | 实体(非弹) | 弹峰 | 整帧合成 (ms) |
|---|---|---|---|---|---|---|---|
| F1 | combat_a1_03 (密度 18) | 0.020 / 0.040 | 0.023 | 98.2 / 188 | 66 | 500 | 10.64 |
| **F2** | combat_a2_01 (密度 13) | 0.021 / 0.049 | 0.024 | **107.6 / 185** | 62 | 500 | 10.54 |
| F3 | combat_a3_08 (密度 14) | 0.035 / 0.059 | 0.022 | 98.0 / 154 | 62 | 500 | 9.75 |

- **F2 draw avg 107.6 ≤ 150 预算 PASS**；与参考基线 ~101 同量级（差值在探针
  逐帧采样/run 间噪声带内；可破坏物视觉与静态期同构：同为 StaticBody2D + 单
  vis 子节点，零新增 draw 来源）。粒子池活跃峰 34~35、降级 0 tick（破坏表现走
  既有 kill_shard 预算，未新增 draw 大户）。
- 原始机器值：`user://m2_perf.json`（窗口运行产出，本文件为摘录）。

## 可破坏物运行证据（同分支 bot 冒烟局，见 m4-c5-smoke.md）

- telemetry.csv `prop_destroyed` 行样例（列契约 event,ts_frame,v1=kind,v2=max_hp,
  v3=drops 数,source）：
  ```
  prop_destroyed,7401,pillar,20,0,
  prop_destroyed,7638,crate,8,1,
  prop_destroyed,8031,crate,8,1,
  ```
  真实局内玩家弹/近战经 CombatSystem 判定流拆毁 pillar/crate，掉落列与数据行
  一致（pillar 无掉落 / crate 1 coin）。

## 机制摘要（实现口径）

- 伤害入口：`DestructibleProp`（core/rooms/destructible_prop.gd）走 CombatSystem
  既有判定缝（gem_queen HivePillar 先例同形：`register_body(Faction.ENEMY)` →
  玩家弹/近战/召唤物/玩家侧 AoE 可及；固定伤害制直扣 ctx.amount，无二次随机乘区）。
- 独立池：`PER_ROOM_CAP=32` 每房上限（模板实测最大 14，cap 为防滥用护栏）；本体
  不是弹，不进 ProjectilePool/弹幕可视化预算（测试钉 `active_count()==0`）。
- 与蜂巢柱关系：**并行不共用**——gem_queen.gd HivePillar（Boss 可破坏掩体，含
  敌弹吸收特技）零改动，其既有测试（test_boss_floor_routing）全量绿。
- demolition 接线：破坏结算单点 `FloorScene._on_prop_destroyed` →
  `AchievementSystem.notify_prop_destroyed`（1 行）→ 30 次阈值解锁（gems 50）。
  **24/24 成就全激活口径达成**（M2 末 21/22 非试炼 + M3 试炼 2 = 23，本卡后
  demolition 激活 → 24/24；引擎阈值半边既有 test_achievements 钉死，接线半边
  test_destructible_props 钉死）。
