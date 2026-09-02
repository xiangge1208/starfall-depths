# M2 Balance Bot 全层回归报告（2026-09-02 · Task 27 / H-1 · m2-t28）

- 驱动：`tools/balance_bot.gd` 无头自动游玩（启发式走位/避弹/避爆炸域/避 hazard/环绕走位/索敌开火/概率翻滚/商店买红心/事件一律接受/三选一贪心），hero=vanguard，headless 墙钟速率（引擎 time_scale 对本作逐拍定步长逻辑无加速效用，物理拍=真实玩家体验时长）
- 决策纯逻辑：`tools/balance_bot_decisions.gd`（确定性，tests/unit/test_balance_bot_decisions.gd 钉死）；校准点机器值：tests/unit/test_balance_bot_calibration.gd 钉死
- 局数：10（种子 2101..2110）｜崩溃：0｜超时中止：0

## 内容覆盖前提（先读这段再读数据）

- **本批回归基线 = main c676657：仅第 1 层为完整可玩内容。** A2/A3 房间模板在 T26（并行在途，含修复轮）；`run_root._floor_data_available(2)` 为假 → 过第 1 层层间门后进入生产「A2 入口里程碑」（`a2_entry_active()`，Task 20/26 定义的最小可玩端点），bot 记为终局 `milestone_a2`。
- 因此 **生产胜利（第 3 层 Boss 链）在本基线不可达，§14.3 胜率带（20%~40%）本批「不可评」**——如实标注，不调数值凑数。可评口径：第 1 层内的死亡热房 / TTK / 房间与单层时长 / 蓝晶曲线 / 内容上限到达率（胜利或 milestone_a2 到达占比 = 0%）。
- 已知内容缺口（T26 合并后仍成立，T36 承接）：A2/A3 波次将仍用 A1 敌人名录、Boss 三层恒 vine_colossus——届时胜率/TTK 的含义仍受此限制：三层难度递进缺失使深层数据偏「同难度复读」，真实分层后胜率预计低于届时测量。
- T26 合并后同一 bot（零改动）自动续走 2/3 层并复评胜率带；本报告即「第 1 层全内容回归 + 骨架就绪证明」。

## 汇总（结局分布 + 可评带对照）

| 指标 | 实测 | §14.3 目标带 | 判定 |
|---|---|---|---|
| 生产胜率（第 3 层胜利） | 0/10 | 20%~40% | **不可评（本基线无 2/3 层内容）** |
| 内容上限到达率（win+milestone_a2） | 0% | -（本卡替代口径） | 有未走完局（超时/崩溃） |
| 单局时长(均值/中位) | 1.5 / 1.9 min | 25.0~35.0 min（单局口径） | 第 1 层子集，仅参考 |

## 逐局

| seed | 结果 | 止步 | 房间 | 击杀 | 时长(min) | 金币 | 蓝晶 | 买红心 | 增益选择 | 首杀可获 | 死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2101 | death | 第1层 | 3 | 26 | 2.1 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |
| 2102 | death | 第1层 | 2 | 8 | 1.9 | 0 | 0 | 0 | - | 否 | 弩兵的弹幕（combat） |
| 2103 | death | 第1层 | 4 | 19 | 1.9 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |
| 2104 | death | 第1层 | 0 | 7 | 0.6 | 0 | 0 | 0 | - | 否 | 藤蔓冲锋者的接触冲撞（combat） |
| 2105 | death | 第1层 | 4 | 26 | 2.5 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |
| 2106 | death | 第1层 | 1 | 7 | 0.5 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |
| 2107 | death | 第1层 | 1 | 11 | 0.8 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |
| 2108 | death | 第1层 | 3 | 20 | 1.4 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（elite） |
| 2109 | death | 第1层 | 1 | 8 | 0.5 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |
| 2110 | death | 第1层 | 5 | 28 | 3.0 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（elite） |

- 「首杀可获」= 该局开始时 vine_colossus 尚无 SaveSystem 首杀标记（击杀蓝晶 +300 只落批次首局，见局间隔离披露）。

## 死亡热房（死亡楼层 × 房型）

| 层:房型 | 死亡次数 |
|---|---|
| F1:combat | 8 |
| F1:elite | 2 |

## TTK / 节奏（对照 §14.3；本批全部为第 1 层口径）

| 指标 | 实测(中位/p90) | §14.3 目标 | 判定 |
|---|---|---|---|
| A1 杂兵 TTK | 4.8 / 18.0 s (n=151) | ≤2.0 s | 偏离 |
| 精英击杀 | 2.7 / 5.7 s (n=9) | （参考） | - |
| 战斗房时长 | 34.4 / 52.7 s (n=19) | 20.0~40.0 s | 达标 |

## 蓝晶获取曲线（每局层末快照；§14.1 过层 60/120/200 + 击杀档位）

| seed | F1 末(过层门快照) | 终局 |
|---|---|---|
| 2101 | 0 | 0 |
| 2102 | 0 | 0 |
| 2103 | 0 | 0 |
| 2104 | 0 | 0 |
| 2105 | 0 | 0 |
| 2106 | 0 | 0 |
| 2107 | 0 | 0 |
| 2108 | 0 | 0 |
| 2109 | 0 | 0 |
| 2110 | 0 | 0 |

- 口径披露：`RunState.gems` 为本局待结算蓝晶（死亡减半/胜利全额入档在终局确认；本 bot 经测试缝捕获终局，不入档）。vine_colossus Boss 首杀 +300 只落在批次首局（SaveSystem 跨局累积，模拟真实玩家成长），其余局 +50/次；elite +5 / miniboss +20 随杀随入池。

## 校准点复核（裁定①②③④⑤⑥，逐项带值）

### ① 炮台 DPS（裁定①口径：射速 2/s × 伤 4 = 8 DPS）

| 炮台 | 周期(t) | 发/周期 | 单发伤 | 持续 DPS | vs 8 DPS 口径 |
|---|---|---|---|---|---|
| thorn_turret | 160 | 3 | 4 | 4.50 | 56% |
| rock_crystal_turret | 180 | 1 | 6 | 2.00 | 25% |
| lava_turret | 180 | 5 | 8 | 13.33 | 167% |

- 结论：**thorn_turret 实装 4.5 DPS（裁定①口径 8 DPS 的 56%）**——3 连发周期 160t（1.125 发/s）未达计划卡「射速 2/s」。lava_turret 扇形 5 发全中 13.33 DPS（理想暴露值）；rock_crystal_turret 蓄能激光 2.0 DPS。三种炮台均以数据行 + 原型循环语义机器复核（test_balance_bot_calibration 钉死）。
- 动态半边：本批 bot 未记录到炮台来源实吃伤害（走位规避生效或本批房间未出炮台）。

### ② 掉落稀有度权重（T6 移交复核；m2-audit 已收口）

- m2-audit 收口（漂移曾于此坐实）：漂移键名 LOOT_RARITY_WEIGHTS（floor_scene.gd 自造 {common:60, rare:30, epic:10}，注释称「白/绿/蓝」——uncommon 无权重键绿档永不被直抽 ~3.2% vs 设计 30%；epic 空桶兜底退化为全池均匀）已删除。
- 现口径：武器掉落统一走 ShopLogic §8.2 分源行——战斗房按层（A1 70/25/5/0/0、A2 45/35/16/4/0、A3 25/33/25/13/4）、宝箱房 30/35/22/10/3、精英房奖励 10/30/35/20/5；空桶经 RARITY_FALLDOWN 逐级向下（不再全池均匀）。test_balance_bot_calibration 钉死。

### ③ 熔铸费用公式 30~390 阶梯（裁定⑰）

- 实测阶梯（较高稀有度基准价 ×1.5 取整到 5）：白 30 / 绿 65 / 蓝 130 / 紫 235 / 橙 390——**两端点 30/390 与裁定⑰一致**，中间档单调递增无跳变（test_balance_bot_calibration 钉死）。

### ④ 守护者史诗星辉杖无弱化（裁定⑥）

- guardian.start_weapons = `xinghuizhang` → weapons 表原行 rarity=epic damage=4 rate=3.0；全表无弱化变体 id。**与裁定⑥一致（无弱化）**。
- 覆盖口径：bot 本批全部 vanguard（初始武器 laohuoji），守护者/星辉杖手感**未在对局覆盖**——本项为数据面复核（采不到对局数据，按数据侧核对处理）。

### ⑤ 生命潮汐法阵 3s 实落 1HP（裁定⑥）

- 实装口径：施放立即回 2 HP；法阵 180t（3s）× 0.5 HP/s 名义 1.5 HP，整数累加器只落 1 HP（第 2 秒拍），余 0.5 消散且不跨施放携带；阵外节拍空转。**与裁定⑥「3s 实落 1HP」一致**。
- 覆盖口径：bot 用 vanguard（技能狂潮），生命潮汐为 guardian 技能——**对局未覆盖**；本项为帧注入直驱复核（test_balance_bot_calibration 逐拍验证）。

### ⑥ 先知击杀经济 +53/+353（裁定⑲）

- 数据行半边：`starfall_prophet` **已在 main**（m2-t24 先知卡合入）——hp=3200，行内 drops 含 gems3（3 蓝晶实体掉落，拾取各 +1）。
- 结算函数半边（RunState.settle_kill_gems 生产口径，test_balance_bot_calibration 以首杀标记快照/还原钉死）：击杀 +50（Boss 档）；首杀再 +300 = **+350**。
- 合计口径（裁定⑲）：普通击杀 = 50 + 3（gems3 拾取）= **+53**；首杀 = 350 + 3 = **+353**。✅ 与裁定⑲一致。
- 对局动态半边：隐藏门需 A3 层（`A3_FLOOR_IDX=3`），本基线 A2/A3 模板在 T26 在途 → **本批对局内未覆盖**（bot 先知击杀数 = 0）。T26 合并后复跑即自动采样（bot 已对「已清房存活波次外嘉宾」保持战斗驱动）。

## 校准建议（只给建议不改数值——校准归后续裁定）

- 胜率带（20%~40%）本批不可评（生产胜利需 3 层内容；本基线仅第 1 层可玩）。**行动项：T26 合并后以同一 bot 复跑 10 局出带**；本批第 1 层口径的上半程生存率 0% 可作为届时带判的先导信号（上半程全活 ≠ 全局带内，届时以全 3 层测量为准）。
- 因子一（输出端）：A1 杂兵 TTK 中位 4.8s 超出 §14.3「初始武器 ≤2.0s」。建议校准初始武器（laohuoji）基础伤害/攻速 +20%~30% 后复测。
- 因子三（生存端）：死亡热房 F1:combat（8 次）。若集中于特定房型，建议校准该房型敌方弹幕密度（§7.5 上限）或弹速 -10%~15%；死亡集中于 Boss 房则复核 P2/P3 弹幕量曲线。

## 接口边界与前提披露

- **接口边界**：bot 只经由生产接口操作——Input 移动、`PlayerDriver.touch_mode_override`（生产触屏 auto_aim 自动开火，手机玩家同路径）+ 战斗期按住物理 fire、`player.start_roll`/`Skill.cast`（CD/耗蓝守卫在生产侧）、`FloorScene.enter_room`（生产 enter_room→_push_back 落位，走廊徒步不模拟，同 m1_loop_smoke 惯例）、`Shop.interact` + `_buy_item("heart")`（RunState.spend_coins 扣款）、`EventRoom.accept`（bot 一律接受）、层间三回调。伤害/击杀/掉落/金币全部由生产战斗链路自然发生；bot 不使用熔铸台/雕像/饮料机（商店仅买红心）。
- **种子口径**：`RunState.start_run` 墙钟种子被 `RunState.run_seed = seed` + `RngSvc.setup_run(seed)` 确定性覆写（start_run 其余状态不变）；bot 决策采样用独立 `_rng`（同种子播种）——同 seed 可复现整局（bot 行为侧；敌人 AI 消费 RunState 盐流，同种子同确定性）。
- **局间隔离**：每局 `start_run` 重置局内状态；SaveSystem 原状保留（headless 自动重定向 save_headless.json，真档不受影响）——图鉴/成就计数与 Boss 首杀标记跨局累积（真实玩家成长模拟），vine_colossus 首杀 +300 只落批次首局（逐局表「首杀可获」列可查）。多局会推进 save_headless.json 的图鉴/解锁进度，属产品正确行为（裁定㉒口径）。
- **胜/死捕获**：生产测试缝 `run_root.victory_route_override` / `DeathRecorder.open_summary_override`（死亡报告 = DeathRecorder.build_report 生产口径）；终局蓝晶**不入档**（无 DeathSummary/VictorySummary 确认路径）。
- **内容缺口（前提，非本卡缺陷）**：本基线 A2/A3 层模板在 T26（并行在途）——本报告全部统计为第 1 层口径；A2/A3 就绪后波次仍为 A1 名录、Boss 恒 vine_colossus（T36 承接），届时报告继续注明该限制。


---

# M4-C1 冒烟裁定 + 派味特技遥测台账（2026-09-02 · Task C-1 · m4-c1）

> 以下为 m4-c1 卡追加节（bot 报告主体为既有模板自动产出）。执行卡：Task C-1
> 敌人派味特技 ×11（代码+数据+测试见 feat b591aca）。

## 冒烟裁定（验收口径：崩溃数=0、无新停滞、房间可清不变量不破）

| 指标 | 实测 | 判定 |
|---|---|---|
| 局数 / 崩溃 | 10 / **0** | ✅ |
| 超时中止 / 停滞（bot 180t 无进展窗） | 0 / **0**（aggregate.stalls=0） | ✅ 无新停滞 |
| 结局分布 | death ×10（F1:combat 8 / F1:elite 2） | 与 m2-balance-2026-08-31 基线（9 death + 1 timeout，种子 2001..2010）同型——bot 全部止步第 1 层属 B-2 终判披露的 bot 能力结构性边界，非本卡回归 |
| 房间可清 | 逐局清房数 3/2/4/0/4/1/1/3/1/5（合计 24 房清），room_dur 中位 34.4s | ✅ 清房节奏正常，无可清性退化 |

**覆盖度披露（如实入账）**：F1 垃圾怪池（floor_scene.gd FLOOR_TRASH[1]）= kuli_bug /
cave_bat / crossbowman / vine_charger——**不含 11 个派味特技敌**（特技敌分属
FLOOR_TRASH[2] magnet_golem/ghost_jelly/frost_crab/crystal_rat/echo_lurker 与
[3] lava_hound/firerain_priest；hardshell_turtle/thorn_turret/moss_slime/
seed_pitcher 现无任何波次引用，属 M2 已披露的波次接线范围、非本卡文件所有权）。
故本批冒烟对「新行为零变化路径」做了全覆盖回归（改动的 6 个 archetype +
EnemyBase 对无键行逐字节零漂移，test_signature_moves + 既有 test_enemy_ai 钉死），
而特技行为本身的房间级可清性由单测承载红线不变量：落地生怪 per-投手上限 3 +
counts_for_wave=false（不阻清房）、水洼帧基过期 + 活区上限 24、龟缩免疫窗有界
（210/90 周期必然让位）、偷币死亡全额返还。bot 达 F2 能力属 B-3 卡范围。

## 派味特技遥测台账（M4 约束 12：新行为必带遥测；事件名已查 Telemetry 既有清单无撞名）

| # | 事件 | 发射点（file:line） | 列语义（event,ts_frame,v1,v2,v3,source） | 行为 | 单测钉死 |
|---|---|---|---|---|---|
| 1 | enemy_shell_up | archetypes/heavy.gd:88 | v1=缩壳窗长 ticks | 硬壳龟缩壳起步（每周期 1 行） | test_turtle_shell_cycle_* |
| 2 | enemy_arc_volley | archetypes/turret.gd:105 | v1=burst_count | 荆棘炮台抛物连发（逐发 1 行） | test_thorn_turret_arc_* |
| 3 | puddle_created | archetypes/splitter.gd:66 | v1=半径 px | 苔藓史莱姆落洼（拖尾+死亡各 1 行） | test_moss_slime_drops/death |
| 4 | puddle_boost | archetypes/splitter.gd:41 | v1=提速倍率 | 苔藓系进水洼提速（一窗一行） | test_moss_slime_drops_puddle_* |
| 5 | seed_sprout | archetypes/barrage.gd:172 | v1=幼体行 id / v2=活苗数 | 种子投手落地生怪（中签出苗 1 行） | test_seed_pitcher_sprout_* |
| 6 | enemy_pull | archetypes/heavy.gd:129 | v1=位移 px | 磁石傀儡拉拽得手（1 行/次） | test_magnet_golem_pulls_player_* |
| 7 | claw_sweep | archetypes/heavy.gd:191 | v1=命中 1/0 | 冻土巨蟹钳击横扫（每扫 1 行） | test_frost_crab_claw_* |
| 8 | coin_steal | archetypes/suicide.gd:51 | v1=窃取额 | 窃晶鼠群偷币得手 | test_crystal_rat_steals_* |
| 9 | coin_recover | archetypes/suicide.gd:62 | v1=返还额 | 窃晶鼠死亡全额返还 | test_crystal_rat_death_refunds_* |
| 10 | enemy_mimic_shot | archetypes/barrage.gd:222 | v1=复制弹数 | 深窟回响者模仿齐射（1 行/轮） | test_echo_lurker_mimics_* |
| 11 | enemy_chain_zap | enemy_base.gd:151 | v1=元素名 | 幽光水母电弧链（元素弹出膛 1 行） | test_ghost_jelly_fires_* |
| 12 | enemy_double_bite | archetypes/charger.gd:52 | v1=段号 | 熔岩犬第二段扑咬起冲拍 | test_lava_hound_two_stage_* |
| 13 | firerain_strike | archetypes/barrage.gd:254 | v1=区数 | 火雨祭司施放火雨（1 行/轮） | test_firerain_priest_casts_* |

**运行时留痕披露**：本批 10 局 telemetry.csv 中上述事件为 0 行——与覆盖度披露同
因（F1 波次池无特技敌，特技代码路径在局内未被触发；F1 无键行的零漂移路径不产
遥测）。每事件的发射点由 tests/unit/test_signature_moves.gd 走真实 Telemetry
autoload 路径触达（gdUnit 会话行数未达 32 行 flush 阈值，不落 CSV——发射正确性
以断言承载）；生产对局留痕自 A2/A3 内容进入 bot 可达范围后自动采样。schema 面
工具证据：`tools/validate_enemies.gd` 无头校验 52/52 PASS（fail-closed：缺键/
类型越界/语义域越界/跨行引用断链即退出码 1）。

## 结论

- C-1 验收「11 项行为可玩可测 + 全量绿 + bot 冒烟 10 局无新停滞」：✅
  （11/11 行为落地无豁免；全量 1698/1698 绿含新 44 用例；冒烟 0 崩溃 0 停滞 0 超时）
- 移交披露：hardshell_turtle / thorn_turret / moss_slime / seed_pitcher 4 行现无
  波次引用（M2 起的波次接线范围），待波次池扩编卡承接；届时本台账事件随对局
  自然留痕。
