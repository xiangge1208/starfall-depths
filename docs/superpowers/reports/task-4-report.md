# M2 Task 4（A2 生态——暗视野 + 冰面）独立评审报告

- **被审对象**：分支 `m2-t4`，单 commit `e0580e4` `feat(m2-t4): a2 dark vision + ice floor biome`（基线 `ed88ef8`），worktree `D:\workspace\thomas\.worktrees\m2-t4`
- **评审方式**：只读评审（本报告为唯一写出的文件）；逐文件精读 diff + GDD §10 + 计划卡 Task 4 对照 + 本机实测全量测试
- **评审日期**：2026-08-30

## 结论：Approved-with-notes

规格四项全部符合（两处口径取舍均已如实披露且与计划卡一致）；测试真实且非摆设；本机实测 **740/740 全绿（48/48 套件，0 orphans，exit 0）**，与实现者自报一致。存在 1 项**潜伏型 Major 生命周期缺口**（楼层销毁路径不还原玩家 `friction_mult`）与若干 Minor，均不阻塞合并，建议随 T16/T26（冰面复用方 / biome 字段接线卡）或先行小修闭环。

---

## 一、规格符合度逐项

| # | 规格项（计划卡 Task 4 / GDD §10 A2） | 判定 | 依据 |
|---|---|---|---|
| 1 | 暗视野：CanvasModulate (0.25,0.25,0.35) | **PASS** | `biome_fx.gd:7` `DARK_COLOR`；`_ready` 建子节点并设色；测试 `test_setup_mounts_canvas_modulate_and_player_light` 断言精确色值 |
| 2 | 玩家 PointLight2D 半径 140px、能量 1.2、二次衰减 | **PASS（带注）** | 能量 `biome_fx.gd:10`；有效半径 = 纹理半宽 128 × `texture_scale` 280/256 = **140.0 整**（`biome_fx.gd:50`，测试以 ±0.5 验证）；「二次衰减」用 GradientTexture2D 单锚点（d=0.5, α=0.25=(1-0.5)²）分段线性近似，与真二次曲线最大偏差 ≈6% alpha，代码注释如实披露（见 Minor-2） |
| 3 | 敌人剪影 modulate 下限 0.4（公平性） | **PASS** | `biome_fx.gd:11` `SILHOUETTE_FLOOR`；`silhouette_modulate()` 纯函数 clamp 到 [0.4, 1.0]；测试覆盖 0→1.0、140→0.4、1000→0.4 与单调性 |
| 4 | 冰面：玩家摩擦系数 ×0.25，进入替换/离开恢复 MoveMath friction | **PASS** | `ice_floor.gd:5` `FRICTION_MULT=0.25`；`player.gd:46,79-80` `FRICTION * friction_mult`；`floor_scene.gd:170` 每物理帧 `biome_ice.tick(player)` 进出接缝；注入帧测试验证 80→72.5（冰）与 80→50（常轨）衰减差 |
| 5 | 敌人不受冰面影响 | **PASS** | 结构性保证：`IceZone.tick(player: Player)` 只收 Player；`EnemyBase` 无 `friction_mult` 字段（测试 `"friction_mult" in enemy` 断言为 false） |
| 6 | A2 模板 hazards/biome 字段驱动钩子（floor_scene 挂载点，幂等） | **PASS（带注）** | `floor_scene.gd:136` `set_biome_a2(enabled)` 挂载/卸载钩子，双向幂等（同值早退，测试覆盖 true/true 与 false/false）；冰面区域暂由常量演示补丁驱动（`floor_scene.gd:26,153`），biome JSON 字段消费按计划留给 T26——与卡文「后续卡提供 biome 字段」一致（见 Minor-5） |
| 7 | TDD：暗视野纯参数单测；冰面摩擦进出恢复断言（注入帧 velocity 序列） | **PASS（带注）** | `tests/unit/test_biome_a2.gd` 16 测：纯参数（常量/剪影曲线）、IceZone 纯函数、注入帧 `p._physics_process(0.0)` 驱动 velocity 断言、FloorScene 挂载/卸载/幂等。单 commit 同含测试与实现，RED-first 无法从历史核验（符合本流水线按卡原子提交的惯例，仅记录） |

**数值口径核查（实现者自报两处取舍，均属实、合理）：**

1. **×0.25 vs GDD「摩擦减半」**：GDD §10 表写「冰面(摩擦减半)」，计划卡明确「摩擦系数 ×0.25」且注明比减半更强的打滑——冲突以计划卡为准（评审指令同此判定）。`ice_floor.gd:4` 注释明示「比 GDD『减半』更强打滑」。披露属实。方向正确：摩擦降至 25% → 松手滑行 80/(450/60)=10.7 帧 vs 常轨 2.7 帧。
2. **A2 冰面补丁为常量演示**：每房内域中心 96×64 补丁，`floor_scene.gd:134` 注释明示待 A2 模板 JSON biome 字段（T26）替换。披露属实。这是卡内预留接缝而非偷工——`add_zone()` 接口已为数据驱动就绪。

---

## 二、质量发现

### Major

**Major-1（潜伏）：楼层销毁路径不还原玩家 `friction_mult`，冰面摩擦可跨层泄漏。**
- 位置：`core/rooms/biome_fx.gd:89`（`_exit_tree` 只调 `restore_enemies()`）＋ `core/rooms/run_root.gd:107`（`_start_floor` 直接 `floor_scene.queue_free()`，不经 `set_biome_a2(false)`）
- 链路：Boss 房清 → `run_root.gd:142` 旧层 `PROCESS_MODE_DISABLED`（`biome_ice.tick` 停摆，`friction_mult` 冻结在末帧值）→ 玩家进入层间中转 → 旧层 `queue_free`。若玩家在 Boss 死亡瞬间恰站冰面补丁上（Boss 房内域中心即补丁中心），`friction_mult=0.25` 冻结带入下一层——新层 `biome_ice==null` 永无恢复，玩家整层打滑。
- 潜伏性：当前生产代码**无任何 `set_biome_a2` 调用方**（全仓 grep 仅测试与本钩子定义），今日影响为零；T26 接线 / T16 寒渊蛛母「铺冰面」复用后即成为活缺陷。`set_biome_a2(false)` 显式卸载路径本身正确且有测试（敌人 modulate + 玩家摩擦均复位）。
- 建议：`BiomeFx._exit_tree()` 补一行 `if player != null and is_instance_valid(player): player.friction_mult = 1.0`（组件存活期间 tick 每帧覆写，此复位只在组件消亡时生效，无双写竞争）。

### Minor

- **Minor-1（热路径，合规但可更省）**：`biome_fx.gd:80` 每帧 `get_nodes_in_group("enemies")` 新建 Array（引擎侧分配），`biome_fx.gd:86` 对每个敌人无条件写 `modulate`（远敌恒 0.4 仍每帧写属性 → RenderingServer 调用）。**Global Constraint 5 的字面（零字符串拼接/零新建 Dictionary）满足**——`Color(m,m,m)` 为内联 Variant 非堆分配，组名为常量；但「零分配」精神下可加 `if e.modulate.r != m` 跳过不变写。≤40 敌规模下不构成实际问题，记录备查。
- **Minor-2**：二次衰减为分段线性近似（`biome_fx.gd:61` 单 0.5 锚点，偏差 ≤6% alpha，视觉不可辨）。注释与测试锚点均如实；如需更贴可补 0.25/0.75 锚点。
- **Minor-3（测试轻微同义反复）**：`test_biome_a2.gd:225` 近敌期望值用被测同一纯函数 `silhouette_modulate(20.0)` 计算（≈0.9143）。有 `test_silhouette_modulate_monotonic_to_floor` 的硬编码端点断言（0→1.0 / 140→0.4 / 1000→0.4）托底，不构成假绿；硬编码 `0.9143` approx 会更严格。
- **Minor-4**：`test_biome_a2.gd:14` `const SEED := 20260828` 全文件未使用（死常量）。
- **Minor-5（手动验证可行性）**：演示冰面补丁无任何视觉表现（纯 Rect2 逻辑），「冰面打滑手感」手动清单项在游戏中无法目视定位冰面边界。视觉归 T26 模板/T27 瓦片尚可辩护，但建议 T26 落地时给 zone 加最简着色/描边，否则手感验收始终盲测。
- **Minor-6（防御性）**：`floor_scene.gd:161` `set_biome_a2(false)` 复位 `player.friction_mult` 前只判 `player != null` 未判 `is_instance_valid`（悬垂引用会报错）。当前调用图不可达，随 Major-1 修复顺手补上即可。
- **记录（非缺陷）**：`restore_enemies()` 无条件写 `Color.WHITE`——与现有命中白闪无冲突（白闪走子节点 "Sprite" 的 ShaderMaterial，`autoload/fx.gd:203-213`，父子 modulate 乘法复合互不覆盖）；未来精英词缀若染 enemy 根 modulate 需改走复合而非直写。敌人弹不 dim（不在 "enemies" 组）→ 暗屏上弹幕保持高亮，客观上有利公平，与 GDD 意图相容。

### 实现者自报 2 处测试修复的方向核查（均正确，未掩盖实现 bug）

1. **`light.energy` float32 往返**（`test_biome_a2.gd:190-191`）：引擎属性按 float32 往返（1.2→1.20000004…），逐位相等必假相等；改为 `is_equal_approx(1.2, 0.0001)`。实现侧是常量直赋（`biome_fx.gd:49`），容差 1e-4 远小于任何语义差异——**改测试正确**。
2. **近敌 modulate 期望值**：改用剪影曲线推导（见 Minor-3）。方向正确——原期望若为半径内恒 1.0 的阶跃则是规格误读（GDD 只定 0.4 下限，圈内平滑衰减是合理设计）；既有硬编码端点断言保证纯函数本身被独立钉死。

### 热路径合规总检

| 检查点 | 结果 |
|---|---|
| `BiomeFx._process`（`biome_fx.gd:72-87`） | 零字符串拼接、零新建 Dictionary；逐帧 O(n) 写 modulate 无堆分配（Color 为值类型 Variant）；组查询 Array 分配见 Minor-1 |
| `FloorScene._physics_process`（`floor_scene.gd:169-170`） | `biome_ice.tick` 零分配（遍历 `Array[Rect2]` + 写 float 字段） |
| `Player._physics_process`（`player.gd:79-80`） | `FRICTION * friction_mult` 一次浮点乘，零分配 |
| 光斑纹理 | `_aura_texture()` 仅 `_ready` 一次性构建 |

### 组件生命周期总检

| 路径 | 结果 |
|---|---|
| 挂载（`set_biome_a2(true)`） | 建 BiomeFx + IceZone + 每房冰面补丁；无 player 时 push_error 并回滚标志；重复 true 幂等（测试覆盖） |
| 显式卸载（`set_biome_a2(false)`） | 敌人 modulate 复位（显式 + `_exit_tree` 双保险）、组件 queue_free、引用置 null、玩家摩擦回 1.0；重复 false 幂等（测试覆盖） |
| 楼层销毁（queue_free 不经 disable） | 敌人 modulate 复位 ✓；**玩家 friction_mult 不复位 ✗（Major-1）** |
| 层间静默期 | 旧层 `PROCESS_MODE_DISABLED` → tick/剪影均停摆（暗视野残留为氛围，可接受；冻结摩擦见 Major-1） |

---

## 三、测试实测计数（本机复跑，2026-08-30）

```
$ godot --headless --path . --import            → exit 0
$ godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
        -a res://tests --ignoreHeadlessMode     → exit 0

Overall Summary: 740 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans
Executed test suites: (48/48)
Executed test cases : (740/740)
Total execution time: 31s 386ms
```

新增 `tests/unit/test_biome_a2.gd` 单套件 **16/16 PASSED（393ms，0 orphans）**，逐条无跳过。与实现者自报 740/740 完全一致。

## 四、修复建议（Approved-with-notes，不阻塞合并）

1. **（对应 Major-1，建议随本卡 hotfix 或 T16 前落地）** `biome_fx.gd:89` `_exit_tree` 增加玩家摩擦复位：
   ```gdscript
   func _exit_tree() -> void:
       restore_enemies()
       if player != null and is_instance_valid(player):
           player.friction_mult = 1.0
   ```
   并在 `test_biome_a2.gd` 补一条「直接 `biome_fx.free()`（不走 disable）后 `friction_mult` 仍回 1.0」的断言。
2. **（对应 Minor-6）** `floor_scene.gd:161` 补 `is_instance_valid(player)`。
3. **（对应 Minor-1，可选）** `biome_fx.gd:86` 改为 `if e.modulate.r != m: e.modulate = Color(m, m, m)` 跳过不变写。
4. **（移交 T26）** biome 字段驱动替换常量演示补丁时：为冰面 zone 加最简视觉（Minor-5）；为 `set_biome_a2` 接层索引/模板调用方时回归「跨层泄漏」场景（Major-1 的验收方）。
5. **（顺手）** 删除 `test_biome_a2.gd:14` 未使用的 `SEED` 常量。

---

## 五、卫生检查

- commit 单一、conventional、带卡号（`feat(m2-t4): ...`）；8 文件 +475/-1，无 `.import`/`__pycache__`/数据表噪音；三个新脚本 `.uid` 均随卡提交（符合波次表注）。
- 未触碰他人独占文件（`core/rooms/floor_scene.gd` 为本卡声明的挂点修改文件，`player.gd` 仅 +1 字段 +1 行乘区，波次表未将其列为独占冲突）。
