# M2 Task 11 评审报告：法师奥术新星 + 守护者生命潮汐

- **被审对象**：worktree `.worktrees/m2-t11`（分支 m2-t11，单 commit `204e942`，基于 `1d71bda`）
- **评审员**：独立评审（只读；除本报告外未改任何文件、未 commit、未 merge）
- **日期**：2026-08-30
- **测试实测**：`godot --headless --path . --import` 通过；GdUnit4 全量 **830/830 绿（52 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，exit 0，3min08s）**，新套件 `test_skills_mage_guardian` 20 例全过（XML 复核 tests=20 failures=0）。与实现者自报一致。

## 结论

**APPROVE（通过，可合并）**。无 Blocker、无 Major。规格逐项对 GDD §6 全 PASS（数值出处、边界、升级版、冻结语义复用均正确且有测试钉死）；质量维度上 get_weapon 回落影响面经核实可控、双减伤窗互斥成立、热路径零分配。5 项 Minor 均不阻塞，其中 2 项需流转台账（被动接线无承接卡、星辉杖弱化版留 T28）。

## 规格核对（逐项）

数值权威 = GDD §6（编排者裁定：计划卡为摘要；生命潮汐升级=-20% 受伤 + 施放即回 2HP 按 GDD 落地，合法）。

### 奥术新星（core/player/skills/arcane_nova.gd）

| 项 | GDD §6 权威值 | 实现 | 判定 |
|---|---|---|---|
| 半径 | 120px | `RADIUS_PX=120.0`，边界含（恰 120px 命中，121.5px 排除，测试双侧钉死） | PASS |
| 伤害 | 24 固定 | `DAMAGE=24`，`is_crit=false`（§7.1 伤害固定、技能不掷暴击） | PASS |
| 冻结 | 1.2s | `FREEZE_TICKS=72`（60Hz），窗 `[now, now+72)` | PASS |
| CD | 10s | 600t（heroes 行 `skill_cd:600` 经 HeroApplier→`cooldown_ticks` 覆写，端到端测试断言） | PASS |
| 耗蓝 | 20 | `energy_cost=20`（heroes 行 `skill_energy:20`） | PASS |
| 升级半径 | +40% | `RADIUS_UPGRADED_PX=168`（120×1.4） | PASS |
| 升级冻结 | 2s | `FREEZE_TICKS_UPGRADED=120` | PASS |
| 精英减半 | 「冻结 1.2s（精英减半）」 | 72/2=36、120/2=60（整除无截断）；判定=`elite_affixes` 非空，同 `EnemyBase._test_init` 口径；**伤害不减免**（GDD 只减半冻结） | PASS |
| Boss 免冻 | §6 未写；§7.3 冰叠满冻结「Boss 免疫冻结，仅冰缓」 | `apply_freeze` 内 `is_boss` 早退（豁免统一持有在 StatusComponent，与 `is_frozen` 同一判定）；伤害照常 | PASS（推导合理：冻结豁免是全局机制非 nova 特例；与 §7.3 一致，测试钉死） |

### 生命潮汐（core/player/skills/life_tide.gd）

| 项 | GDD §6 权威值 | 实现 | 判定 |
|---|---|---|---|
| CD | 14s | 840t（heroes 行 840，端到端断言） | PASS |
| 耗蓝 | 30 | `energy_cost=30` | PASS |
| 施放即回 | 立即回 2 HP | `INSTANT_HEAL=2` → `player.heal(2)`（clamp hp_max） | PASS（编排者已裁定） |
| 法阵 | 3s（0.5 HP/s）名义 1.5HP | `DURATION=180t`、节拍 60t×0.5 累加器满 1 落地：**3s 实落 1HP**（第 2 秒拍生效），余 0.5 消散、不跨施放携带 | PASS（带偏差备注，见 Minor①；代码与测试均显式披露该口径） |
| 升级 | 法阵内额外 -20% 受伤 | `TIDE_DR=0.8`（floor、min1），`tide_guard_until` 窗每拍续期 +2t 前瞻；离阵 ≤2t 自然过期 | PASS（编排者已裁定） |
| 法阵半径 | GDD 未给 | 60px 议定值（同坚守 60px 先例，注释标明 T28 校准点） | PASS（议定已披露） |

### heroes.json 两行 vs GDD §6 面板表

| 行 | hp/盾/蓝/速 | 暴击 | 初始武器 | 判定 |
|---|---|---|---|---|
| mage 法师·烬 | 5/5/160/80 全对 | 0.05（§7.1 基础 5%，无法师暴击被动） | 学徒法杖 `xuetufazhang`（common、伤 3、0 耗蓝、未锁定，在掉落池内） | PASS |
| guardian 守护者·萄 | 7/6/130/80 全对 | 0.05 | 星辉杖 `xinghuizhang`（epic、伤 4/rate 3.0/耗蓝 4、`locked:true`、不入掉落池） | PASS（弱化版偏差见 Minor②） |

两行均为整齐 16 键（schema 全必填），`skill_cd/skill_energy` 与技能默认一致，`skill_name/skill_desc` 中文文案与 GDD 数值一致；`passive_id` echo/blessing 落位（消费方见 Minor⑤）。`test_heroes.gd` 计数 3→5、选角卡 3→5 同步更新。

### 冻结复用 status_component 语义

- `apply_freeze(ticks, now)`（status_component.gd:185-188）：取 `maxi` 不缩短既有窗 ✓；`is_boss` 或 `ticks<=0` 早退 ✓；与 `is_frozen` 共用 `_freeze_until`，Boss 豁免口径单一出处 ✓。
- **调用时序「须在 take_hit 后」**：全库 grep 确认唯一生产调用点在 `arcane_nova._activate` 内 `take_hit` 之后（arcane_nova.gd:52-62），且命中致死后跳过（不冻尸体）。理由成立：若命中使 ICE 跨阈值，`_trigger` 对 `_freeze_until` 是直接赋值（1.0s），先冻后打会被覆盖；后打先冻 + 取 max 不受影响。3 个专门单测钉死（窗/Boss/max 不缩短）。
- 边缘交互见 Minor③（共鸣清 ICE 会连带清冻结窗——既有语义延续，非本卡回归）。

### TDD 核对

全部要求项均有测试：半径边界（120/121.5；升级 150/170）✓、冻结时长（+71/+72；精英 +35/+36；升级 +119/+120）✓、蓝耗门（19/20、29/30）✓、CD 边界（+599/+600、+839/+840）✓、升级版双参数 ✓、法阵周期（节拍 60/120/180 末拍含、法阵后停、阵外空转、instant heal、-20% 阵内/阵外）✓、ICE 层积累推进（再 1 层触发 0.7 冰缓）✓、HeroApplier 端到端真装配 2 例（含史诗初始武器 equip 通路）✓。

## 质量维度

### 1. game_db.gd get_weapon 回落 weapons_all（跨卡语义变更）——影响可控

- **必要性**：回落前 locked 行返回 `{}`，守护者的史诗初始武器会在 `WeaponRig.equip`（weapon_rig.gd:33 经 get_weapon）静默失败、选角卡显示裸 id（hero_select.gd:122）。回落是「初始武器=授予而非掉落」语义的必要通路。
- **掉落/商店不可达**：`FloorScene._roll_weapon`（floor_scene.gd:1066）与 `ShopLogic._weapons`（shop_logic.gd:126）直接枚举 `GameDB.weapons`（locked 在 GameDB 装载期 erase，game_db.gd:146-149），**不经过 get_weapon** → 回落无法让 locked 武器进入掉落/商店滚动。商店购买、拾取、奖励的 id 全部源自池滚动，回落对这些路径不可达。
- **T20 接口**：图鉴解锁引擎 T20 按 unlocked 过滤进池；get_weapon 已能解析 locked 行反而减小 T20 改动面（解锁前后无需切换查询口径）。
- **钉死充分性**：新增 `test_locked_epic_start_weapon_resolves_but_stays_out_of_drop_pool` 四断言（weapons_all 有 / locked true / weapons 无 / get_weapon 可解析）+ T6 既有 `test_weapons_pool.gd`（掉落池排除 locked、115 计数、稀有度分布）。足够。
- 残余风险见 Minor④。

### 2. 守护者初始武器强度——数据面如实

`xinghuizhang` 行如实为史诗原版（damage 4 / rate 3.0 = 12 DPS / 耗蓝 4 / locked:true / 不入掉落池），无弱化版独立行——与 GDD「星辉杖(弱化版)」字面不符，强度风险已记录 T28（其余四名初始武器均为白品 0 耗蓝，守护者开局即史诗，量级差异显著）。偏差在注释（arcane_nova/life_tide 同款披露风格）与测试注释中如实声明。属已裁定 T28 校准项，不阻塞本卡。见 Minor②。

### 3. TIDE_DR × RAMPAGE_DR 叠乘——互斥成立，不可达

`rampage_active_until` 全库唯一写入方 = vanguard_rampage.gd；`tide_guard_until` 唯一写入方 = life_tide.gd（grep 确认）。Skill 节点单挂（player.tscn 恒一个，HeroApplier set_script 换装），一名角色一局只持有一个技能脚本 → 两窗不可能同时在同一 player 上活跃，0.7×0.8=0.56 叠乘不可达。实现者自报属实。player.gd 接缝共 4 行（const/var/两行结算），顺序 floor+min1 与狂潮先例一致。

### 4. 热路径

- `life_tide.tick`：非节拍帧仅两次比较早退（法阵结束后 `_until<0 or frame>_until` 直接 return）；升级路径每拍一次距离比较；治疗节拍纯 float 运算。**零分配** ✓。`_physics_process` 自驱 + 测试注入帧双轨；即使被双重驱动，节拍推进幂等（`frame < _next_heal_at` 二次早退），防御性好。
- `arcane_nova._activate`：每次施放（600t 一次）扫一次 "enemies" 组 + 每敌一个 ctx 字典。事件路径分配，同坚守被动（player.gd:192 每敌 ctx 字典）与敌方 `fire_bullet`（enemy_base.gd:112 每发弹字典）既有习语，非每帧热路径，符合约束 5 的既有执行口径。
- 寻敌为施放时一次组扫描（同坚守/炮台），非每 tick。✓

### 5. 测试质量（20 例）

- 断言真实：无恒真断言，边界全部双侧（+71/+72、+599/+600、120/121.5px、150/170px、839/840）。
- 帧注入模式与 test_skills/test_summons 一致（cast/tick(frame) 直驱，不经 _physics_process）。
- 夹具清理：root/player/enemy/skill 全 auto_free 级联，实测 0 orphans；测试同步执行无物理帧 interleaving 风险。
- 端到端 2 例走 player.tscn + HeroApplier 真装配（set_script 后数据覆写、史诗武器 equip、满蓝施放），覆盖高于纯手工 new。
- 小瑕疵：`test_tide_upgraded` 依赖 Player 默认 hp=8 隐式值（未显式设 hp_max，断言 `8-4` 可读性略降）——不构成问题。

## 发现清单

### Blocker
无。

### Major
无。

### Minor

1. **法阵 3s 实落 1HP vs GDD 名义 1.5HP**（life_tide.gd:66-72, 44）：整 HP 口径 + 余数随法阵消散（不跨施放携带），单次施放治疗 1HP（0.33HP/s 均值）低于 GDD 0.5HP/s 设计值。实现是 §7.1 floor 习语的合理延伸且代码/测试双披露，判 PASS；但若求长期均值收敛 GDD，一行改动即可：`_activate` 移除 `_heal_acc = 0.0`（余数跨施放携带 → 两次施放共 3HP = 1.5/次）。建议 T28 校准时定夺。
2. **GDD「星辉杖(弱化版)」未落地弱化行**（data/heroes.json guardian 行 + weapons.json xinghuizhang）：直接授予史诗原版。已记录 T28；数据面如实、锁定口径正确。备选方案：独立弱化行或 HeroApplier 授予时运行时覆盖。
3. **nova 冻结可被共鸣提前清除**（status_component.gd:145-150 与 185-188 交互）：`_clear_active_element(ICE)` 重置 `_freeze_until=-1`，若 nova 冻结生效后目标 ICE 触发并与另一活跃状态共鸣，冻结窗被提前清掉。这是既有「冻结绑定 ICE 状态生命周期」语义的延续（阈值冻结同样被清），非本卡引入的回归；GDD 无明文。建议 T12（增益+21）元素相关工作时顺带复核是否需要解耦。
4. **get_weapon 语义从「掉落池查询」扩为「全名录查询」**（game_db.gd:161-165）：若未来数据表（增益/房间/熔铸）引用武器 id 并以 get_weapon 空值做存在性过滤，locked 行将被放行。当前无此类调用方；约定「池口径在池构造处收口（weapons dict）」即可，T20 落地时保持。
5. **被动 echo/blessing 无消费代码且无承接卡**（heroes.json passive_id + hero_select.gd 文案仅有）：实现者披露「后续卡接线」，但查波次表 T13 是数据卡，**无任何卡显式承接被动接线**（连同 T8 的 spare_parts）。非 T11 的 FAIL（卡范围=两个主动技），属流水线台账缺口，上报编排者。

## 修复建议（非阻塞）

1. Minor① 若裁定贴近 GDD：删除 `life_tide.gd:44` 的 `_heal_acc = 0.0`，同步更新测试第 7 行口径注释（两次施放收敛 1.5HP/次）。
2. Minor② 纳入 T28 Balance Bot 校准清单：守护者（史诗开局武器+潮汐）胜率带，弱化版星辉杖（如伤 3/rate 2.5/0 耗蓝）为备选项。
3. Minor⑤ 台账补记：echo（法杖/激光 +15%）/blessing（新层回满盾+5% 叠层）/spare_parts（每层补炮台）三被动的接线归属（建议 T13 扩围或 T20-T25 间微卡）。

## 验证记录

| 步骤 | 命令 | 结果 |
|---|---|---|
| 导入 | `godot --headless --path . --import` | 通过（编辑器加载完成，无报错） |
| 全量测试 | `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode` | **830/830 PASS**（52/52 套件；0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans；exit 0；3min08s） |
| 新套件复核 | reports XML | `test_skills_mage_guardian` tests=20 failures=0 errors=0 |
| 卫生 | `git status` | 评审前 clean；评审 import 产生的 icon.svg.import 噪音已由评审员还原，worktree 交还时 clean |
