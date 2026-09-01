# M3-fix1 修复台账（B-1 停滞根因修复 + 试炼 mods 消费端接线）

- 基线：main `b60b6de`（B-1 报告 m3-balance-w1 合入点）；worktree `m3-fix1`
- 驱动：`tools/balance_bot.gd`（本卡新增：挑战房灾厄处理、走图计划指针脱钩自愈、进房落位补齐、`--seeds=` 定向种子列表、因子观测采样；逐局落盘口径沿 B-1 不变）
- 关联：B-1 报告「阻塞项①」（69/100 停滞）与「试炼因子局空洞真」——本卡为该两项的独立修复卡；B-1 报告原文不回改，本台账直接引用

---

## 缺陷一（P0）：刷怪不变量兜底 → 停滞（B-1 实测 69/100 局房间永不可清）

### 1.1 证据链（fix1 卡内带快照探针逐种子复现）

B-1 把停滞归因为「filter_spawn_points 兜底丢不变量 → 敌人 NaN 坐标」单因。fix1 以带 STALLPROBE 快照的 bot 逐种子取证，实证停滞实为**多家族叠加**，且主家族与 B-1 的归因不同：

| 家族 | 机制 | 探针证据（文件:行 + 复现种子） |
|---|---|---|
| A：挑战房灾厄面板死等 | m2-t26 挑战房进门弹「灾厄 4 选 1」UI、选定才开战（`core/rooms/floor_scene.gd` `enter_room → _open_calamity_panel`）。bot 无 UI 交互能力（B-1 bot 仅处理 EventRoom），房间锁定后波次永不启动 | seed **3004**：`STALLPROBE room=1(combat) locked=true cleared=false wave_idx=-1 spawned_wave=-1 enemies=0 alive=0` 持续 180s。`wave_idx=-1` 说明 `RoomFlow.on_entered` 从未执行——**房里根本没有怪**，与「怪不可杀尽」表象不同 |
| B：刷怪点全过滤兜底丢不变量 | `core/rooms/room_combat.gd` `filter_spawn_points` 旧实现（:109）在全点位被过滤时原样返回全量点位（丢弃 ≥64px 距门 / ≥120px 距玩家不变量），怪可刷在玩家贴脸位甚至门体上 | 探针实测触发：小房（内域约 336×208）5 刷点在玩家居中时全部落入 120px 圈 → 兜底把怪刷在离玩家 35px 处（points=[(504,72),(680,72),(504,152),(680,152),(600,72)]，player=(590.5,105.9)）。此为**产品侧公平性/可清性缺陷**（真人玩家贴住刷点蹲守同样触发），与本卡修法见 1.2① |
| C：敌人 NaN 坐标（B-1 预警洪水源头） | `core/enemies/enemy_base.gd` 表现层 `velocity = (brain_pos - global_position) * FPS; move_and_slide(); brain_pos = global_position` 构成污染回路：brain_pos 一旦非有限即入 velocity → move_and_slide 把 global_position 写成 NaN → 拍末回写 brain_pos → 永久污染（敌人成「冻结的不可伤幽灵」+ 引擎 normalize 每帧告警，B-1 实测 20min 259 万行可拖垮进程） | 注入瞬间的栈级复现未在 fix1 探针窗内抽中（3001/3004/3033/3103 等种子数轮 6min 窗均未出现非有限坐标）；按任务标准「检测→重置→留痕、不跨拍存活」落地防御（1.2③），回归批 `enemy_nan_reset` 遥测零触发（见 2.1） |
| D：bot 走图计划指针与 flow 脱钩 + 玩家滞留旧房（fix1 新发现） | 生产 `_detect_room_enter`（`floor_scene.gd`）按**玩家物理位置**回写 flow；bot 的走图计划指针（M3-B1 改为只进不退的索引制）一旦被弹回的 flow 甩在身后即永久脱钩——`enter_room(计划目标)` 每拍失败、`_push_back` 每拍把玩家拽回旧房中心，原地空转；或指针被甩到计划尾后 `-1` 空转 | seed **3010**：`STALLPROBE room=1(shop=2 邻) locked=false cleared=true … PLAN idx=2 nxt=3 nxtadj=FALSE`（room 1 邻接=[0,2]）→ enter 每拍失败、ppos 恒=(176,-304)=room 1 中心。seed **3021**：房 1 全清（wave=2 alive=0）但 bot 冻结在房内 170s 不动 |

种子级对照口径（B-1 披露延续）：敌人 AI 消费 `Engine.get_physics_frames()` 相位（orbiter 俯冲 `frame%180`、shooter 横移 `frame/60%2`），进程启动偏移使逐种子结局**不可逐字节复现**（同种子两次分别得停滞 202s / 死亡 14s）——回归结论按分布口径。

### 1.2 修复设计（全部落在 bot/产品既有接缝上）

① **刷怪过滤渐进放宽**（`core/rooms/room_combat.gd`，家族 B）：
- 全过滤时不再原样返回全量点位，改为双阈值同步按 `SPAWN_RELAX_STEP_PX=8px`/档渐进放宽，取「首个非空档」= 最小必要放宽量（能不放宽就不放宽，保不变量本意）；
- 命中非空档后按「离玩家距离降序」输出（同距按输入序稳定排序）——波次刷怪依次取点，首怪必落离玩家最远的合法点（保进度、保公平）；
- 放宽至 0 阈值必有非空档（点位非空时）→ 任何点位组合都有怪可刷 → 房间必可清；`push_warning` 带放宽档位留痕；
- 零漂移：任一点位在完整阈值下合法时走原路径、输入序原样返回（不排序、不放宽）。

② **EnemyBase 非有限坐标防御**（`core/enemies/enemy_base.gd` `ensure_finite_position`，家族 C）：每物理帧表现层入口跑（房间 brain_tick 之后同拍）：检测（`brain_pos`/`global_position` 任一非有限）→ 重置到 `combat_bounds` 内域中心（脑测空 bounds 回原点）→ `push_warning` + Telemetry `enemy_nan_reset` 各留痕一次 → 返回 false 当拍跳过表现层。**NaN 不跨拍存活**：下一拍坐标已有限，守卫零干预。

③ **bot 走图三项修复**（`tools/balance_bot.gd` + 新落位缝 `FloorScene.push_player_back`，家族 A/D）：
- 挑战房灾厄 4 选 1：面板可见时经生产测试缝 `FloorScene.choose_calamity(CalamityPanel.CALAMITY_IDS[0])` 选定（等价面板选卡；固定选首项 `enemy_speed`，与 EventRoom「一律接受」同级的 bot 策略披露）；
- 走图计划指针脱钩自愈：仅当「计划目标与 flow 实际房不邻接（按计划走不到）」时，把指针向后回拨到当前房在计划中的最近出现位——重走的都是已清路标房（enter 幂等），绝不跳过未访房；正常邻接推进零触发，锁房战斗期该函数不被调用（无 M2 震荡回归面）；
- 进房落位补齐：`enter_room(nxt)` 成功后若玩家物理位不在新房外框内，经新落位缝 `FloorScene.push_player_back()`（生产 `_push_back` 同一实现）把玩家放进 flow 当前房中心——消除「锁房战斗玩家不在场」与 `_detect_room_enter` 的 1↔2 每拍振荡。

### 1.3 回归数据（B-1 停滞种子样本 20/69，修复后复跑）

- 样本：B-1 的 69 个停滞种子按序取前 20（3001、3004、3009-3011、3013-3015、3017-3018、3020-3022、3024-3026、3029-3030、3033-3034）；`--max-frames-per-run=32400`（9 min，> 180s 停滞判定窗的 3 倍）；逐局落盘 `docs/superpowers/reports/m3-fix1-stall-regression-{a,b}.json`。
- **结果：20 局 → 停滞 0（B-1 同种子 20/20 全停滞）；20 局全部以合法战斗死亡终局**（A 批 10 死 / B 批 10 死；死因谱系=苦力虫自爆/弩兵弹幕/精英接触，与 B-1 死亡局同谱系——停滞样本转化为有效对局后 bot 暴露的是 TTK/生存端压力，与 B-1「阻塞项② 修订窗口」预期一致）。
- 中位时长从「停滞判定的 ~200s 空转」变为 17-163s 的有效对局；最深推进 3 房 26 杀（seed 3034，死于精英双刀蜥人）。

---

## 缺陷二（P1）：试炼 mods 零 gameplay 消费者

### 2.1 设计：白名单 10 键 × 单一消费端

新增 `core/meta/trial_mods.gd`（`TrialMods`）：data/trials.json mods 白名单 10 键逐一提供唯一读取函数，各系统只经本类消费 `RunState.mods`（R-A 单点注入通道），零散读 trials.json。零漂移契约：普通局 mods 恒 `{}` → 全部函数恒等返回（`tests/unit/test_trial_mods.gd` 17 例逐键钉死）。

| # | mods 键 | TrialMods 读取点 | 系统消费端 |
|---|---|---|---|
| 1 | `enemy_speed_pct` | `enemy_speed_scale()` | `EnemyBase._physics_process` 体速式 ×倍率（走/冲/绕行全原型一处生效；×1.0 为 IEEE 精确恒等） |
| 2 | `enemy_attack_speed_pct` | `enemy_attack_speed_scale()` | `EnemyBase._windup_ticks`（既有统一钩子）+ 新 `_attack_cooldown_ticks`（收敛 6 处 `maxi(cd−windup,0)` 字面重复）+ shooter 连发间隔；拍数 ÷倍率 |
| 3 | `bullet_speed_pct` | `enemy_bullet_speed_px(base)` | `EnemyBase.enemy_bullet_speed()` 读行键，替换全部敌弹速度读点（含 5 Boss/3 精英/turret 激光/undead_gunner 弹形复制统一口径）；慢弹等比提速、快弹封顶 150px/s（GDD §7.5，上限不倒扣存量快弹）；windup 预警时间不受此键影响 |
| 4 | `drop_melee_only` | `drop_melee_only()` | `ShopLogic.roll_weapon_id(..., melee_only)`（桶内 category=="melee"，掷签消费序列不变）+ FloorScene 嘉宾/宝箱掉落两调用点 + `_roll_weapon` 哨兵池 |
| 5 | `energy_cost_mult` | `player_energy_cost(cost)` | `WeaponRig.try_fire` 开火蓝耗 `ceil(×倍率)`（0 耗 ×1.5 仍 0 字面语义；技能蓝耗不经此处） |
| 6 | `shop_discount_pct` | `shop_price(price)` | `Shop._haggled_price` 售价漏斗（武器/饮料；取整到 5、下限 5）；道具卡走固定价 + 试炼折让、不过玩家议价（保 m2-t35「道具固定价不参与议价」钉死契约） |
| 7 | `no_hearts` | `no_hearts()` + `HEART_DROP_COIN_EQUIV=12` | `Shop`（红心卡隐藏 + `_buy_item` 拒售）+ `FloorScene._spawn_pickup`（红心掉落位 → 12 等值金币；等值口径：商店红心 25 金币回 2HP → 每 HP 12.5 向下取整） |
| 8 | `vision_scale` | `vision_scale()` | `FloorScene._apply_trial_vision`（setup 挂 BiomeFx 整层暗视野，独立层灰=f、光圈/剪影同比 ×f；有 A2 生态层时 `BiomeFx.apply_vision_scale_min` 取更暗者不双乘；房清不还原） |
| 9 | `elite_bonus_pct` | `elite_extra_copies()` | `FloorScene._spawn_wave`：精英房波次内 `GUEST_SPECS kind=="elite"` 标记体追加同 id 体（100% → 双精英）；同 wave_id 由 RoomFlow 按出现次数计数，快照遍历防链式翻倍 |
| 10 | `force_element` | `floor_force_element(floor_idx)`（run_seed+floor 经 RngSvc.stable_hash 确定性派生） | `WeaponRig.element_hit_profile`：本层一切元素附魔（武器自带/增益/星髓像临时附魔）统一转为层元素；proc 概率与「临时独立覆盖」结构保留 |

遥测留痕：`trial_vision` / `trial_heart_to_coins` / `trial_elite_bonus` Telemetry 行 + bot 观测采样字段（3.2）。

### 2.2 规格边界执行披露

- `elite_surge` 的「战斗房 15% 增益祭坛概率改为追加 1 精英」半边：本基线不存在「战斗房增益祭坛」设施（floor_scene 设施仅 shop/event/雕像/熔铸台，模板无该字段）——**按规格「未覆盖情形上报编排者」处理不自行定夺**，本卡只落地精英房 ×2 半边。
- `bullet_haste` 预警时间不减免：windup 拍数只受 `enemy_attack_speed_pct` 缩放，两键解耦 ✓。
- `narrow_vision` 与 A2 叠加取更暗者：`apply_vision_scale_min`（min 语义，非连乘）✓。
- `single_element` 的「HUD 显示本层元素」属 R-B（面板/角标）范畴，本卡未触碰 ui/。
- m2-t35 契约兼容：道具价只吃试炼折让、不吃玩家议价（`test_meta_wiring::test_shop_applies_haggle_to_weapon_and_drink_prices` 保持绿）。

---

## 3. 回归与复测数据

### 3.1 停滞复验（B-1 停滞种子样本 20 个）——停滞 20 → 0

| 批 | 种子 | 结果 |
|---|---|---|
| A | 3001,3004,3009,3010,3011,3013,3014,3015,3017,3018 | **10 死 / 0 停滞** |
| B | 3020,3021,3022,3024,3025,3026,3029,3030,3033,3034 | **10 死 / 0 停滞** |

20 局全部以合法战斗死亡终局（B-1 同种子 20/20 停滞）。逐局数据：`m3-fix1-stall-regression-{a,b}.json`。口径：`--max-frames-per-run=32400`（9min）；A/B 两进程并行（B-1 披露的 save 跨局累积口径延续，分布对照）。

### 3.2 因子局复测（seeds 3101-3110，`--trial=2026-09-01`，普通局同种子基线对照）

- 试炼批：**10/10 完成、0 停滞**（9 死 + 1 超时=270s 帧帽时仍在推进）；**seed 3110 推进到 F1 Boss 房（11 房 50 杀，死于 Boss 蘑菇孢子手）——bot 回归史上最深对局**，证明因子局在修复后的基线上是「更难但可玩」的有效对局。
- 对照批（同种子普通局）：7 死 / 2 超时（均推进中）/ **1 停滞**（3103，见 3.3 残余）。
- 因子改变 gameplay 的遥测证据（`obs_*` 观测采样，逐局落盘 `m3-fix1-factor-{baseline,trials}.json`）：
  - `bullet_haste`（3104/3107）：敌弹实速均值 **110 → 138 px/s**（110×1.25=137.5，等比提速精确吻合规格）；
  - `enemy_haste`（3101/3106）：活敌实速均值 **50→71** / **39→55**（差分度量含绕行几何，方向与幅度同向）；
  - `melee_drops`/`bargain_ban`：落盘掉落台/红心采样在死亡局未自然触发（对局早夭），行为由单测钉死（近战池过滤/红心拒售/折价）；
  - `energy_tax`/`force_element`/`vision_scale`/`elite_surge`：单测逐键断言 + 消费端遥测行落库（`trial_vision`/`trial_elite_bonus` 等）。
- 对照 B-1 试炼批「因子局与普通局轨迹无差」疑点：本批因子局在敌速/弹速/推进深度上均与普通局可区分（3110 打到 Boss、3104/3107 弹速 +25%），疑点关闭。

### 3.3 残余停滞（低频，已定位未修）

对照批 seed 3103 出现 1 例战斗中冻结（rooms=0 kills=2，183s；近 33 局普通/因子对局中 1 例 ≈3%，B-1 为 69%）。探针快照：弩兵 ENGAGE 态钉在内域墙沿（gp x≈32.07=内域左边界）风筝走位卡墙，bot 瞄准保持命中 2 次后不再命中——属「钉墙风筝敌 × bot 瞄准保持」的 bot 能力残差（真人玩家可走位补枪），与刷怪不变量/NaN/走图脱钩均无关。建议后续 bot 能力卡处理；产品侧四项修复（1.2①②③）不阻塞于此。

---

## 4. 测试

- 全量：`cmd //c tools\run_tests.cmd` —— **1622/1622 通过（0 失败 0 错误）**，较 B-1 基线 1598 净增 24（试炼 mods 17 + NaN 守卫 4 + 刷怪过滤净增 3）。
- 新增/改写用例：
  - `tests/unit/test_trial_mods.gd`（17）：10 键逐键「无因子恒等 + 注入后可断言改变」双层断言（含商店 UI 红心折价/拒售、BiomeFx 取更暗者、近战池过滤掷签序列零漂移、force_element 分层确定性与附魔统一、elite 波次扩増快照遍历防链式翻倍）。
  - `tests/unit/test_enemy_nan_guard.gd`（4）：NaN/inf 检测→重置→velocity 清零、恢复后零干预、空 bounds 回原点。
  - `tests/unit/test_room_flow.gd`（+3 净改）：渐进放宽的最小档/最远优先/零漂移/永非空四性质，替代旧「原样返回全量点位」钉死用例。
- 顺带记录（评审备忘）：`Array(Array(x))` 链式构造在本基线实测会别名共享（追加互见、循环失控至 OOM 守卫截断），集合拷贝一律 `duplicate()`（test_trial_mods 内有注释钉存证）。

## 5. 残余风险

1. **~3% 低频战斗中冻结**（3.3）：钉墙风筝敌 × bot 瞄准保持，bot 能力残差，非产品缺陷；真人不可复现为「永不可清」。
2. **敌 AI 相位非确定性**：`Engine.get_physics_frames()` 相位消费（orbiter/shooter）使逐种子结局不可复现（B-1 披露延续，本卡探针再次实证）；跨批对比只有分布意义。
3. **save 跨局/跨批累积**（B-1 披露延续）：本卡回归 A/B 并行执行，save_headless.json 写入存在竞态窗口（仅图鉴/解锁计数维度，分布对照口径不受影响）。
4. **试炼结算/排行榜/成就**（R-B/R-C）与 `single_element` HUD 显示不在本卡范围；`elite_surge` 增益祭坛半边待设施落地后补接线（2.2）。
5. 停滞清零后 bot 全部死于 F1 压力（20/20 死亡、中位时长 <2min）：TTK/生存端偏离（B-1 台账 A1 杂兵 TTK 4.7s vs ≤2.0s 带）的数值修订窗口现已解除阻塞，建议校准卡复跑全量 100 局再判带。
