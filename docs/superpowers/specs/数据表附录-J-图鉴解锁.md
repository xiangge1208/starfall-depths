# 数据表附录 J：图鉴解锁任务（M2-T3 定稿）

> GDD 契约出处：数据表附录 A「解锁规则」（紫/橙 49 把默认锁定，图鉴任务解锁后进掉落池；示例：击杀 300 敌人解锁「哑火者」、完成 10 次熔铸解锁「湮灭号角」）、设计文档 §8.1（49 把 = 约 42% 内容构成 20h 长线目标）与 §14.3（20h 图鉴解锁 80%）。
> 本文为图鉴解锁任务全表定稿（设计 + 数据卡）：49 条 = `data/weapons.json` 全部 `locked:true` 武器（紫 33 + 橙 16）逐一给出解锁条件。
> 数据文件 `data/unlock_tasks.json`（纯数据卡，FileAccess 直读，暂不经 GameDB 装载）；契约测试 `tests/unit/test_unlock_data.gd`（schema 自校验 fail-closed；fail-closed/负样本风格同 T2 `test_talents_data.gd`，装载机制为 FileAccess 直读独立校验——trials 数据卡先行模式，见评审 Minor ③勘误）。
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
| `collect_gems_x` | 累计获得蓝晶 | 0 | 蓝晶枚数 | 层通过蓝晶事件（附录 H 已定）→ `counters.gems_earned_total`；击杀/首杀/成就蓝晶入账口径依赖 M2-T32/T33 结算 |
| `buy_x` | 累计商店购买 | 0 | 件数 | `shop_purchase(kind)` 信号（K.2 声明；shop.gd/drink_machine.gd 现无购买信号/遥测，发射点归 M2-T35 接线卡）→ `counters.purchases_total` |

全部 6 类可由既有遥测行或 RunState 字段判定；**计数一律为跨局累计口径**（本局值由 RunState/Telemetry 会话计数提供，入档聚合由 M2-T25 migration v2 落地）。解锁判定 = `progress(task_id).cur >= goal`（M2-T20 实现）。

## J.3 分配原则（编排者裁定③ + 武器特性）

1. **附录 A 既定示例优先照录**（数值唯一出处，Global Constraint 3）：哑火者 `kill_x 300`、湮灭号角 `craft_x 10`。
2. **裁定③**：4 把★熔铸限定（星陨炮/雷神之锤/斩舰刀/湮灭核心）条件类型一律 `craft_x`（熔铸获取），并携带 `forge_only:true`（J.6）。
3. **元素武器 → `resonate_x`**：`weapons.json` 中 `element != none` 的 13 把（紫 11 + 橙 2：电磁轨道、★雷神之锤，均 shock）——元素附魔是共鸣玩法的输入，解锁线与玩法线同构；其中★雷神之锤已被规则 2（裁定③ craft_x）先行覆盖，故实际走 resonate_x 的为 12 把。
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

## J.7 增益效果键白名单扩展（权威 = M2-T12 实现）

**权威声明（评审 Major ① 勘误）**：本节原按 T3 预估出具 21 键；M2-T12（`.worktrees/m2-t12`，commit `137eed1` "feat(m2-t12): complete 36 buffs"）已并行落地 **25 个新效果键（11 pct + 8 int + 6 flag）**，并以 `GameDB.BUFF_PCT_KEYS/BUFF_INT_KEYS/BUFF_FLAG_KEYS` + `BuffManager.EFFECT_DEFAULTS/PLAYER_META_KEYS/RIG_META_KEYS` 为运行时白名单。**键名以 T12 实现为唯一权威**，本表按 T12 实键重排（原预估拆键差异：蓝能汲取/弹药转化/元素视界拆为对键、复仇者增设时长键）。T15（天赋 effects 键「复用 buff_manager 键」）及 T20/T33 一律按本表（= T12 实键）取名，**不得使用下节映射表中 T3 原名**。

拆键比预估多的原因：单键混合「概率 × 幅度」或「周期 × 数值」会迫使消费方硬编码伴生参数——T12 拆为对键（如 `kill_energy_chance` + `kill_energy_amount`）后每个键语义单一，聚合与消费各自独立。符号约定沿用 `roll_cd_pct`：**负值 = 方向减益**（`bullet_dmg_taken_pct: -0.08` 受伤减免、`haggle_pct: -0.15` 降价）。

### J.7.1 白名单（25 新键，键名 = T12 实键）

| 新键 | 类型 | 幅度 | 增益（附录 C / T12 id） | 聚合落地 | 消费点 | 接线卡 |
|---|---|---|---|---|---|---|
| `dmg_vs_statused_pct` | float | 0.20 | 猎杀者 `hunter` | rig meta | CombatSystem 命中结算（目标异常伤害乘区） | 待 T35 接线 |
| `resonance_radius_pct` | float | 0.30 | 共鸣增幅 `resonance_amp` | rig meta | 共鸣结算 AoE 扩散 | 待 T35 接线 |
| `resonance_duration_ticks` | int | 60 | 共鸣增幅 `resonance_amp` | rig meta | 共鸣结算持续 | 待 T35 接线 |
| `vengeance_pct` | float | 0.25 | 复仇者 `avenger` | rig meta | CombatSystem 输出乘区（受击后窗口） | 待 T35 接线 |
| `vengeance_ticks` | int | 180 | 复仇者 `avenger` | rig meta | 同上（3s 窗口时长） | 待 T35 接线 |
| `bullet_dmg_taken_pct` | float | −0.08 | 甲壳 `carapace` | player meta | Player.take_hit_ctx 弹幕来伤乘区（1+pct） | 待 T35 接线 |
| `roll_distance_pct` | float | 0.25 | 冲刺延伸 `dash_extend` | player meta | Player.start_roll 翻滚距离乘区 | 待 T35 接线 |
| `phoenix_flag` | flag | 1 | 不死鸟（唯一）`phoenix` | player meta | Player.take_hit_ctx 致死分支（每局 1 次） | 待 T35 接线 |
| `hurt_iframe_bonus_ticks` | int | 15 | 神经反射 `nerve_reflex` | player meta | Player.take_hit_ctx 无敌帧加算 | 待 T35 接线 |
| `thorns_contact_dmg` | int | 3 | 荆棘护甲 `thorn_armor` | player meta | 接触伤路径反伤 | 待 T35 接线 |
| `wealth_pct` | float | 0.20 | 财富 `wealth` | player meta | Pickup 金币 on_collect 乘区（天赋同义键 T15/T31） | 待 T35 接线 |
| `drink_effect_pct` | float | 0.50 | 大胃王 `glutton` | player meta | DrinkMachine._apply_drink 效果值乘区 | 待 T35 接线 |
| `pickup_radius_pct` | float | 0.60 | 捡拾磁铁 `pickup_magnet` | player meta | Pickup.MAGNET_RANGE_PX 乘区（天赋同义键 T15；掉落面 T20） | 待 T35 接线 |
| `kill_energy_chance` | float | 0.10 | 蓝能汲取 `energy_siphon` | player meta | 击杀结算钩（RoomCombat 敌死亡掷签） | 待 T35 接线 |
| `kill_energy_amount` | int | 2 | 蓝能汲取 `energy_siphon` | player meta | 同上（回蓝量） | 待 T35 接线 |
| `heart_sense_pct` | float | 0.50 | 红心感应 `heart_sense` | player meta | 红心掉落掷签权重乘区 | 待 T35 接线 |
| `passive_energy_interval_ticks` | int | 1800 | 弹药转化 `ammo_convert` | player meta | 房间帧循环周期回蓝（30s） | 待 T35 接线 |
| `passive_energy_amount` | int | 10 | 弹药转化 `ammo_convert` | player meta | 同上（每次回蓝量） | 待 T35 接线 |
| `haggle_pct` | float | −0.15 | 议价 `haggle` | player meta | ShopLogic 商店结算乘区（1+pct，负=降价） | 待 T35 接线 |
| `element_vision` | flag | 1 | 元素视界 `element_vision` | player meta | 敌方弹幕/激光预警展示开关 | **M2-T7**（警示线）+ T35（展示侧） |
| `telegraph_bonus_ticks` | int | 9 | 元素视界 `element_vision` | player meta | 预警 +0.15s（9 ticks）加时 | **M2-T7**（敌激光警示线） |
| `resonance_vision` | flag | 1 | 共鸣视界 `resonance_vision` | player meta | 敌人异常高亮描边渲染钩子 | **M2-T21**（敌人渲染接线） |
| `anti_fire` | flag | 1 | 抗火 `anti_fire` | player meta | 岩浆伤害 −50%；燃烧免疫 | **M2-T10**（岩浆减半）+ T35（免疫系） |
| `anti_ice` | flag | 1 | 抗冰 `anti_ice` | player meta | 冰面打滑免疫；冰缓免疫 | 待 T35 接线（T4 冰面组件已合，读侧补线） |
| `anti_poison` | flag | 1 | 抗毒 `anti_poison` | player meta | 中毒免疫 | 待 T35 接线 |

「聚合落地」列 = T12 `BuffManager` 已写入 `buff_<key>` meta（player/rig，绝对值幂等重写）；「接线卡」列 = 读侧消费的责任卡——**除 T7/T10/T21 三张在途卡各自接线外，其余读侧接线统一归 M2-T35 接线卡**（T12 只落聚合不落消费，全库 `get_meta("buff_*")` 读点当前为零，评审已核实）。既有 15 键（`BUFF_PCT_KEYS` 原 9 + `BUFF_INT_KEYS` 原 6）语义不变。

### J.7.2 T3 原名 → T12 实键映射（历史对照，取键勿用左列）

| T3 原预估键 | T12 实键（权威） |
|---|---|
| `big_eater_pct` | `drink_effect_pct` |
| `energy_siphon_pct` | `kill_energy_chance` + `kill_energy_amount`（拆对） |
| `ammo_convert_energy` | `passive_energy_interval_ticks` + `passive_energy_amount`（拆对） |
| `element_vision`（int 9t） | `element_vision`（flag）+ `telegraph_bonus_ticks`（int 9，拆对） |
| `resonance_vision_flag` | `resonance_vision` |
| `hunter_vs_status_pct` | `dmg_vs_statused_pct` |
| `nerve_reflex_ticks` | `hurt_iframe_bonus_ticks` |
| `bullet_resist_pct` | `bullet_dmg_taken_pct`（名+符号向变更：负值=减伤） |
| `thorns_dmg` | `thorns_contact_dmg` |
| `dash_extend_pct` | `roll_distance_pct` |
| （未预估） | `vengeance_ticks`（复仇者 3s 窗口，T12 增补） |

其余 11 键（wealth_pct / pickup_radius_pct / heart_sense_pct / haggle_pct / vengeance_pct / resonance_radius_pct / resonance_duration_ticks / phoenix_flag / anti_fire / anti_ice / anti_poison）两边逐字一致。

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

## J.9 与规格出处的计数勘误（评审闭环留档）

- **增益条数**：附录 C 全 36 条 − M1 已有 16 条 = **剩余 20 条**新增益（计划卡 T12 行文「+21 → 36」按 16+21=37 计，差 1；另 T12 卡稀有度行文「白14/绿12/蓝10」与附录 C 实际「白15/绿11/蓝10」亦差档）。**已由 T12 落地定稿：36 条（白15/绿11/蓝10）+ 25 新键（J.7.1），两处行文偏差以附录 C 与 T12 实数据为准，勘误闭环。**
- **元素武器清点**：locked 且 `element != none` 为 13 把（紫 11 + 橙 2），J.3 原文「12 把」漏计★雷神之锤（shock，已被裁定③ craft_x 覆盖，分配结果不受影响）——已勘误（评审 Minor ①）。
