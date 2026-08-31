# M2 卡评审报告：prophet（星陨先知 + 隐藏门）

- 被评审提交：`c4ebc1a feat(m2-prophet): starfall prophet + hidden gate`（分支 `m2-prophet`，基于 main `c84bf88` 线性历史）
- 评审方式：只读代码审查 + 独立复跑全量测试
- 测试复跑：`python -c "import PIL"` 通过（PIL 12.3.0）；`godot --headless --path . --import` 无报错；gdUnit 全量 **1116/1116（67 套件，4m17s，0 失败 0 错误 0 flaky）**；隔离复跑 `test_boss_m2_prophet.gd` 单套 **19/19 通过**。实现者自述的 test_telemetry 偶发未在本次评审复现。
- **结论：NEEDS FIXES**（Critical ×1，Important ×2，Minor ×7）

---

## 一、概述

本卡交付 A3 隐藏 Boss 星陨先知（附录 E.6，HP 3200 三阶段）+ 隐藏门接线。Boss 侧
（`core/enemies/bosses/starfall_prophet.gd`，469 行）实现完整：P1 元素轮回四轮 +
星陨追踪（可近战反弹击回 Boss）、P2 单元素领域 + 共鸣斩、P3 星河滚筒墙 + 召唤，
招式序列状态机沿用 VineColossus/MagmaTyrant 习语，数值逐键对照附录 E.6 全部命中
（见下表）。测试 19 个均为真断言（弹数/角度/速度/时序/相位门控/门信号逐项核对，
非同义反复）。主要问题集中在**隐藏门的触发时序**（Critical，波 1 杂兵死亡即提前
开门）与**共鸣斩第二击被玩家受击无敌帧吞掉**（Important，测试鸭子替身掩盖了真实
Player 契约分叉）。

实现者自述的 4 项偏差核实：
1. 「携带任意共鸣」→「本层触发过任意共鸣」：**理由属实**。`core/player/player.gd`
   无 `status` 属性（仅 `status_rate_bonus`/`effective_status_rate_multiplier`），
   `take_hit_ctx`（player.gd:218-267）对来伤元素不做任何状态积累——玩家侧确无
   共鸣携带机制，宽松口径成立，且计数源（EventBus.resonance_triggered，仅
   enemy_base.gd:302 敌侧共鸣广播）语义自洽。
2. 共鸣斩鸭子接缝：接缝本身成立，但**同拍双击被受击无敌帧吞掉**未披露（Important-2）。
3. drops "gems3,soul" 附录无据：**属实**（附录 E.6/H 均无 Boss 掉落行；其余 Boss 行
   均无 drops 键）。`RunState.add_gems` 与 `add_coins` 习语一致；main 上唯一其它写入
   点是 `next_floor` 内 `gems += FLOOR_GEMS[...]`（run_state.gd:89）直加，口径不冲突。
4. 半成品零丢弃：单提交包含自述全部文件（boss + 测试 + enemies.json/factory/
   floor_scene/run_state/audio/pickup 七处接线），内容自洽，未见缺口。

## 二、规格符合度（附录 E.6 逐键核对）

| E.6 键 | 规格 | 实现 | 判定 |
|---|---|---|---|
| HP | 3200 | enemies.json `hp:3200` | ✓ |
| P1 元素轮回 前摇/伤/轮数 | 0.6s / 6 / 4 轮 | `CYCLE_WINDUP_TICKS=36`；`row.bullet_dmg=6`；`CYCLE_ROUNDS=4`，轮间隔 24t（发射拍 36/60/84/108，测试钉死） | ✓ |
| 轮回元素序 | 火环/冰针/毒云/电链 | `CYCLE_ELEMENTS=[FIRE,ICE,POISON,SHOCK]`，游标跨施法延续（测试 test_..._persists_across_casts 断言第二次施法回火） | ✓ |
| P1 星陨 前摇/伤/颗数 | 0.8s / 7 / 3 颗可反弹 | `STARFALL_WINDUP_TICKS=48`、`STAR_DMG=7`、`STAR_COUNT=3`；反弹链路完整验证：melee.gd:47-49 招架窗 `combat.reflect`（combat_system.gd:257-263 翻 PLAYER 面）→ `_live_stars()`（仅 ENEMY 面）自动出追踪集 → PLAYER 弹与 ENEMY 战斗体标准碰撞结算（combat_system.gd:147-158）；测试断言反弹后不再转向 + Boss 掉血 | ✓ |
| P2 领域 前摇/时长 | 1.0s / 8s | `FIELD_WINDUP_TICKS=60`、`FIELD_DURATION_TICKS=480`；重施 `FIELD_ORDER` 轮转切元素并重锚窗口（测试断言 火→冰 + 过期清空） | ✓ |
| P2 领域「伤 6」 | 表内伤 6 | 领域本体不直接伤害，6 为存续招式弹延续行伤 `bullet_dmg=6` | 解释性成立（Boss 侧口径已在头注释披露） |
| P2 共鸣斩 前摇/伤 | 0.5s / 8 | `SLASH_WINDUP_TICKS=30`、`SLASH_DMG=8`，90°/70px 与熔核暴君火拳（magma_tyrant.gd:34-37）同款 | ✓（几何为附录未规定的自定补充） |
| P2 共鸣斩 强制第二状态 | 对已有异常玩家强制附加 | 鸭子接缝实现（`Resonance.compatible_partner` + `StatusComponent.force_resonance` 均存在且语义匹配）；**但第二击在真实 Player 上被同拍受击无敌帧吞（Important-2）** | 部分 |
| P3 星河 前摇/伤/波数 | 1.2s / 6 / ×3 波 | `GALAXY_WINDUP_TICKS=72`、行伤 `bullet_dmg=6`、`GALAXY_WAVES=3`（间隔 48t，方向 +1/-1/+1 交替，测试钉死） | ✓ |
| P3 缺口罩间 | 缺口即安全通道 | 前/后半区各 1 缺口×2 连续行（g1∈[0,4]、g2∈[6,10]，构造上不重叠；测试断言 4 行缺失且成对连续）。坐标推演：中段缺口自由中心窗 40px（弹 r4+玩家 r6，两缺失行两侧 30px−10px）；**贴边缺口（rows {0,1}/{10,11}）退化至约 10px 中心余量**（见 Minor-5） | ✓（可走，贴边偏紧） |
| P3 召唤 2 星髓聚合体 | 期间召唤 2 | `GALAXY_SUMMON_COUNT=2`，archetype `starmarrow_blob`（enemies.json:41 存在），counts_for_wave=false | ✓ |
| 阶段阈值 | —（附录未规定） | `phases:[1.0,0.6,0.3]` → P2@60%/P3@30%，与其余四 Boss 一致 | ✓ |
| 弹速契约 | 附录 H A3 | bullet_speed 100，电链 150（=契约上限），毒云 60 | ✓ |
| contact_dmg | 附录 H A3 基准 9 | `contact_dmg:9` | ✓ |

其余附录未规定的自定补充（火环 12/冰针 5 扇 ±30°/毒云 4 慢弹 60px·r8·3.5s/电链 4 快索
±12°/星陨转向率 0.035rad·life 4s/星河 12 行×20px·life 5s）均有测试逐项锁定，数值自洽。

## 三、质量发现

### Critical

**C-1 隐藏门在小 Boss 房波 1 杂兵死亡时即提前开启（非小 Boss 死亡）**
- 证据：`core/rooms/floor_scene.gd:1033` 的 `_maybe_open_starfall_gate(room, death_pos)`
  位于 `if room.room_flow.cleared and not room.cleared_emitted:` 块**之外**，对每次
  counts_for_wave 死亡都执行；守卫（floor_scene.gd:1092-1098）只检查
  `room.type=="miniboss"` + `floor_idx>=3` + `_floor_resonances>0` + 幂等，**既不检查
  死者是小 Boss，也不检查房间已清**。而小 Boss 房波次为 `[杂兵×2, ["miniboss_charger"]]`
  （floor_scene.gd:1459-1461 `waves_for`，全楼层通用）。
- 后果：A3 层玩家只要本层触发过任意共鸣（共鸣为游戏签名系统，常态发生），杀死小 Boss 房
  **第一波的第一只杂兵**就会开门并让 3200 血隐藏 Boss 提前进场——违背「击杀小 Boss 且
  本层共鸣 → 开门」的规格（design.md:275、roadmap:136）与实现者自己的注释/测试命名
  （"on_a3_miniboss_kill"）。
- 为何测试没抓住：`test_hidden_gate_opens_on_a3_miniboss_kill_with_resonance`
  （tests/unit/test_boss_m2_prophet.gd:558-585）在杀死波 1 杂兵**之后**才发出共鸣事件
 （563-565 行），刻意避开了「共鸣计数先于杂兵死亡」的生产常见时序。
- 修复建议：`_maybe_open_starfall_gate` 增加 `if not room.room_flow.cleared: return`
 （小 Boss 为末波，房清即小 Boss 已死），或传 `killed_row` 并要求
  `String(killed_row.get("guest_kind","")) == "miniboss"`；同时补一条负向测试
 （共鸣>0 时击杀波 1 杂兵不得开门/不得生成先知）。

### Important

**I-1 共鸣斩第二击被玩家受击无敌帧吞掉，生产环境只落一击**
- 证据：`starfall_prophet.gd:352` 与 `:362` 在**同一物理帧**先后两次 `_hit_player`
 （伤 8「共鸣斩」+ 伤 8「元素共鸣」）。真实 `Player.take_hit_ctx` 首击后置
  `_iframe_until = frame + HURT_IFRAME_TICKS(48)`（player.gd:231），第二击在
  `is_invincible_at(frame)`（player.gd:205-206，224-225 早退）处被吞——伤害、事件、
  遥测全部不发生。
- 测试鸭子 `SpyPlayer`/`StatusedPlayer`（test_boss_m2_prophet.gd:26-43）的 `take_hit`
  只记录不判无敌帧，故三条共鸣斩测试断言 2 击/16 伤——**测试锁定的行为在生产不可达**
 （真实玩家只吃 8 伤；因玩家侧无 StatusComponent，"第二状态"本就无从落地，见偏差①）。
  实现者披露了鸭子接缝但未披露无敌帧吞击。
- 修复建议（三选一）：第二击延后 ≥48t 结算（沿用 hazard/aoe_delay 延迟习语）；或合并为
  单次 16 伤带搭档元素的单击；或明确接受「第二击仅状态语义、生产单击 8 伤=附录伤值」，
  改测试为对真实 Player 契约（含无敌帧）的替身断言。

**I-2 与 m2-t31（未合 main）的合并面冲突（按指示仅标注，不解决）**
- 文本冲突①：两分支在**同一位置**各自新增 `RunState.add_gems`（本卡
  autoload/run_state.gd:112-115 vs m2-t31 autoload/run_state.gd:114-117，函数体相同、
  注释不同）——合并必起冲突（解决平凡）。
- 文本冲突②：两分支同改 `_on_enemy_died`：t31 在 `RunState.add_kill()` 后插入击杀
  蓝晶路由（m2-t31 floor_scene.gd:1002-1005），本卡在中部插入先知嘉宾掉落块
 （floor_scene.gd:1017-1022）+ 尾部插入门调用（:1033）。hunk 相邻不重叠，git 可能
  自动合并，但需人工复核顺序语义。
- 语义叠加：t31 的 `boss_script != "" → kill_kind="boss"` 兜底会把 starfall_prophet
  归入 Boss 档击杀蓝晶（+50，首杀再 +300 入池），叠加本卡的 3 颗实体拾取蓝晶
 （drops gems3）——隐藏 Boss 死亡经济双口径，合并时需裁定（保留其一或明确并存）；
  另 t31 注释中真实 Boss 行枚举（vine_colossus/gem_queen/prism_golem/frost_widow/
  magma_tyrant）合并后缺 starfall_prophet，注释需更新。

### Minor

**M-1 星陨追踪热路径每拍分配 + 全池扫描**
- `starfall_prophet.gd:297-306` `_stars_home_tick` → `_live_stars()`（:286-293）在每次
  `_engage` 拍分配一个 Array 并 O(存活弹)（上限 ~400-500）扫描，**无星在空时也无早退**。
  同类背景效果（magma_tyrant `_erupt_tick`/`_rain_tick`）遍历自有区列表、零分配，且
  combat_system.gd:39-43 明示全池清点仅接受低频发射拍。与「热路径零分配」自述相悖。
- 建议：粘性 `_stars_live` 标志（starfall 施法置位、扫描未见星时清零）或内联扫描免建数组。

**M-2 领域「敌我伤害转化」仅实现 Boss 侧**
- `starfall_prophet.gd:312-313` `_spawn_element()` 只转化 Boss 自身招式弹/直击元素；
  E.6 P2「领域内**敌我**伤害转化」的玩家侧（玩家攻击被转化）未实现。头注释已披露
 「Boss 侧口径」，属规格降采样，建议在卡内或后续卡补玩家侧或修订规格口径。

**M-3 `_galaxy_rng` 缺兄弟 Boss 的懒初始化护栏**
- vine_colossus.gd:290-291（magma_tyrant 同款）在消费前有 `if _rain_rng == null` 兜底；
  starfall_prophet.gd:383-384 直接 `_galaxy_rng.randi_range`——手工构造未走
  `_test_init`/`setup` 的调试路径进 P3 会空引用崩溃（生产 EnemyFactory 必经 setup，不受影响）。

**M-4 星河墙体纵向超出生产房间内域，贴边缺口偏紧**
- 生产模板均为 22×14 瓦（data/rooms/a1_templates.json）→ 内域 320×192；12 行×20px
  展幅 220px，行 0/11 各入墙带 14px（弹不撞墙、仅视觉压墙，与既有全弹幕行为一致）。
  贴边缺口（rows {0,1} 或 {10,11}）自由中心窗仅 ~10px（玩家 r6+弹 r4），中段缺口 40px
  宽裕。测试 BOUNDS 用 456×238（test_boss_m2_prophet.gd:23）大于生产内域，未覆盖贴边情形。
- 建议：缺口行抽样向内收（如 g1∈[1,4]、g2∈[7,10]），或展幅按内域高缩放。

**M-5 隐藏 Boss 无 Boss 曲层**
- `AudioMgr.boss_layer(true)` 仅挂 `room_type=="boss"` 首进（floor_scene.gd:1193-1194）；
  先知在小 Boss 房开打走生态曲，死亡亦无 `boss_layer(false)`（因从未开启，无残留状态）。
  表现层缺口，建议门开启时切 boss 曲、先知死亡恢复。

**M-6 蓝晶拾取无专属贴图**
- `art/generated/pickups/` 无 gem.png，`Pickup._ready`（pickup.gd:26-31）回落默认多边形
  染蓝——与心形轮廓同模（`_shape_for` default 分支），辨识度弱。音频已正确映射
  `pickup_gem → pickup_energy.wav`（audio_mgr.gd KEY_FILE）。

**M-7 「soul」头目魂贴花为纯表现**
- `_build_boss_soul`（floor_scene.gd 内）为无战斗数值的星形贴花，随房存续；与自述一致，
  无问题，仅备案（附录无据的设计补充，同偏差③）。

### 质量维度总评（非问题项）

- **盐纪律 ✓**：`GALAXY_RNG_SALT="boss_starfall_prophet_galaxy"` 单点定义于
  starfall_prophet.gd:69，`_test_init` 走 `RngSvc.stream(floor_idx, salt)`、`setup` 走
  `RunState.stream(salt)`（两者等价，run_state.gd:99-101）——与 magma/vine 完全同款；
  全仓 grep 无调用点字面量（测试也不引用盐字符串，测试流用独立 "prophet_*_test" 盐）。
- **.uid ✓**：`starfall_prophet.gd.uid`、`test_boss_m2_prophet.gd.uid` 均已提交（合法 uid://）。
- **文案 ✓**：注释中文、标识符英文；attack_name（星陨/星河/共鸣斩/元素共鸣）为面向玩家
  中文文案，与「燎原」「毒火云」等既有口径一致。
- **隐藏门其余语义 ✓**：幂等（floor_scene.gd:1097 `has_node("StarfallGate")` + 每层唯一
  小 Boss 房，floor_flow.gd:60-63 `break` 取首个）；`_floor_resonances` 随楼层实例重建清零
 （run_root.gd:112-124 `_start_floor` 释放旧 FloorScene 新建实例，EventBus 连接随实例
  释放自动断开）；嘉宾 `counts_for_wave=false` 不消费波次、不回锁已清房
 （FloorFlow.is_locked 按 cleared 集合判定，floor_flow.gd:135-136）；先知死亡不误发
  `boss_defeated`/层间中转（room.type=="boss" 门控）；死亡掉落走行内 drops（gems3+soul）。
- **测试质量 ✓**：19/19 真断言——轮回发射拍序列/25 弹池序元素分轮/火环 12 发相邻角差
  τ/12/冰针互异方向数/星陨转向单调有界/反弹星停追踪+击回掉血/领域元素全覆盖轮回弹/
  重施换元素/滚筒三波方向交替+缺口成对连续+前后半区/门开（信号+贴花+先知入场+波次外+
  3 蓝晶+魂）/门不开（无共鸣、层号<3）。缺口：缺 C-1 的负向时序测试、I-1 的真实
  Player 无敌帧契约测试。

## 四、结论

**NEEDS FIXES**

- **必须修复**：C-1（隐藏门提前开启——一行守卫 + 一条负向测试）。
- **应当修复**：I-1（共鸣斩同拍二击被无敌帧吞——测试与生产行为分叉）；I-2 为合并期
  标注项，随 t31 合并时裁定。
- 其余 Minor 可随修复轮顺手处理或登记后续卡。
- 复跑结果：全量 1116/1116（0 失败/0 错误/0 flaky），prophet 套件 19/19；实现者自述的
  telemetry 偶发未复现。
