# Task 9 评审报告：C 数据-2 敌人补齐 40（分支 m2-t9）

- **被审对象**：`.worktrees/m2-t9`，单 commit `54673b9` `feat(m2-t9): complete 40-enemy roster`（基线 `b633ed6`）
- **评审员**：独立评审（只读；除本报告外未修改任何文件、未 commit、未 merge）
- **评审日期**：2026-08-30
- **数值唯一出处**：`docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md` 附录 B.1/B.2/B.3
- **测试实测**：`godot --headless --import` 后 GdUnit4 全量 **761/761 通过**（48 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，2min52s）——与实现者自报一致

---

## 一、结论

# Approved-with-notes

数据转录零误差（40/40 三元组全量比对通过，非抽样），契约全行合规，preload 映射完备，测试实测全绿。两个 Major 均非代码错误、不阻塞合并：①本卡唯一新增机制键 `element_rotate`（星髓聚合体元素轮换）无任何测试覆盖；②小 Boss 池"A2 400 / A3 870 楼层侧缩放"在测试注释中被宣称存在但代码中无实现、4 个新小 Boss 未接入任何抽取池——属移交协调面，需编排者在后续卡简报中显式承接。修复建议见第六节。

---

## 二、规格符合度逐项表

| # | 规格项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 总数 40 常规（B.1×4 + B.2 每层 12×3） | **PASS** | 独立清点：`data/enemies.json` 共 47 行 = 40 常规 + 6 小 Boss + 1 Boss（vine_colossus）；四组 id 清单逐一在表，无缺无多 |
| 2 | 小 Boss 池 6（含 4 新增：石盾武僧/亡灵枪手/电磁蛛/腐沼巨蟾） | **PASS** | `shuangdao_lizardman`、`zibao_wangchong`（M1 既有）+ 本卡 4 新行；六行口径一致（hp 180 / body_scale 1.25 / 2 词缀 / drops weapon,hearts2），且有专属 elite 脚本（卡面要求"data 行 + 专属 archetype 脚本"满足） |
| 3 | 附录 B.1/B.2 数值三元组（hp/触/弹）交叉验证（要求分层抽样 ≥15 行） | **PASS** | 评审员**全量 40/40** 脚本比对（非抽样）：三元组零失配；分组行（8×3/18×4/26×3/29×4）单行取单只 HP，符合"成组由 spawn 侧处理"的口径（遗留见 m5） |
| 4 | 4 小 Boss 数值对 B.3 | **PASS（附注）** | B.3 仅给 HP 基准：四行 hp=180（A1 基准）✓。接触/弹伤/弹速/windup 为附录未给值处的推导（contact 4~6、bullet 4~5、speed 110、windup 30），推导自洽且测试注释已注明口径；但"A2 400/A3 870 楼层缩放"无实现（见 M2） |
| 5 | 弹速 ≤150 全行（自报 46/46；rock_crystal_turret=150 恰达上限） | **PASS** | 独立脚本核验 46/46 非 Boss 行零违例；`rock_crystal_turret` bullet_speed=150，契约 `≤` 为闭区间，**恰达上限合规**；其"激光形态"为 150 速弹近似（T7 对齐项，见第五节） |
| 6 | windup ≥24t 全行 | **PASS** | 所有有弹行/有冲锋行 windup ≥30t；windup=0 的行均为无弹无冲锋（穴蝠/自爆/召唤/重装无弹型）；自爆引信 fuse 全 ≥30t；`rock_crystal_turret` windup 36t ≥ 附录"警示线 0.5s"(=30t)，蓄能语义有宽裕 |
| 7 | 新 archetype 补 preload 映射（ARCHETYPES +9） | **PASS** | `enemy_factory.gd`：`splitter/heavy/turret/summoner/barrage`（通用族 5）+ 4 小 Boss，全部 `preload()` 编译期常量，无运行时字符串路径；46 行构造测试全通过（fail-closed 不触发） |
| 8 | 数据卡纪律：分布/一致性测试（GC8） | **PASS** | 5 个数据测试：roster 40 计数、三元组逐字校验、小 Boss 池口径、契约复查（速/预警/引信三合一）、46 行工厂构造 |
| 9 | TDD / 测试 | **PASS** | `test_enemy_ai.gd` 9→26 用例（+17，实测 `test_m2_` 前缀 17 个）；实测 761/761 全绿 |

---

## 三、附录交叉验证结果（独立清点）

评审员未采信实现者的期望表，从 spec 附录 B 原文独立录入后与 `data/enemies.json` 全量脚本比对：

- **常规 40 行**：B.1 通用 4（苦力虫 12/0/0、穴蝠 10/3/0、弩兵 16/3/3、泥浆史莱姆 20/4/0）+ A1×12 + A2×12 + A3×12，三元组 **40/40 全对**，id 集合完全一致（无缺失、无多出）。
- **抽样展示 ≥15 行逐字段核对**（全量已核，此处列分层代表）：
  - A1：硬壳龟 45/5/0、荆棘炮台 30/0/4、老树守卫 40/5/4、萤光虫群 8/0/0 ✓
  - A2：冻土巨蟹 100/7/0、岩晶炮台 66/0/6、晶核召唤师 57/4/0、深窟回响者 48/5/5、晶背龙蜥 88/8/0 ✓
  - A3：黑曜卫 220/10/0、岩浆喷吐炮台 145/0/8、焦土践踏者 194/11/0、烈焰巫妖 106/6/7、星髓聚合体 242/7/7 ✓
- **小 Boss 4 行对 B.3**：hp 全 180（A1 基准口径）✓；机制对应（石盾武僧=正面全格挡+近战破势、亡灵枪手=对枪+复制弹形、电磁蛛=召唤小蛛+电弧断链、腐沼巨蟾=吞弹存伤吐还）均有行为实现与测试。
- **A2/A3 层倍率口径核对**：B.2 各行 HP 已是层换算后的终值（非基准×乘数），实现直接转录终值，正确；弹伤 A2=基准+2、A3=基准+4 的层规律与转录值一致（如弩兵 3 → 晶簇蝙蝠 5 → 灰烬射手 7）。

---

## 四、质量发现

### Blocker

无。

### Major

**M1：`element_rotate`（星髓聚合体确定性元素轮换）零测试覆盖**
- 位置：`core/enemies/archetypes/barrage.gd:81`（`_volley_element()`，ROTATE_ELEMENTS 火→冰→电→毒，`_volley_index` 逐轮推进）。
- 事实：全库 grep `element_rotate` 仅 barrage.gd 两处命中（注释+实现），`tests/unit/test_enemy_ai.gd` 无任何行为断言（starmarrow_blob 仅出现在 id 清单与三元组表）。
- 影响：这是本卡唯一新增的**机制性**行为键（其余新键均为数值参数），轮换序、与 cd 循环的交互、`element` 字段进入 spawn cfg 均无护栏；后续重构（改数组/改 index 推进/改键名）会静默破坏。
- 备注（简报评审点裁断）：**确定性轮换本身可接受为 M2 口径**。附录 B.2 行为文本"随机切换 4 元素弹幕（教学:反制）"若走 RNG 需新盐+新流（GC2 收敛压力），且 T23 死亡回放需要确定性重放；附录 E.6 星陨先知"元素轮回弹幕"本就是固定循环而非随机——敌侧元素循环取确定性符合规格家族口径，且"教学:反制"用固定轮换反而更可教学。唯一瑕疵：轮换顺序 火→冰→**电→毒** 与武器侧彩虹发生器（A.6）/先知（E.6）的 火→冰→**毒→电** 不一致，附录未规定敌侧顺序故非违规，建议顺手统一（Minor 性质，随 M1 补测试时一并处理）。

**M2：小 Boss 池接线面悬空，且测试注释宣称了不存在的机制**
- 位置：`tests/unit/test_enemy_ai.gd`（test_m2_miniboss_pool_six_rows 注释："A2 400 / A3 870 为楼层侧缩放，不落多行"）；`core/rooms/floor_scene.gd:42-43`（小 Boss 映射仍为 M1 硬编码 `shuangdao_lizardman`/`zibao_wangchong`）。
- 事实：全库无任何 HP 楼层缩放实现（无 400/870/×2.2/×4.84 相关代码）；4 个新小 Boss 不在任何抽取池/waves 引用中；`data/rooms/m0_combat.json` 波次仍只含 M1 的 4 种敌人。
- 影响：注释口径超前于现实，会误导后续实现者以为缩放机制已存在。卡面确未要求接线（属 T26/T27/门禁范围），故不算违规，但**附录 B.3 的"A2 400 / A3 870"换算目前没有任何卡明确承接**——需要编排者落卡（建议挂 T26 房间模板或 T27 balance 回归），否则 A2/A3 层小 Boss 将以 180 HP 出场（严重偏低）。

### Minor

- **m1** `ENEMY_OPTIONAL` 未随新键扩展：`autoload/game_db.gd:19-26` 白名单不含本卡 19 个新行为键（split_count/split_child_hp/split_generations/front_block_pct/summon_row/volley_mode/volley_spread_deg/burst_count/burst_interval_ticks/fan_count/fan_spread_deg/slow_pct/slow_ticks/death_burst_count/self_stun_ticks/element_rotate/chain_cd_ticks/guard_break_stun_ticks/wait_ticks 等）。`_load_table` 对未知键透传不拒收（M1 既有口径，zibao 的 delayed_death_ticks 同样不在表内），非本卡引入的倒退；但 t10 注释"其余全部 optional 默认 0"已失真，行为键默认值散落在各 archetype 的 `row.get()`。建议后续数据卡收口时统一登记。
- **m2** `core/enemies/elites/undead_gunner.gd:62` 直接读取 `Projectile._ticks`（下划线私有成员跨对象访问）：能跑但契约脆弱，建议 Projectile 暴露只读 `age_ticks` 属性。
- **m3** 名称口径三处两写：附录 B.3 表作"腐沼**巨蛙**"、任务卡与数据行作"腐沼**巨蟾**"（id `marsh_toad`）。建议 spec 勘误统一（蟾=toad 更贴 id）。
- **m4** 派味特技未实现清单（详见下方"遗留面"）——按卡口径（数据+原型行为抽样）可接受，但需显式移交。
- **m5** 分组敌人"×N 成组"无承接：萤光虫群(8×3)、窃晶鼠群(18×4)、硫磺蛾群(29×4) 附录语义为成组出现，数据行只有单只 HP，spawn 侧（waves 仍为 m0 占位）未实现成组刷出。
- **m6** 亡灵枪手"弹形复制玩家武器"仅复制 damage/bullet_speed 两键（弹数/散射/元素未复制）；速度已正确夹 150 上限（`COPY_SPEED_CAP`）。
- **m7** 电磁蛛召唤 `ice_spider`（A2 特有种）为跨层复用埋雷：若该小 Boss 出现在 A1/A3 层会召出 A2 敌人且无 HP 缩放——与 M2 同源（池化+缩放未接线），一并列移交。
- **m8** 测试内 `RngSvc.stream(1, "m2_barrage")` 等字面量盐：沿用既有测试惯例（"enemy_radius_test"/"combat" 同款），运行时代码零违规（GC2 约束的调用点），灰色可不改。

### 未实现派味特技遗留清单（附录行为文本 → 现实现）

| 敌人 | 附录行为 | 现实现 | 承接 |
|---|---|---|---|
| 磁石傀儡 | 把玩家向自身拉拽（2 格） | heavy 逼近+正面减伤 0.6 | **无承接卡**（建议 T7 或 T26 简报追加） |
| 冻土巨蟹 | 横向钳击（预警扇区） | heavy 逼近+正面减伤 | 无承接卡 |
| 硬壳龟 | 龟缩时免疫 | 正面减伤 0.8 | 无承接卡 |
| 窃晶鼠群 | 偷 5 金币后逃跑 | suicide 自爆 | 无承接卡 |
| 苔藓史莱姆 | 遇水洼提速 | splitter 逼近 | 无承接卡 |
| 荆棘炮台 | 抛物 3 连发 | 直线 3 连发 | 无承接卡 |
| 种子投手 | 落地 30% 生苦力虫 | 扇形弹 | 无承接卡 |
| 深窟回响者 | 模仿玩家上次武器弹形 | 通用扇弹 | 无承接卡 |
| 幽光水母 | 电弧链射击 | 单发瞄射 | 可挂 T28 元素弹分化 |
| 冰蛛 | 结网 1.5s 禁锢 | splitter 分裂 | **T7 简报需明确 defer 去向** |
| 熔岩犬 | 两段扑咬+燃烧 | 单段冲锋 | 可挂 T10（A3 燃烧语义） |
| 火雨祭司 | 火雨区（预警红圈） | 环形弹 | 可挂 T10 火雨组件复用 |
| 焦土践踏者 | 跺地环形火浪 | 冲锋 | 可挂 T10 |
| 硫磺蛾群 | 爆炸留燃烧地面 | AoE 7 | 可挂 T10 |
| 棱镜游侠 | 借晶柱折射射击 | 单发瞄射 | **T7 明确承接** |
| 岩晶炮台 | 蓄能直线激光 | 150 速弹近似 | **T7 明确承接** |
| 40 行 spawn 接线 | — | waves 仍为 m0 占位（仅 4 种 M1 敌人） | **T26/T27 承接** |

**评估**：M2 流水线里 T7（A2 形态）、T10（A3 火语义）、T26/T27（刷怪/平衡）、T28（元素弹）能承接大部分；但"偷金币/水洼提速/模仿武器/抛物线/龟缩免疫/钳击/拉拽/落地生怪"约 8 项无归属。数量在数据卡口径内可容忍（本卡交付的是数据+原型行为），建议编排者将本清单并入 T33 门禁"移交项闭环"核对表，防止 M2 收口时静默丢失。

### 其他质量维度

- **热路径**：无字符串路径拼接；`row.get()` 读行为键与 M1 既有原型（charger/shooter）同款；弹 cfg 新建 Dictionary 为 `fire_bullet` 既有模式（池化由 `combat.spawn_projectile` 持有）。preload 映射完备（见规格表 #7）。
- **RNG 纪律**：本卡运行时代码**零新 RNG 流**（确定性轮换+固定相位状态机），是 GC2 的模范执行；星髓聚合体详见 M1 裁断。
- **测试断言真实性**：帧级精确断言扎实——首发拍 55（25+30）、连发间隔 6/8t、自晕窗恰 60t、吞弹相边界 85/235、补召窗 264/324、环弹 45° 均布角度逐对差分、失败指纹带 id+期望+实际可定位。`undead_gunner` 用真 CombatSystem 池（非替身）验证对枪触发链。弱点：`test_m2_orbiter_wing_lizard_fires_with_telegraph` 断言偏松（≥1 发、≥55 拍，无周期断言）；element_rotate 见 M1。
- **fail-fast 完整性**：GameDB schema fail-closed 在启动时 quit(1)；46 行工厂构造测试兜住未知 archetype；0 orphans。
- **基类接缝**：`_windup_ticks`/`stun_until`/`_on_engage_start`/`spawn_callback`/`fire_bullet` 均为 EnemyBase 既有契约；splitter 与 m1-t12 分裂词缀路径（`split_on_death`）互不干扰（名字不同的两个方法，行未设 `split_on_death`）；magma_slime 减半链 145→72→36 与注释声明的两代结构一致；heavy 的 `round` 而非 `floor`（0.8 减伤浮点修正）有注释且被测试锁死（10×0.2=2 精确断言）。

---

## 五、T7 对齐清单（供编排者写 T7 简报用）

T7 卡原文计划"Modify `data/enemies.json`（+rock_crystal_turret/prism_ranger/ice_spider/crystal_rat/magnet_golem 等 A2 行，按附录 B.2 数值）"——**这 5 行已全部由本卡交付**（数值即附录 B.2）。T7 简报必须改写为"数据行已存在，勿重复插行"，工作收窄为形态接线：

1. **`rock_crystal_turret`（岩晶炮台，data/enemies.json:24）**：现为 turret 原型 windup 36t + 单发 150 px/s 直线弹近似"蓄能直线激光（警示线 0.5s）"。T7 的 `core/enemies/enemy_laser.gd` 落地后需决定：改接激光束形态，或保留 150 速弹但接入晶柱折射。警示线 0.5s=30t 已被 windup 36t 覆盖，无需改数。
2. **`prism_ranger`（棱镜游侠）**：现为 shooter 单发瞄射，"借晶柱折射射击（拐角弹）"未实现。T7 折射组件（prop_crystal_pillar 45° 反射、最多 1 次）落地后需让该敌的弹参与折射。
3. **数据行零改动**：T7 不得再向 `data/enemies.json` 插入上述 5 行（id 冲突/覆盖风险）；波次表 T7 与 T9 的独占文件均含 `data/enemies.json`，若 T7 并行开发中，rebase 时以本卡 40+6+1 行全集为基线。
4. **明确 defer 去向**：冰蛛结网（1.5s 禁锢）、磁石傀儡拉拽若 T7 不做，需在简报写明 defer 目标卡（当前无归属，见 m4 清单）。
5. T7 的 A2 行为抽样测试若引用这些行，现成断言可复用 `tests/unit/test_enemy_ai.gd` 的 M2 节夹具（M2SpyCombat/_m2_record_spawn）。

---

## 六、修复建议（Approved-with-notes，非阻塞）

1. **（建议本卡内热修或并入 T7 前置）** 补一条 `element_rotate` 行为测试：构造 starmarrow_blob，注入两轮 volley，断言元素序列 FIRE→ICE（再两轮 SHOCK→POISON）且 `element` 进入 spawn cfg；顺手把 ROTATE_ELEMENTS 顺序统一为 火→冰→毒→电（与 A.6/E.6 对齐）。
2. **（编排者动作）** 将"小 Boss 池抽取 + A2 400/A3 870 分层 HP 缩放 + 4 新小 Boss 入池"显式写入 T26 或 T27 简报；同时把 m4 遗留清单并入 T33 门禁移交核对表。
3. **（低成本清理，可并入后续数据卡）** test_m2_miniboss_pool_six_rows 注释改为"分层缩放由后续卡承接（当前无实现）"；ENEMY_OPTIONAL 登记 19 个新键；undead_gunner 改读 Projectile 公开属性；spec 勘误"腐沼巨蛙/巨蟾"。

---

## 七、验证记录

```
cd D:\workspace\thomas\.worktrees\m2-t9
godot --headless --path . --import            # DONE 无报错
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests --ignoreHeadlessMode
# Overall Summary: 761 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans
# Executed test suites: (48/48)   Executed test cases: (761/761)   Exit code: 0
```

独立数值比对脚本（评审员从附录 B 独立录入期望值，全量非抽样）：40/40 三元组零失配；46/46 非 Boss 行契约（弹速≤150、有弹/有冲锋行 windup≥24、fuse≥24）零违例；`rock_crystal_turret` 弹速恰为 150（闭区间合规）。
