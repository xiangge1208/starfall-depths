# Task 12 报告：C 数据-3 增益 16 → 36（m2-t12）

- 分支：`m2-t12`（基于 main 1d71bda）
- 提交：`137eed1 feat(m2-t12): complete 36 buffs`；评审修复 `fix(m2-t12): truthful consumer annotations + flag max aggregation`（追加，未 amend）
- 文件：`data/buffs.json`、`core/meta/buff_manager.gd`、`tests/unit/test_buffs.gd`、`autoload/game_db.gd`（白名单常量必要扩展，见偏差③）
- 数值唯一出处：数据表附录 C（36 条全表）；计划卡括号值为占位，以附录实测为准

## ① 完成清单（新增 20 + 既有 16 核对）

**M1 既有 16 条逐条核对附录 C：全部一致（名称/稀有度/desc/数值/键），零修正需要。**

**新增 20 条**（附录 C 剩余全量）：

| id | 名称 | 稀有 | effects |
|---|---|---|---|
| hunter | 猎杀者 | 蓝 | dmg_vs_statused_pct 0.20 |
| resonance_amp | 共鸣增幅 | 蓝 | resonance_radius_pct 0.30 + resonance_duration_ticks 60 |
| avenger | 复仇者 | 蓝 | vengeance_pct 0.25 + vengeance_ticks 180 |
| anti_fire / anti_ice / anti_poison | 抗火/抗冰/抗毒 | 白 | 同名 flag 1 |
| nerve_reflex | 神经反射 | 绿 | hurt_iframe_bonus_ticks 15 |
| carapace | 甲壳 | 绿 | bullet_dmg_taken_pct −0.08 |
| thorn_armor | 荆棘护甲 | 绿 | thorns_contact_dmg 3 |
| dash_extend | 冲刺延伸 | 蓝 | roll_distance_pct 0.25 |
| phoenix | 不死鸟 | 蓝·唯一 | phoenix_flag 1 |
| wealth | 财富 | 白 | wealth_pct 0.20 |
| glutton | 大胃王 | 白 | drink_effect_pct 0.50 |
| pickup_magnet | 捡拾磁铁 | 白 | pickup_radius_pct 0.60 |
| energy_siphon | 蓝能汲取 | 绿 | kill_energy_chance 0.10 + kill_energy_amount 2 |
| heart_sense | 红心感应 | 绿 | heart_sense_pct 0.50 |
| ammo_convert | 弹药转化 | 绿 | passive_energy_interval_ticks 1800 + passive_energy_amount 10 |
| haggle | 议价 | 蓝 | haggle_pct −0.15（负=降价，同 roll_cd_pct 约定） |
| element_vision | 元素视界 | 蓝 | element_vision 1 + telegraph_bonus_ticks 9 |
| resonance_vision | 共鸣视界 | 蓝 | resonance_vision 1 |

唯一项 3 条：散弹扩张/暴虐回响/不死鸟（UNIQUE_IDS + pick 二道防线 + 可抽池移除）。

## ② 附录 C 清点分布 vs 数据文件分布

| 来源 | 白 | 绿 | 蓝 | 合计 |
|---|---|---|---|---|
| 附录 C 实测清点（C.1 6/3/5 + C.2 5/5/2 + C.3 4/3/3） | 15 | 11 | 10 | 36 |
| data/buffs.json（脚本实数复核） | 15 | 11 | 10 | 36 |
| 计划卡括号口径（占位，未采用） | 14 | 12 | 10 | 36 |

## ③ 新聚合键 → 消费状态（评审修复① 后的 truthful 口径）

**落地方式**：无既有公开字段的新键经 `set_meta("buff_<key>")` 绝对值幂等落地（M1 drink_* meta 先例）。输出侧 5 键落 rig meta，其余 20 键落 player meta。

**消费状态（逐键 grep 核实）**：截至修复 commit，25 个新键在代码库中**零运行时消费**（无任何 `get_meta("buff_*")` 调用；T4 ice_floor/biome_fx 不读 meta，T10 岩浆未交付，Player.take_hit_ctx 用固定 HURT_IFRAME_TICKS 常量且致死分支无 phoenix 处理，Pickup/ShopLogic 均常量结算）。全部标注为：

> 消费方待接线 → **T35**（编排者已立卡：meta 生效接线，含 player/pickup/shop_logic/drink_machine/weapon_rig/fx 的 get_meta 读取）

目标消费模块仍逐键保留在 `game_db.gd` BUFF_*_KEYS 注释（如 phoenix→Player 致死结算、haggle→ShopLogic、pickup_radius→Pickup.MAGNET_RANGE_PX），仅状态从「已接」改为「待接」。

| 落点 | 键 | 目标消费模块（T35 接线） |
|---|---|---|
| rig meta | dmg_vs_statused_pct / resonance_radius_pct / resonance_duration_ticks / vengeance_pct / vengeance_ticks | CombatSystem 命中/共鸣结算 |
| player meta | anti_fire / anti_ice / anti_poison | StatusComponent 免疫 + 冰面/岩浆抗性 |
| player meta | hurt_iframe_bonus_ticks / bullet_dmg_taken_pct / thorns_contact_dmg / roll_distance_pct / phoenix_flag | Player 受击/翻滚/致死结算 |
| player meta | wealth_pct / pickup_radius_pct / heart_sense_pct | Pickup 结算与掉落掷签 |
| player meta | drink_effect_pct | DrinkMachine |
| player meta | kill_energy_chance / kill_energy_amount / passive_energy_interval_ticks / passive_energy_amount | 击杀钩与周期回蓝 |
| player meta | haggle_pct | ShopLogic（1+pct） |
| player meta | element_vision / telegraph_bonus_ticks / resonance_vision | 敌方预警展示/异常高亮渲染 |

## ④ 测试计数

- `test_buffs.gd`：29 → 41（首版）→ **42**（评审追加 flag max 断言）例
- 全量：main 基线 810/810 → T12 首版 **822/822** → 评审修复后 **823/823**（51/51 套件，0 失败 0 孤儿）
- 新增断言面：36 计数、15/11/10 分布、附录 C 20 条逐条转录、3 唯一项、flag 行值 0/1 校验、flag 聚合 max（anti_fire×2 → 1）、player/rig 新键 apply、meta 中性/幂等/叠加

## ⑤ 与规格偏差

1. 计划卡标题"+21"实为 **+20**（16+21=37≠36；附录 C 全表 36−16=20）。
2. 稀有度占位 14/12/10 → 附录实测 **15/11/10**。
3. 所有权外必要改动：`autoload/game_db.gd` BUFF_PCT_KEYS/BUFF_INT_KEYS 扩展 + 新增 BUFF_FLAG_KEYS（fail-closed 白名单与 EFFECT_DEFAULTS 镜像，不扩展则新行整表拒收）。
4. 新键落地方式：player.gd/weapon_rig.gd 不在本卡所有权内，经 buff_* meta 落地（T10 卡明言"读抗性 meta"，与 T35 接线卡吻合）。

## ⑥ 评审修复（Approved-with-notes → 本轮闭环）

1. **注释改真（Major）**：逐键 grep 核实 25 键全部无真实消费方；game_db.gd/buff_manager.gd/test_buffs.gd 中所有「M1/T4/T7/T10/T21 已接」注记改为「消费方待接线 → T35」+ 目标消费模块，并注明核实证据（零 get_meta("buff_*) 调用等）。
2. **flag 聚合语义**：`aggregate()` 对 FLAG_KEYS（anti_fire/ice/poison、phoenix_flag、element_vision、resonance_vision）由求和改为 **max**，结果恒 0/1；补测试 `test_flag_keys_aggregate_max_not_sum`（抗火×2/元素视界×2 → 聚合与落地 meta 均为 1）。与 BUFF_FLAG_KEYS 行值 0/1 校验、"0/1 语义"注释一致。
3. **haggle_pct clamp 约定**：game_db.gd 键注释补消费方约定——T35 落地时 clamp 到 **[-0.5, 0]** 或更窄（多张议价叠加的极端值不得产生 ≤0 价格或正收益）。

## ⑦ 遗留风险（移交编排者）

1. 25 键消费方全部待 T35 接线；T35 需按 game_db.gd 注释的目标消费模块逐键 get_meta，防死键。
2. resonance_vision 的高亮渲染在 M2 无其他专属卡，T35 若不接则为死键。
3. T3 并行白名单文档未进 main，无法交叉核对键名；若与本文键名不一致，以附录 C 对齐版（本实现）为准。
4. phoenix"每局 1 次"的次数消耗、复仇者 3s 窗口判定、 vengeance_ticks 跨多张叠加的均值语义由 T35 消费方解释（聚合层纯求和/取 max）。
5. 权重白55/绿30/蓝15 未动；新分布下 roll_three 白占比 band（0.50–0.60）实测通过。
