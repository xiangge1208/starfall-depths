# M2 Balance Bot 全层回归报告（2026-09-03 · Task 27 / H-1 · m2-t28）

- 驱动：`tools/balance_bot.gd` 无头自动游玩（启发式走位/避弹/避爆炸域/避 hazard/环绕走位/索敌开火/概率翻滚/商店买红心/事件一律接受/三选一贪心），hero=vanguard（m4-c2 --hero 参数，缺省 vanguard），headless 墙钟速率（引擎 time_scale 对本作逐拍定步长逻辑无加速效用，物理拍=真实玩家体验时长）
- 决策纯逻辑：`tools/balance_bot_decisions.gd`（确定性，tests/unit/test_balance_bot_decisions.gd 钉死）；校准点机器值：tests/unit/test_balance_bot_calibration.gd 钉死
- 局数：2（种子 2401..2402）｜崩溃：0｜超时中止：0

## 内容覆盖前提（先读这段再读数据）

- **本批回归基线 = main c676657：仅第 1 层为完整可玩内容。** A2/A3 房间模板在 T26（并行在途，含修复轮）；`run_root._floor_data_available(2)` 为假 → 过第 1 层层间门后进入生产「A2 入口里程碑」（`a2_entry_active()`，Task 20/26 定义的最小可玩端点），bot 记为终局 `milestone_a2`。
- 因此 **生产胜利（第 3 层 Boss 链）在本基线不可达，§14.3 胜率带（20%~40%）本批「不可评」**——如实标注，不调数值凑数。可评口径：第 1 层内的死亡热房 / TTK / 房间与单层时长 / 蓝晶曲线 / 内容上限到达率（胜利或 milestone_a2 到达占比 = 0%）。
- 已知内容缺口（T26 合并后仍成立，T36 承接）：A2/A3 波次将仍用 A1 敌人名录、Boss 三层恒 vine_colossus——届时胜率/TTK 的含义仍受此限制：三层难度递进缺失使深层数据偏「同难度复读」，真实分层后胜率预计低于届时测量。
- T26 合并后同一 bot（零改动）自动续走 2/3 层并复评胜率带；本报告即「第 1 层全内容回归 + 骨架就绪证明」。

## 汇总（结局分布 + 可评带对照）

| 指标 | 实测 | §14.3 目标带 | 判定 |
|---|---|---|---|
| 生产胜率（第 3 层胜利） | 0/2 | 20%~40% | **不可评（本基线无 2/3 层内容）** |
| 内容上限到达率（win+milestone_a2） | 0% | -（本卡替代口径） | 有未走完局（超时/崩溃） |
| 单局时长(均值/中位) | 1.2 / 1.7 min | 25.0~35.0 min（单局口径） | 第 1 层子集，仅参考 |

## 逐局

| seed | 结果 | 止步 | 房间 | 击杀 | 时长(min) | 金币 | 蓝晶 | 买红心 | 增益选择 | 首杀可获 | 死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2401 | death | 第1层 | 4 | 22 | 1.7 | 0 | 0 | 0 | anti_poison | 否 | 苦力虫的自爆（elite） |
| 2402 | death | 第1层 | 1 | 10 | 0.6 | 0 | 0 | 0 | - | 否 | 苦力虫的自爆（combat） |

- 「首杀可获」= 该局开始时 vine_colossus 尚无 SaveSystem 首杀标记（击杀蓝晶 +300 只落批次首局，见局间隔离披露）。

## 死亡热房（死亡楼层 × 房型）

| 层:房型 | 死亡次数 |
|---|---|
| F1:elite | 1 |
| F1:combat | 1 |

## TTK / 节奏（对照 §14.3；本批全部为第 1 层口径）

| 指标 | 实测(中位/p90) | §14.3 目标 | 判定 |
|---|---|---|---|
| A1 杂兵 TTK | 5.4 / 18.2 s (n=31) | ≤2.0 s | 偏离 |
| 精英击杀 | 1.2 / 1.2 s (n=1) | （参考） | - |
| 战斗房时长 | 30.3 / 49.9 s (n=4) | 20.0~40.0 s | 达标 |

## 蓝晶获取曲线（每局层末快照；§14.1 过层 60/120/200 + 击杀档位）

| seed | F1 末(过层门快照) | 终局 |
|---|---|---|
| 2401 | 0 | 0 |
| 2402 | 0 | 0 |

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
- 因子一（输出端）：A1 杂兵 TTK 中位 5.4s 超出 §14.3「初始武器 ≤2.0s」。建议校准初始武器（laohuoji）基础伤害/攻速 +20%~30% 后复测。
- 因子三（生存端）：死亡热房 F1:elite（1 次）。若集中于特定房型，建议校准该房型敌方弹幕密度（§7.5 上限）或弹速 -10%~15%；死亡集中于 Boss 房则复核 P2/P3 弹幕量曲线。

## 接口边界与前提披露

- **接口边界**：bot 只经由生产接口操作——Input 移动、`PlayerDriver.touch_mode_override`（生产触屏 auto_aim 自动开火，手机玩家同路径）+ 战斗期按住物理 fire、`player.start_roll`/`Skill.cast`（CD/耗蓝守卫在生产侧）、`FloorScene.enter_room`（生产 enter_room→_push_back 落位，走廊徒步不模拟，同 m1_loop_smoke 惯例）、`Shop.interact` + `_buy_item("heart")`（RunState.spend_coins 扣款）、`EventRoom.accept`（bot 一律接受）、`Altar.interact` + `Altar.choose`（m4-c4 祭坛生产交互/选卡缝：增益分支同层间三选一贪心、elite_surge 分支交互即追加精英，逐局表 altars 列可查）、层间三回调。伤害/击杀/掉落/金币全部由生产战斗链路自然发生；bot 不使用熔铸台/雕像/饮料机（商店仅买红心）。
- **种子口径**：`RunState.start_run` 墙钟种子被 `RunState.run_seed = seed` + `RngSvc.setup_run(seed)` 确定性覆写（start_run 其余状态不变）；bot 决策采样用独立 `_rng`（同种子播种）——同 seed 可复现整局（bot 行为侧；敌人 AI 消费 RunState 盐流，同种子同确定性）。
- **局间隔离**：每局 `start_run` 重置局内状态；SaveSystem 原状保留（headless 自动重定向 save_headless.json，真档不受影响）——图鉴/成就计数与 Boss 首杀标记跨局累积（真实玩家成长模拟），vine_colossus 首杀 +300 只落批次首局（逐局表「首杀可获」列可查）。多局会推进 save_headless.json 的图鉴/解锁进度，属产品正确行为（裁定㉒口径）。
- **胜/死捕获**：生产测试缝 `run_root.victory_route_override` / `DeathRecorder.open_summary_override`（死亡报告 = DeathRecorder.build_report 生产口径）；终局蓝晶**不入档**（无 DeathSummary/VictorySummary 确认路径）。
- **内容缺口（前提，非本卡缺陷）**：本基线 A2/A3 层模板在 T26（并行在途）——本报告全部统计为第 1 层口径；A2/A3 就绪后波次仍为 A1 名录、Boss 恒 vine_colossus（T36 承接），届时报告继续注明该限制。

