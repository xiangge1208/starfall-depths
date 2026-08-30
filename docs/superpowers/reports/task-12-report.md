# Task 12 评审报告：C 数据-3 增益 16→36（分支 m2-t12）

- **被审对象**：`.worktrees/m2-t12`，单 commit `137eed1` `feat(m2-t12): complete 36 buffs`（基线 `1d71bda`）
- **评审员**：独立评审（只读；除本报告外未修改任何文件、未 commit、未 merge）
- **评审日期**：2026-08-30
- **数值唯一出处**：`docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md` 附录 C（36 条全表）
- **变更面**：`data/buffs.json`（+20 行）、`core/meta/buff_manager.gd`、`autoload/game_db.gd`（BUFF_PCT/INT/FLAG_KEYS 扩展 + 消费方注释）、`tests/unit/test_buffs.gd`——与卡面文件清单一致，无越界文件
- **测试实测**：`godot --headless --path . --import` 通过；GdUnit4 全量 **822/822 通过**（51/51 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，3min6s）——与实现者自报一致；`test_buffs` 实测 **41/41**（XML 报告抽验）

---

## 一、结论

# Approved-with-notes

数据面零误差：附录 C 36 条**全量**交叉验证通过（非抽样），稀有度 15/11/10 与附录实际一致，已有 16 条零修正属实，白名单三层（game_db 三键组 / buff_manager EFFECT_DEFAULTS / buffs.json 实际键）**程序化比对完全镜像**，fail-closed 语义完整，41 例测试断言真实且全绿。唯一 Major 非代码错误、不阻塞合并：**25 个新效果键当前在全部生产代码中零消费方**（grep 全库仅 buff_manager 自身与测试读取），而 `game_db.gd` 注释把多数键的消费归属写成"M1 Player.take_hit_ctx / M1 CombatSystem / T4 冰面"等——实测这些位置**均已存在且未读取任何 buff meta**（T4 已合并、take_hit_ctx 用固定 HURT_IFRAME_TICKS 无加算），且 M2 剩余卡（T13~T34）中只有 T10（抗火）显式承诺读取增益 meta，其余键的接线无人承接 → 门禁时死键风险，需编排者指定收口卡。修复建议见第六节。

---

## 二、规格符合度逐项表

| # | 规格项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 36 条计数、id 唯一 | **PASS** | 程序化清点：36 行；`object_pairs_hook` 验证 JSON 无重复键；36 行 `id == key` 全一致 |
| 2 | 稀有度分布 = 附录 C 实际（15/11/10） | **PASS** | 附录 C 独立清点：C.1 攻击 6白/3绿/5蓝 + C.2 防御 5白/5绿/2蓝 + C.3 资源 4白/3绿/3蓝 = **白15/绿11/蓝10**；`buffs.json` 程序化计数完全一致。计划卡括号"白14/绿12/蓝10"为占位口径（且卡标题"+21"自相矛盾：16+21=37≠36），实现者按 Global Constraint 3"数值唯一出处=附录"正确取实际值 20 条/15-11-10，并在测试注释中显式记录口径差——处理正确 |
| 3 | 已有 16 条与附录 C 逐条一致（自报零修正；要求抽验 ≥8） | **PASS** | 评审员**全量 16/16** 核验（非抽样）：四附魔（火/冰/毒 0.2、电 0.15）、弹速 0.15、精准 0.06、强健 +2、护盾调谐 +1、迅捷扳机 0.12、致命 0.5、状态侵蚀 0.25、快速充能 60t（=3.0s→2.0s，60Hz 换算正确）、蓝能上限 +25、翻滚大师 −0.15、散弹扩张（唯一）、暴虐回响 0.2（唯一）——零失配，零修正属实 |
| 4 | 新增 20 条逐条对附录 C（全量核对） | **PASS** | 20/20 全量逐条（名称/稀有度/效果键/数值/desc 语义），详第三节；tick 换算 15t=0.25s、60t=+1s、180t=3s、1800t=30s、9t=0.15s 全部 60Hz 正确 |
| 5 | 新聚合键在 apply_to_player/apply_to_rig 落地并注明消费卡 | **PASS（附 Major-1）** | 实测新增效果键 **25 个**（评审简报预估 21，实测 25 = pct 11 + int 8 + flag 6）：20 个经 `PLAYER_META_KEYS` 落 `player buff_*` meta、5 个经 `RIG_META_KEYS` 落 rig meta；`game_db.gd` 注释逐一给消费归属。卡面只要求"落地+注明"，形式满足；但注明的消费方多数失实（见 Major-1） |
| 6 | 唯一项 3 条（散弹扩张/暴虐回响/不死鸟） | **PASS** | `UNIQUE_IDS = [extra_projectiles, crit_detonate, phoenix]` 恰为附录 C 三个加粗「唯一」项；全 rare（测试断言）；双防线：可抽池移除 + `pick()` 二次拒绝（`push_error` fail-closed）；200 次三选不复现测试覆盖 phoenix 新增 |
| 7 | TDD：36 计数 / 分布 / 新键 apply 断言 | **PASS（附观察）** | `test_buffs_table_loaded_36_rows`、`test_buff_rarity_counts_follow_appendix_c_15_11_10`、3 个附录转录测试 + 5 个 apply/aggregate 新键测试齐备且断言真实。观察：单 squash commit 无法从历史验证 RED 阶段（本流水线通例，不计失败） |
| 8 | 数据卡纪律：分布/一致性测试（GC8） | **PASS** | 计数/分布/白名单/逐条数值/flag 边界（=2 拒收）共 12 新例 + 2 更名，29→41 |

---

## 三、附录 C 交叉验证结果（独立全量清点）

评审员未采信实现者数据，从 spec 附录 C 原文独立录入后与 `data/buffs.json` 全量比对。**36/36 全对**（稀有度记号：白=common、绿=uncommon、蓝=rare）：

### C.1 攻击（14）—— 6白/3绿/5蓝

| 附录 C 名称 | 稀有 | 附录效果 | 实现 id | 效果键值 | 核对 |
|---|---|---|---|---|---|
| 火焰附魔 | 白 | 命中 20% 点燃 | fire_enchant | element_enchant=1, element_proc_chance=0.2 | ✓ |
| 冰霜附魔 | 白 | 命中 20% 冰缓 | ice_enchant | element_enchant=2, 0.2 | ✓ |
| 毒素附魔 | 白 | 命中 20% 中毒 | poison_enchant | element_enchant=3, 0.2 | ✓ |
| 电弧附魔 | 白 | 命中 15% 麻痹 | shock_enchant | element_enchant=4, 0.15 | ✓ |
| 弹速强化 | 白 | 弹速 +15% | bullet_speed | bullet_speed_pct=0.15 | ✓ |
| 精准 | 白 | 暴击率 +6% | precision | crit_pct=0.06 | ✓ |
| 迅捷扳机 | 绿 | 攻速 +12% | swift_trigger | atk_speed_pct=0.12 | ✓ |
| 致命 | 绿 | 暴伤 +50% | deadly | crit_dmg_pct=0.5 | ✓ |
| 状态侵蚀 | 绿 | 异常积累 +25% | status_erode | status_rate_pct=0.25 | ✓ |
| 猎杀者 | 蓝 | 对异常目标伤害 +20% | hunter | dmg_vs_statused_pct=0.2 | ✓ |
| **散弹扩张** | 蓝 | **唯一**：弹丸数 +1 | extra_projectiles | extra_projectiles=1（UNIQUE） | ✓ |
| 共鸣增幅 | 蓝 | 共鸣 AoE 半径 +30%、持续 +1s | resonance_amp | resonance_radius_pct=0.3, resonance_duration_ticks=60 | ✓（60t=1s） |
| **暴虐回响** | 蓝 | **唯一**：暴击 20% 强制共鸣 | crit_detonate | crit_detonate_pct=0.2（UNIQUE） | ✓ |
| 复仇者 | 蓝 | 受击后 3s 伤害 +25% | avenger | vengeance_pct=0.25, vengeance_ticks=180 | ✓（180t=3s） |

### C.2 防御（12）—— 5白/5绿/2蓝

| 附录 C 名称 | 稀有 | 附录效果 | 实现 id | 效果键值 | 核对 |
|---|---|---|---|---|---|
| 强健 | 白 | HP 上限 +2 | vigor | hp_max=2 | ✓ |
| 护盾调谐 | 白 | 盾上限 +1 | shield_tune | shield_max=1 | ✓ |
| 抗火 | 白 | 免疫燃烧；岩浆 −50% | anti_fire | anti_fire=1（flag） | ✓ |
| 抗冰 | 白 | 免疫冰缓与打滑 | anti_ice | anti_ice=1（flag） | ✓ |
| 抗毒 | 白 | 免疫中毒 | anti_poison | anti_poison=1（flag） | ✓ |
| 快速充能 | 绿 | 盾延时 3.0s→2.0s | quick_charge | shield_delay_reduction_ticks=60 | ✓（60t=1.0s 减量） |
| 神经反射 | 绿 | 受击无敌帧 +0.25s | nerve_reflex | hurt_iframe_bonus_ticks=15 | ✓（15t=0.25s） |
| 翻滚大师 | 绿 | 翻滚 CD −15% | roll_master | roll_cd_pct=−0.15 | ✓ |
| 甲壳 | 绿 | 受弹幕伤害 −8% | carapace | bullet_dmg_taken_pct=−0.08 | ✓ |
| 荆棘护甲 | 绿 | 被接触反伤 3 | thorn_armor | thorns_contact_dmg=3 | ✓ |
| 冲刺延伸 | 蓝 | 翻滚距离 +25% | dash_extend | roll_distance_pct=0.25 | ✓ |
| **不死鸟** | 蓝 | **唯一**：致死保留 1 HP（每局 1 次） | phoenix | phoenix_flag=1（UNIQUE） | ✓ |

### C.3 资源/功能（10）—— 4白/3绿/3蓝

| 附录 C 名称 | 稀有 | 附录效果 | 实现 id | 效果键值 | 核对 |
|---|---|---|---|---|---|
| 蓝能上限 | 白 | 蓝上限 +25 | energy_max | energy_max=25 | ✓ |
| 财富 | 白 | 金币获取 +20% | wealth | wealth_pct=0.2 | ✓ |
| 大胃王 | 白 | 饮料效果 +50% | glutton | drink_effect_pct=0.5 | ✓ |
| 捡拾磁铁 | 白 | 拾取范围 +60% | pickup_magnet | pickup_radius_pct=0.6 | ✓ |
| 蓝能汲取 | 绿 | 击杀 10% 概率回 2 蓝 | energy_siphon | kill_energy_chance=0.1, kill_energy_amount=2 | ✓ |
| 红心感应 | 绿 | 红心掉率 +50% | heart_sense | heart_sense_pct=0.5 | ✓ |
| 弹药转化 | 绿 | 每 30s 被动回 10 蓝 | ammo_convert | passive_energy_interval_ticks=1800, passive_energy_amount=10 | ✓（1800t=30s） |
| 议价 | 蓝 | 商店价格 −15% | haggle | haggle_pct=−0.15 | ✓ |
| 元素视界 | 蓝 | 弹幕/激光预警 +0.15s | element_vision | element_vision=1, telegraph_bonus_ticks=9 | ✓（9t=0.15s） |
| 共鸣视界 | 蓝 | 异常敌人高亮描边 | resonance_vision | resonance_vision=1（flag） | ✓ |

**汇总**：白 6+5+4=15、绿 3+5+3=11、蓝 5+2+3=10，总 36；三「唯一」全 rare；名称/稀有度/数值/换算**零失配**。`desc` 文案与附录效果列语义逐条一致（anti_* 三条有测试断言，其余人工核读一致）。

---

## 四、质量维度发现

### Major-1：25 个新效果键零实际消费方，且 `game_db.gd` 消费归属注释失实（移交编排者）

- **证据**：全库 grep（排除 tests/ 与 buff_manager.gd）`buff_anti_*|buff_phoenix|buff_wealth|buff_haggle|buff_dmg_vs|buff_vengeance|buff_resonance_|buff_pickup_radius|buff_heart_sense|buff_kill_energy|buff_passive_energy|buff_drink_effect|buff_roll_distance|buff_thorns|buff_bullet_dmg_taken|buff_hurt_iframe|buff_element_vision|buff_telegraph|buff_resonance_vision` → **0 命中**。即 36 增益中 20 条（全部新卡）在本卡合入后对玩法**实际不生效**（三选一 UI 可选、meta 已写、无人读）。
- 注释失实三例：
  1. `nerve_reflex hurt_iframe_bonus_ticks → M1 Player.take_hit_ctx（HURT_IFRAME_TICKS 加算）`——实测 `core/player/player.gd:126` `take_hit_ctx` 用常量 `HURT_IFRAME_TICKS`，**无任何 meta 加算**；`phoenix_flag → M1 致死分支` 同理不存在（致死直接 `hp = maxi(0, ...)`）；`bullet_dmg_taken_pct → 弹幕来伤乘区` 不存在。
  2. `anti_ice → T4 冰面免疫`——T4 已于本卡之前合并（W1），`core/rooms/ice_floor.gd`/`biome_fx.gd` **无任何 `get_meta` 调用**。把消费归属指向一张已经完结且未接线的卡，等于无人承接。
  3. `dmg_vs_statused_pct → M1 CombatSystem 命中结算`——CombatSystem 无该读取。
- **计划内真实归属核查**：M2 剩余卡中仅 **T10**（A3 岩浆"抗火增益减半，读抗性 meta"）显式承诺读 buff meta；`resonance_vision → T21` 但 T21 卡面只写敌人行走帧动画，无高亮接线；其余键（haggle/wealth/pickup/kill_energy/passive_energy/heart_sense/drink_effect/telegraph/vengeance/thorns/roll_distance 等）**在 T13~T34 无一显式承接**。
- **定性**：卡面字面要求（"落地并注明消费卡"）形式满足，故不判 FAIL；但这与 M1-T27 教训（GC8"每束末卡显式承担集成收口"）正面冲突——若无人指卡，T34 门禁时 36 增益中 20 条是"可抽但不生效"的静默死键，且注释会误导后续实现者以为已接线。**必须移交**。

### Minor-1：flag 键聚合语义与注释矛盾

`game_db.gd:81` 注释称 flag 键"叠加无意义，幅度仅 0 或 1"，但 `buff_manager.gd aggregate()` 对 int 键**求和**——非唯一 buff 可重复 pick，`anti_fire` 取两次得 `buff_anti_fire = 2`。对按 `>= 1` 判定的消费方无害（免疫语义仍成立），且数据行校验（0/1 拒收 >1）只管表内幅度、不管聚合结果，链路自洽；但与注释表述矛盾。建议 flag 聚合取 `maxi` 或注释改注"和值 ≥1 即生效"。

### Minor-2：负值键无消费端 clamp 约定

`haggle_pct −0.15` 与 `bullet_dmg_taken_pct −0.08` 聚合为**符号加法**（方向正确：负=降价/减伤，与 roll_cd_pct 约定一致，测试断言 ×2 → −0.30/−0.16 已覆盖）。但无幅度下限：理论 7 叠议价 → `1+pct = −0.05` 负价格。3 层局实际取 7 张同名蓝卡概率可忽略；**接线消费方时必须 clamp `maxf(0, 1+pct)`**——应写入消费方简报，防止未来卡直接乘出负数。

### Minor-3：新 20 条 desc 断言覆盖缺口

附录转录测试对数值/稀有度全 20 条断言，但 `desc` 全文断言仅 anti_* 3 条（名称断言已全 20 条覆盖）。低风险（desc 纯展示），顺带补齐即可。

### 白名单镜像一致性（核验通过，无发现）

程序化比对：`BUFF_PCT_KEYS(20) ∪ BUFF_INT_KEYS(14) ∪ BUFF_FLAG_KEYS(6)` 与 `EFFECT_DEFAULTS(40)` **键集完全相等且 float/int 类型逐键镜像**，三键组互不重叠；`buffs.json` 实际使用的 39 键 ⊆ 白名单（唯一未用键 `move_speed_pct` 为 M1 遗留，饮料移速走字段路径，无害）。fail-closed 三层完整：表载校验（FLAG 先于 PCT/INT 判型，0/1 越界拒收、未知键拒收、空 effects 拒收）→ `_normalize_row` 整值 float 还原 int（FLAG 判型成立的前提）→ `aggregate()` 白名单外键忽略。测试覆盖 flag=2 拒收与负 pct 收录两侧。

### meta 绝对写与 T15 叠加冲突（核验：未加重，风险受控）

T2 `data/talents.json` 的 24 节点效果键已**命名空间隔离**（`talent_coin_gain_pct`/`talent_pickup_radius_pct`/`talent_hurt_iframe_pct`/`talent_gem_gain_pct`/`talent_dmg_pct`），与 `buff_*` meta 无键名冲突；本卡绝对写是单写者（仅 BuffManager 写 `buff_*`），幂等重测有测试断言（`test_new_meta_keys_idempotent_and_stack`）。因此**不加重** T15 评审披露的绝对写覆盖问题——前提有二，应写入 T15 简报：①T15 只写 `talent_*` meta、禁止写 `buff_*`；②同义键消费方（金币/拾取/无敌帧）须 `buff_* + talent_*` 加法合成。`game_db.gd` 注释已自注"天赋同义键 T15/T31"，意识到位。

### 测试质量（12 新例断言真实性核验通过）

12 新函数 + 2 更名（29→41，实测一致）。逐例核验非恒真：期望值全部源自附录 C 独立推导（稀有度字符串、数值 is_equal_approx、tick 整值、meta 落点含中性默认与幂等/叠加两侧、flag 越界拒收、`available_pool` 36 计数、phoenix 唯一池移除）。`_expect_effect` 带缺失键的 override_failure_message，缺键不会静默通过。夹具 `auto_free(Player.new()) + _test_init()` 沿用既有模式。

---

## 五、测试实测记录

| 项 | 结果 |
|---|---|
| `godot --headless --path . --import` | 通过（编辑器布局加载完成，无报错） |
| GdUnit4 全量 `-a res://tests` | **822/822 通过**，51/51 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，3min6s，exit 0 |
| `tests/unit/test_buffs.gd` | **41/41**（XML 报告 `reports/report_6/results.xml` 抽验 41 cases 0 failed；函数计数 29→41 与自报一致） |
| 与自报一致性 | 822/822 与 41 例均与实现者自报一致 |

---

## 六、修复建议（按优先级）

1. **【移交编排者·合并前指卡】** 为 25 个新键指定消费收口归属：`anti_fire → T10` 已有归属；建议其余键按消费点打包（Player 受击侧：phoenix/iframe/bullet_dmg_taken/thorns/roll_distance → 可并入 T24/T30 所在波次的受击改造或专设微卡；经济侧：haggle/wealth/pickup_radius/kill_energy/passive_energy/heart_sense/drink_effect → 建议随 T28 Balance Bot 前的微卡；输出侧：dmg_vs_statused/vengeance/resonance_* → 命中结算微卡；视界侧：element_vision/telegraph/resonance_vision → T21 顺带）。并把"36 增益实际生效面核对"加入 **T33 门禁预检**核对表（对照 GC8 集成收口条款）。
2. **【下卡顺带·注释修正】** `game_db.gd` 消费注释措辞：已存在但未接线的目标（M1 各点、T4/T7）改为"M1 XX **待接线（需指卡）**"，避免误导后续实现者。
3. **【可选·一行改动】** `aggregate()` 对 6 个 flag 键取 `maxi(agg[k], int(eff[k]))` 代替求和，或修正"0/1"注释为"和值 ≥1 即生效"。
4. **【消费方接线时】** 负 pct 乘区统一 `maxf(0.0, 1.0 + pct)` clamp；T15 落地只写 `talent_*` meta。
5. **【编排者·计划卡勘误】** Task 12 卡标题"+21 → 36"与括号"白14/绿12/蓝10"均与附录 C 实际（+20 → 36、15/11/10）不符，建议在计划文档勘误，防后续卡复制占位口径。

---

## 七、规格符合度总览

**PASS 8 / 8 项**（含 1 项附 Major 移交注记）。数据转录零误差、白名单镜像零失配、测试全绿且断言真实；阻塞级问题无，Major-1（死键收口无主 + 注释失实）按流水线惯例属移交协调面，建议合并后立即指卡闭环。
