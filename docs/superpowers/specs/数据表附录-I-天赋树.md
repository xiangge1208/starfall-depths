# 数据表附录 I：天赋树（M2-T2 定稿）

> GDD 契约出处：设计文档 §14.3「10h 点满天赋树 60%」、§20 成就表「天赋异禀（12 节点，150）/ 满溢之光（全部点亮，500）」。
> 本文为天赋树全表定稿（设计 + 数据卡）：24 节点、三系各 8（红/攻击、蓝/防御、绿/资源）。
> 数据文件 `data/talents.json`；schema 与校验 `autoload/game_db.gd`（TALENT_*）；契约测试 `tests/unit/test_talents_data.gd`。
> 系统落地消费方：M2-T15（core/meta/talent_system.gd + ui/talents.tscn），按本表 effects 键白名单全量接线。

## I.1 节点 Schema（契约）

每节点 8 键全部必填，无 optional；任一键缺失/类型错/语义校验失败 → 整行拒收，跨行校验失败 → 整表拒收且 `GameDB.load_ok = false`（`_ready` 中 `push_error` + `quit(1)`，fail-closed）。

| 键 | 类型 | 约束 |
|---|---|---|
| `id` | String | snake_case，与表键一致（mismatch 拒收） |
| `name` | String | 中文名，非空 |
| `desc` | String | 中文描述，非空 |
| `branch` | String | `red` / `blue` / `green` |
| `tier` | int | 1..8；同分支同层唯一 |
| `cost` | int | 价格梯度 [100, 800]（蓝晶） |
| `requires` | Array[String] | 前置节点 id，可为空；无重复、无自指；引用必须存在同表；**前置 tier 必须严格更低** |
| `effects` | Dictionary | 非空；键在白名单（I.4）；数值幅度受单键上限约束（I.4） |

## I.2 经济数学（GDD §14.3「10h 点满 60%」的定稿口径）

蓝晶获取速率按 M1 门禁校准 **500~700/小时**（保守 500 / 中值 600 / 乐观 700）。

**主契约（成本口径）：全树总蓝晶价 = 10000。**

- 60% × 10000 = **6000 蓝晶 = 10h × 600/h（中值速率）** → 中值速率下 10 小时恰好点满全树价值的 60%。
- 速率区间换算：保守 500/h → 10h = 5000（50%）；乐观 700/h → 10h = 7000（70%）。设计点居中，验收对照留双向容差。

**辅助口径（节点数）：最便宜 15 节点 = 24 × 62.5%（≥ 60%）累计 4100 蓝晶 ≤ 10h × 500/h（保守速率下限也达标）。**

- 成立前提是「最便宜优先」购买集为合法前置闭包——由 schema 校验强制「前置 tier 严格更低」+ 价格随 tier 单调递增保证（tier 1..4 全部 ≤ 350 蓝晶，任何 15 节点组合的贪心集必为合法）。
- 成就节奏换算：`天赋异禀`（点亮 12 节点）= 2850 蓝晶 ≈ 4.8~5.7h；`满溢之光`（全点亮 24 节点）= 10000 蓝晶 ≈ 14.3~20h，构成 10h 之后的长线目标。

**分支价格合计（测试锁定）：红 3400 / 蓝 3300 / 绿 3300，合计 10000。**
红系为毕业优先输出向定价稍高；三系共享价格梯度（tier 1..8 = 100/200/300/350/450|400/550/600|650/800）。

## I.3 全表（24 节点）

### 红 / 攻击系（8 节点，合计 3400）

| tier | id | 名称 | 效果 | 价格 | 前置 |
|---|---|---|---|---|---|
| 1 | `red_sharpen` | 磨刃 | 伤害 +3% | 100 | — |
| 2 | `red_deadeye` | 神射校准 | 暴击率 +4% | 200 | red_sharpen |
| 3 | `red_rapid_hammer` | 高速击锤 | 攻速 +6% | 300 | red_deadeye |
| 4 | `red_gouge` | 创口撕扯 | 暴伤 +25% | 350 | red_rapid_hammer |
| 5 | `red_catalyst` | 侵蚀催化剂 | 异常状态积累 +10% | 450 | red_deadeye（支线分叉） |
| 6 | `red_ballistics` | 弹道优化 | 弹速 +8% | 550 | red_gouge |
| 7 | `red_conduit` | 元素导联 | 附魔触发概率 +5% | 650 | red_catalyst（支线深入） |
| 8 | `red_apex` | 处刑时刻 | 伤害 +5%、暴击率 +2% | 800 | red_ballistics |

### 蓝 / 防御系（8 节点，合计 3300）

| tier | id | 名称 | 效果 | 价格 | 前置 |
|---|---|---|---|---|---|
| 1 | `blue_vitality` | 活体强化 | HP 上限 +2 | 100 | — |
| 2 | `blue_barrier` | 相位屏障 | 盾上限 +1 | 200 | blue_vitality |
| 3 | `blue_tuning_fork` | 屏障谐振 | 盾回复延时 -0.5s（-30 ticks） | 300 | blue_barrier |
| 4 | `blue_fleet_step` | 疾风步 | 移速 +8% | 350 | blue_tuning_fork |
| 5 | `blue_second_wind` | 二段呼吸 | 盾上限 +1 | 400 | blue_barrier（支线分叉） |
| 6 | `blue_adrenaline` | 肾上腺素 | 翻滚冷却 -12% | 550 | blue_fleet_step |
| 7 | `blue_phase_shift` | 相位偏移 | 受击无敌帧时长 +10%（0.8s→0.88s） | 600 | blue_second_wind（支线深入） |
| 8 | `blue_bulwark` | 钢铁堡垒 | HP 上限 +2、盾回复延时 -1.0s（-60 ticks） | 800 | blue_adrenaline |

### 绿 / 资源系（8 节点，合计 3300）

| tier | id | 名称 | 效果 | 价格 | 前置 |
|---|---|---|---|---|---|
| 1 | `green_deep_cell` | 深层电池 | 能量上限 +15 | 100 | — |
| 2 | `green_scavenge` | 拾荒直觉 | 金币获取 +5% | 200 | green_deep_cell |
| 3 | `green_magnet` | 磁化场 | 金币磁吸范围 +10%（56px→61.6px） | 300 | green_scavenge |
| 4 | `green_crystal_vein` | 晶脉勘探 | 蓝晶获取 +5% | 350 | green_magnet |
| 5 | `green_super_cell` | 超容电池 | 能量上限 +25 | 400 | green_deep_cell（支线分叉） |
| 6 | `green_prospector` | 矿脉商人 | 金币获取 +10% | 550 | green_crystal_vein |
| 7 | `green_resonator` | 晶石共鸣 | 蓝晶获取 +10% | 600 | green_super_cell（支线深入） |
| 8 | `green_vortex` | 汇流涡场 | 金币磁吸范围 +20% | 800 | green_prospector |

三系统一拓扑（串并联）：主脊 tier 1→2→3→4→6→8，tier 5 支线自 tier 2 分叉、tier 7 支线接 tier 5——tier 2/4 之后各存在「直进主脊 / 先走支线」的取舍，且所有前置 tier 严格更低。

## I.4 effects 键白名单与消费方

**复用键（与 `BuffManager.EFFECT_DEFAULTS` / `GameDB.BUFF_*_KEYS` 同名同义，消费面为 M1 已接线的 Player / WeaponRig 公开字段）：**

| 键 | 类型 | 幅度上限 | 消费面（既有） |
|---|---|---|---|
| `crit_pct` | float | +0.10 | Player.crit_bonus |
| `crit_dmg_pct` | float | +0.25（暴伤自身刻度：增益即 +50% 一档） | Player.crit_damage_bonus |
| `atk_speed_pct` | float | +0.10 | WeaponRig.rate_mult |
| `bullet_speed_pct` | float | +0.10 | WeaponRig.bullet_speed_mult |
| `status_rate_pct` | float | +0.15 | Player.status_rate_bonus |
| `move_speed_pct` | float | +0.10 | Player.move_speed |
| `roll_cd_pct` | float | 0.15（**负值 = 缩短**，与 buffs.json 约定一致） | Player.effective_roll_cd_ticks |
| `element_proc_chance` | float | +0.10 | WeaponRig.enchant_proc_chance |
| `hp_max` | int | +100 | Player.hp_max |
| `shield_max` | int | +100 | Player.shield_max |
| `energy_max` | int | +100 | Player.energy_max |
| `shield_delay_reduction_ticks` | int | +100（120 ticks = 2.0s） | Player.shield_delay_reduction_ticks |

**新增键（一律 `talent_` 前缀，逐键声明消费方；`NO new key without a stated consumer`）：**

| 键 | 类型 | 幅度上限 | 消费方（M2 计划卡） |
|---|---|---|---|
| `talent_dmg_pct` | float | +0.10 | M2-T15 TalentSystem.apply → WeaponRig 伤害乘区（同 rate_mult 模式） |
| `talent_hurt_iframe_pct` | float | +0.15 | M2-T15 → Player.apply_iframes / HURT_IFRAME_TICKS 乘区 |
| `talent_gem_gain_pct` | float | +0.10 | M2-T31 蓝晶结算 → RunState.next_floor / settle_death_gems → SaveSystem.add_gems 乘区 |
| `talent_coin_gain_pct` | float | +0.10 | M2-T15 → Pickup coin on_collect 金币计数乘区（T31 结算复核） |
| `talent_pickup_radius_pct` | float | +0.30（磁吸基线 56px，+10% 仅 5.6px 无感，QoL 键按自身刻度） | M2-T15 → Pickup.MAGNET_RANGE_PX 乘区 |

测试锁定「白名单零死键」：每个声明的键都至少被一个节点使用；表内出现的所有键都在白名单内。

**消费语义注（m2-t35 接线时补记）：** `roll_cd_pct` 为负值约定——生效式 `1.0 + pct` 乘 `ROLL_CD_TICKS`（-0.15 = 翻滚 CD 缩短 15%，`Player.effective_roll_cd_ticks`）。`element_proc_chance` 双侧语义不同：**buff 侧 override-not-add**——它与 `element_enchant` 成对，聚合取最后一条附魔的概率（`BuffManager.aggregate` 覆盖语义，重复拾取附魔不叠概率）；**天赋侧加法叠加**——`red_conduit` 经 `TalentSystem` own-delta 加算到 `rig.enchant_proc_chance`（可与 buff 附魔概率共存累加）。

## I.5 分支累计效果（满系上限）

| 系 | 累计效果 |
|---|---|
| 红/攻击（3400） | 伤害 +8%、暴击率 +6%、攻速 +6%、暴伤 +25%、异常积累 +10%、弹速 +8%、附魔概率 +5% |
| 蓝/防御（3300） | HP 上限 +4、盾上限 +2、盾回复延时 -1.5s（-90 ticks，3.0s→1.5s）、移速 +8%、翻滚冷却 -12%、受击无敌帧 +10% |
| 绿/资源（3300） | 能量上限 +40、金币获取 +15%、蓝晶获取 +15%、金币磁吸范围 +30% |

数值基调对照 GDD §14：局内增益单条为 +6~12%（暴伤 +50%、异常 +25%），永久天赋单节点 ≤ +10%（暴伤 0.25 / 磁吸 0.30 按自身刻度放宽并注明）；满系红约等于 3~4 条稀有增益的常驻化，与「点满一系 ≈ 14h 中值投入」的代价匹配。

## I.6 校验清单（`autoload/game_db.gd`，全部 fail-closed）

1. `validate_row` + `TALENT_SCHEMA`：8 键齐备、类型正确（JSON float 按 `_normalize_row` 还原 int）。
2. `validate_talent_row`（行级）：branch 白名单；tier 1..8；cost ∈ [100,800]；requires 无自指/重复且全为 String；effects 非空、键白名单、幅度 ≤ `TALENT_KEY_MAX`（`roll_cd_pct` 必须为负）。
3. `validate_talent_refs`（跨行，static）：前置 id 必须存在于同表；前置 tier 必须严格更低。
4. `validate_talent_acyclic`（跨行，static 纯函数）：按 requires 建边 DFS 三色环检测（双节点互指样本单测覆盖）。
5. `_finalize_talents`：3/4 任一失败 → 整表拒收 + `load_ok = false` → `quit(1)`。

契约测试：`tests/unit/test_talents_data.gd`（20 例：计数/分层/schema/坏行/坏引用/环/经济数学/白名单/幅度/端到端拒收）。
