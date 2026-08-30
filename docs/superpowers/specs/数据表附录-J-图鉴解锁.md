# 数据表附录 J：图鉴解锁任务（M2-T3 定稿）

> GDD 契约出处：数据表附录 A「解锁规则」（紫/橙 49 把默认锁定，图鉴任务解锁后进掉落池；示例：击杀 300 敌人解锁「哑火者」、完成 10 次熔铸解锁「湮灭号角」）、设计文档 §8.1（49 把 = 约 42% 内容构成 20h 长线目标）与 §14.3（20h 图鉴解锁 80%）。
> 本文为图鉴解锁任务全表定稿（设计 + 数据卡）：49 条 = `data/weapons.json` 全部 `locked:true` 武器（紫 33 + 橙 16）逐一给出解锁条件。
> 数据文件 `data/unlock_tasks.json`（纯数据卡，FileAccess 直读，暂不经 GameDB 装载）；契约测试 `tests/unit/test_unlock_data.gd`（schema 自校验 fail-closed，照抄 T2 `test_talents_data.gd` 模式）。
> 系统落地消费方：M2-T20（`core/meta/codex_system.gd`：`progress(task_id) -> {cur, goal}`，解锁→`SaveSystem.unlocked` + 武器进掉落池）、M2-T25（存档 v2：计数器持久化字段）、M2-T33（成就系统共享计数源）。

## J.1 任务 Schema（契约）

每任务 7 键全部必填，无 optional；任一键缺失/类型错/语义校验失败 → 整行拒收（fail-closed）。表键 = `id` = `weapon`（任务 id 即武器 id，M2-T3 与 weapons.json locked 集合双向一致的机器锁定项）。

| 键 | 类型 | 约束 |
|---|---|---|
| `id` | String | 任务 id（= 表键 = 目标武器 id，snake_case） |
| `weapon` | String | 目标武器 id，必须与 `id` 相等 |
| `type` | String | 条件类型 ∈ J.2 白名单（6 选 1） |
| `param` | int | 条件参数：`clear_floor_x` = 层号 1..3；其余类型固定 0（不限子类，预留扩展位） |
| `goal` | int | 阈值，> 0；刻度带见 J.5 |
| `forge_only` | bool | true = ★熔铸限定（恰 4 把，J.6）；其余 false |
| `desc` | String | 中文条件文案（图鉴 UI 直读；必须包含阈值数字，`clear_floor_x` 另含层号——测试锁定） |

JSON 数字解析为 float 的整值还原口径与 `GameDB._normalize_row` 一致（带小数留在 float → 类型校验拒收）。

## J.2 条件类型白名单与判定数据

| type | 语义 | param | goal | 判定数据（遥测/RunState → T25 持久化计数器） |
|---|---|---|---|---|
| `kill_x` | 累计击杀敌人 | 0 | 击杀数 | Telemetry `kill` 行计数 → `counters.kills_total` |
| `clear_floor_x` | 通过指定层 | 层号 1..3 | 通过次数 | `floor_clear` 事件（按层分桶）→ `counters.floor_clears[i]` |
| `craft_x` | 累计完成熔铸 | 0 | 熔铸次数 | 熔铸台 `item_forged` 事件 → `counters.crafts_total` |
| `resonate_x` | 累计触发元素共鸣 | 0 | 共鸣次数 | `EventBus.resonance_triggered`（既有信号）→ `counters.resonances_total` |
| `collect_gems_x` | 累计获得蓝晶 | 0 | 蓝晶枚数 | 层通过/击杀/首杀/成就蓝晶入账事件 → `counters.gems_earned_total` |
| `buy_x` | 累计商店购买 | 0 | 件数 | 商店/饮料机成交事件 → `counters.purchases_total` |

全部 6 类可由既有遥测行或 RunState 字段判定；**计数一律为跨局累计口径**（本局值由 RunState/Telemetry 会话计数提供，入档聚合由 M2-T25 migration v2 落地）。解锁判定 = `progress(task_id).cur >= goal`（M2-T20 实现）。

## J.3 分配原则（编排者裁定③ + 武器特性）

1. **附录 A 既定示例优先照录**（数值唯一出处，Global Constraint 3）：哑火者 `kill_x 300`、湮灭号角 `craft_x 10`。
2. **裁定③**：4 把★熔铸限定（星陨炮/雷神之锤/斩舰刀/湮灭核心）条件类型一律 `craft_x`（熔铸获取），并携带 `forge_only:true`（J.6）。
3. **元素武器 → `resonate_x`**：`weapons.json` 中 `element != none` 的 12 把（紫 11 + 橙 1 电磁轨道）——元素附魔是共鸣玩法的输入，解锁线与玩法线同构。
4. **共鸣特性武器 → `resonate_x`**：彩虹发生器（四元素每 1s 轮换）、星核榴弹（必触发已有异常的共鸣）——特性文本直接绑定共鸣；光学分裂系（棱镜权杖、镜面杖）同归此线（分光/分裂视觉即共鸣表达）。
5. **直射/穿透/近战输出向 → `kill_x`**：狙击重炮、高伤近战、速射清怪系（含穿棱镜「穿透一切」、老兵「资历」）。
6. **层进阶向 → `clear_floor_x`**：紫档挂 A2（param 2）、橙档挂 A3（param 3）——紫武 = 中期推进奖励，橙武 = 毕业推进奖励。
7. **功能/资源向 → `buy_x` / `collect_gems_x`**：特殊类功能件（分身信号弹、传送标枪、时间沙漏）走经济线；星辉/星核/黑洞主题走蓝晶积累线。

## J.4 全表（49 条）

### 紫 / 史诗（33）

| id | 名称 | 类别 | 条件 | 阈值 | forge_only |
|---|---|---|---|---|---|
| `yahuozhe` | 哑火者 | pistol | kill_x | 300 | — |
| `dianque` | 电雀 | pistol | resonate_x | 120 | — |
| `yingwan` | 影丸 | pistol | kill_x | 400 | — |
| `shezhezhe` | 折射者 | smg | kill_x | 350 | — |
| `bingzhuiji` | 冰锥机 | smg | resonate_x | 150 | — |
| `duyepensa` | 毒液喷洒 | smg | resonate_x | 150 | — |
| `cibao` | 磁暴 | smg | resonate_x | 180 | — |
| `laobing` | 老兵 | rifle | kill_x | 600 | — |
| `ranshaodanlian` | 燃烧弹链 | rifle | resonate_x | 150 | — |
| `donghehe` | 冻结核 | rifle | resonate_x | 150 | — |
| `longxi` | 龙息 | shotgun | resonate_x | 200 | — |
| `liuhuang` | 硫磺 | shotgun | resonate_x | 200 | — |
| `suijingpao` | 碎晶炮 | shotgun | resonate_x | 200 | — |
| `huoshenzhongpao` | 火神重炮 | sniper | kill_x | 450 | — |
| `duantoutai` | 断头台 | sniper | kill_x | 500 | — |
| `guanri` | 贯日 | sniper | clear_floor_x(A2) | ×2 | — |
| `liedizhe` | 裂地者 | sniper | kill_x | 550 | — |
| `lengjingquanzhang` | 棱镜权杖 | laser | resonate_x | 260 | — |
| `dianhubian` | 电弧鞭 | laser | resonate_x | 250 | — |
| `chuanlengjing` | 穿棱镜 | laser | kill_x | 450 | — |
| `yunshizhang` | 陨石杖 | staff | clear_floor_x(A2) | ×3 | — |
| `xinghuizhang` | 星辉杖 | staff | collect_gems_x | 1200 | — |
| `jingmianzhang` | 镜面杖 | staff | resonate_x | 240 | — |
| `huixuanrengong` | 回旋刃弓 | bow | kill_x | 400 | — |
| `leimingnu` | 雷鸣弩 | bow | resonate_x | 260 | — |
| `fenliejian` | 分裂箭 | bow | kill_x | 380 | — |
| `diancimaichonglei` | 电磁脉冲雷 | throw | kill_x | 420 | — |
| `xuewenci` | 血蚊刺 | melee | kill_x | 500 | — |
| `zhuixingdajian` | 坠星大剑 | melee | clear_floor_x(A2) | ×1 | — |
| `guangjian` | 光剑 | melee | clear_floor_x(A2) | ×2 | — |
| `fenshenxinhaotan` | 分身信号弹 | special | buy_x | 25 | — |
| `chuansongbiaoqiang` | 传送标枪 | special | buy_x | 30 | — |
| `wurenjimujian` | 无人机母舰 | special | collect_gems_x | 1000 | — |

### 橙 / 传说（16）

| id | 名称 | 类别 | 条件 | 阈值 | forge_only |
|---|---|---|---|---|---|
| `zhongyanjicu` | 终焉急促 | smg | kill_x | 1000 | — |
| `caijue` | 裁决 | rifle | clear_floor_x(A3) | ×1 | — |
| `yaniemhaojiao` | 湮灭号角 | shotgun | craft_x | 10 | — |
| `xingyunpao` | ★星陨炮 | sniper | craft_x | 8 | ✓ |
| `dianciguidao` | 电磁轨道 | sniper | resonate_x | 800 | — |
| `shenpanzhiri` | 审判之日 | sniper | kill_x | 1200 | — |
| `caihongfashengqi` | 彩虹发生器 | laser | resonate_x | 1000 | — |
| `guidaobiaojiqi` | 轨道标记器 | laser | clear_floor_x(A3) | ×2 | — |
| `zhongyanzhizhang` | 终焉之杖 | staff | clear_floor_x(A3) | ×3 | — |
| `guanxinggong` | 贯星弓 | bow | kill_x | 900 | — |
| `heidongfashengqi` | 黑洞发生器 | throw | collect_gems_x | 5000 | — |
| `xingheliudan` | 星核榴弹 | throw | resonate_x | 900 | — |
| `leishenzhichui` | ★雷神之锤 | melee | craft_x | 6 | ✓ |
| `zhanjiandao` | ★斩舰刀 | melee | craft_x | 10 | ✓ |
| `shijianshalou` | 时间沙漏 | special | buy_x | 60 | — |
| `yamiehexin` | ★湮灭核心 | special | craft_x | 12 | ✓ |

## J.5 分布统计与节奏校准

**类型分布（测试锁定）**：

| type | 紫 | 橙 | 合计 |
|---|---|---|---|
| kill_x | 12 | 3 | 15 |
| resonate_x | 13 | 3 | 16 |
| clear_floor_x | 4（全 A2） | 3（全 A3） | 7 |
| craft_x | 0 | 5（4★ + 湮灭号角） | 5 |
| collect_gems_x | 2 | 1 | 3 |
| buy_x | 2 | 1 | 3 |
| **合计** | **33** | **16** | **49** |

**阈值刻度带（测试锁定；紫前段 / 橙后段，带内取值）**：

| type | 紫（epic） | 橙（legend） |
|---|---|---|
| kill_x | 300 ~ 600 | 900 ~ 1200 |
| resonate_x | 120 ~ 260 | 800 ~ 1000 |
| clear_floor_x | A2 ×1..3 | A3 ×1..3 |
| craft_x | —（紫无熔铸线） | 6 ~ 12 |
| collect_gems_x | 1000 ~ 1200 | 5000 |
| buy_x | 25 ~ 30 | 60 |

**节奏校准（GDD §14.3「20h 图鉴解锁 80%」≈ 39/49 条）**：

- 速率假设（M1 门禁实测口径）：单局 25~35min（≈2 局/h）；击杀 ≈ 400~500/h；蓝晶 ≈ 500~700/h；共鸣 ≈ 10~20/局（元素构筑成熟后 30+/局）；熔铸 ≈ 2~3/局（通用每局限 2 次 + 固定配方）；购买 ≈ 8~12/局。
- 紫档带 → 单条 1~6h 自然完成（33 条构成前 80% 主体）；橙档带 → 单条 6~20h；★与共鸣重橙（craft 12 / resonate 1000）为 20h 后长尾，与「20h 解锁 80%」契约吻合（最后 ~10 条即长尾）。
- 阈值在带内按武器强度微调（如老兵 600 > 折射者 350；审判之日 1200 = 全表击杀上限，对应其全屏光柱定位）。

## J.6 forge_only 与掉落池契约（M2-T20 消费约定）

- `weapons.json` 的 `locked:true`（M2-T6）表示**未解锁**：GameDB 装载时移出 `weapons` 掉落池、全量留在 `weapons_all` 供图鉴展示。
- M2-T20 解锁引擎达成任务后：`SaveSystem.unlocked` 记录武器 id，掉落池过滤改为 `locked && id ∉ unlocked` → 解锁武器进普通掉落池。
- **★4 把（`forge_only:true`）例外**：解锁后**仍不入普通掉落池**，只保留熔铸产出路径（附录 D 固定配方）——图鉴只点亮条目。T20 的池过滤必须同时检查 `unlock_tasks[id].forge_only`（该键即为本约定在数据面的落地，weapons.json 无需也不得加此键）。
- 计数器持久化：M2-T25 存档 v2 的 `unlock_tasks` 进度字段（J.2 六类计数器）；M2-T33 成就系统复用同一计数源（计划卡 T33 明文）。

## J.7 增益效果键白名单扩展（M2-T3 定稿 → M2-T12 消费）

`data/buffs.json` 现有 16 条（M1），附录 C 全 36 条 → 剩余 20 条新增益（T12 转录；计划卡行文「+21」，与附录 C 实际清点 36−16=20 差 1，见 J.9）。本节定稿其效果键扩展白名单：**新键 21 个覆盖 20 条**（共鸣增幅占 2 键）。键名与 T12 卡已声明聚合键（`haggle_pct, heart_sense_pct, pickup_radius_pct, phoenix_flag, anti_fire/ice/poison, element_vision, vengeance_pct, wealth_pct…`）逐字对齐。T12 须同步扩展 `GameDB.BUFF_PCT_KEYS/BUFF_INT_KEYS` 并新增 BOOL 键组；**本卡不改 `data/buffs.json`**（文件所有权归 T12）。

| 新键 | 类型 | 幅度 | 增益（附录 C） | 消费卡号 |
|---|---|---|---|---|
| `wealth_pct` | float | 0.20 | 财富：金币获取 +20% | M2-T12 → Pickup 金币结算（T31 复核） |
| `big_eater_pct` | float | 0.50 | 大胃王：饮料效果 +50% | M2-T12 → DrinkMachine |
| `pickup_radius_pct` | float | 0.60 | 捡拾磁铁：拾取范围 +60% | M2-T12 → Pickup.MAGNET_RANGE_PX 乘区 |
| `heart_sense_pct` | float | 0.50 | 红心感应：红心掉率 +50% | M2-T12 → 掉落 roll |
| `energy_siphon_pct` | float | 0.10 | 蓝能汲取：击杀 10% 概率回 2 蓝 | M2-T12 → kill 钩子（能量系统） |
| `ammo_convert_energy` | int | 10 | 弹药转化：每 30s 被动回 10 蓝 | M2-T12 → 周期计时器 |
| `haggle_pct` | float | 0.15 | 议价：商店价格 −15% | M2-T12 → ShopLogic 价格乘区 |
| `element_vision` | int | 9（ticks） | 元素视界：弹幕/激光预警 +0.15s | M2-T12 → 预警组件（T7 警示线加时消费） |
| `resonance_vision_flag` | bool | true | 共鸣视界：异常状态敌人高亮描边 | M2-T12 → 敌人渲染钩子 |
| `vengeance_pct` | float | 0.25 | 复仇者：受击后 3s 伤害 +25% | M2-T12 → DamageCalc 条件乘区 |
| `hunter_vs_status_pct` | float | 0.20 | 猎杀者：对异常目标伤害 +20% | M2-T12 → DamageCalc 条件乘区 |
| `resonance_radius_pct` | float | 0.30 | 共鸣增幅：共鸣 AoE 半径 +30% | M2-T12 → core/combat/resonance.gd |
| `resonance_duration_ticks` | int | 60 | 共鸣增幅：持续 +1s | M2-T12 → core/combat/resonance.gd |
| `nerve_reflex_ticks` | int | 15 | 神经反射：受击无敌帧 +0.25s | M2-T12 → Player.apply_iframes |
| `bullet_resist_pct` | float | 0.08 | 甲壳：受弹幕伤害 −8% | M2-T12 → 受击结算 |
| `thorns_dmg` | int | 3 | 荆棘护甲：被接触时反伤 3 | M2-T12 → 接触伤害回调 |
| `dash_extend_pct` | float | 0.25 | 冲刺延伸：翻滚距离 +25% | M2-T12 → 翻滚冲量乘区 |
| `phoenix_flag` | bool | true | 不死鸟（唯一）：致死保留 1 HP，每局 1 次 | M2-T12 → Player 死亡拦截 |
| `anti_fire` | bool | true | 抗火：免疫燃烧；岩浆伤害 −50% | M2-T12 → status（T10 hazard_magma 岩浆减半消费） |
| `anti_ice` | bool | true | 抗冰：免疫冰缓与冰面打滑 | M2-T12 → status（T4 ice_floor 打滑免疫消费） |
| `anti_poison` | bool | true | 抗毒：免疫中毒 | M2-T12 → status |

既有 15 键（`BUFF_PCT_KEYS` 9 + `BUFF_INT_KEYS` 6）语义不变，T12 对既有 16 条的「修正」只动数值不动键名（附录 C 修正口径归 T12 卡）。

## J.8 校验清单（`tests/unit/test_unlock_data.gd`，全部 fail-closed）

1. 文件可读可解析（FileAccess 直读，非 dict/不可读 → 空 dict → 计数断言失败）。
2. `validate_unlock_row`（行级，test 内 static）：7 键齐备且类型正确（float 整值还原口径）；`id == weapon`；type ∈ 6 白名单；goal > 0 int；`clear_floor_x` param ∈ 1..3、其余 param == 0；desc 非空。
3. 49 条计数；行键集合恰 7（无多余键）。
4. 与 `GameDB.weapons_all` 的 `locked:true` 集合**双向一致**（任务多了/少了都失败）。
5. 稀有度分布：紫 33 / 橙 16（join weapons.json）。
6. 类型分布锁定（J.5 表）；★4 把 `craft_x` + `forge_only:true`；非★ `forge_only:false`。
7. 阈值刻度带（J.5 表）+ 紫/橙梯度单调（kill/resonate/gems 紫 max < 橙 min；clear_floor 紫 param 2 < 橙 param 3）。
8. desc 文案含阈值数字（与 `goal` 字段一致；`clear_floor_x` 另含层号）。
9. 行级校验器负样本：坏 type / goal ≤ 0 / 小数 goal / 越界 param / 非 floor 带 param / 缺键 / id≠weapon / 空 desc / forge_only 非 bool。

## J.9 与规格出处的计数勘误（上报留档）

- 附录 C 全 36 条 − M1 已有 16 条 = **剩余 20 条**新增益；计划卡 T12 行文「+21 → 36」按 16+21=37 计，与附录 C 实际总和差 1。本卡按附录 C（数值唯一出处）实际清点 20 条出具白名单（21 个新键，共鸣增幅占 2 键）；若 T12 按「21 条」执行，多出的 1 条以附录 C 全表为准对齐，键须落入本白名单或由 T12 卡补宣言。
