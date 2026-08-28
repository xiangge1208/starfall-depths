# M0 战斗原型 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付可运行的战斗原型：移动/翻滚/射击/近战反弹、6 武器、4 敌人、1 战斗房+靶场房、Juice v1、伤害与元素共鸣结算模块+单测，通过 GDD §18.5 手感清单。

**Architecture:** Godot 4 场景树 + autoload 服务（GameDB/RngSvc/EventBus/Fx）；战斗逻辑跑在固定 60Hz `_physics_process`（物理帧即逻辑时钟）；弹幕走自研对象池+空间哈希；全部数值来自 `data/*.json`。

**Tech Stack:** Godot 4.x (GDScript)、GdUnit4、Python 3.12+Pillow（仅工具）、Node 22（仅工具）。

## Global Constraints（每个任务隐含继承）

- 逻辑固定 60Hz，禁止逻辑代码用 `Time.*` 墙钟；时长一律 `TimeConst.ticks(seconds)`。
- 伤害固定值；最终伤害 = `max(1, int(base × global_mult × (crit ? 2 : 1)))`；暴击是唯一随机乘区。
- 逻辑随机只经 `RngSvc` 派生流；禁止全局 `randi()/randf()`。
- 热路径零每帧分配；弹幕池化；同屏弹幕上限常量 `MAX_PROJECTILES = 500`（M0 压到 300 预分配）。
- 场景零硬编码玩法数值，一律读 `data/*.json`（移动/翻滚手感常量除外，集中于 `player.gd` 顶部常量区）。
- 渲染 480×270、nearest、`canvas_items` 拉伸；窗口放大 3 倍（1440×810）。
- 代码/标识符英文，玩家可见文案中文。
- 数值出处：GDD 附录 A（武器）、B（敌人）、H（经济速查）。发现表内矛盾→停止上报编排者。
- 提交规范：conventional commits，message 带任务号（`feat(m0-t4): ...`）。

---

### Task 1: 工程脚手架与环境验证

**Files:**
- Create: `project.godot`、`icon.svg`（默认）、`.gitignore`
- Create: `autoload/game_db.gd`、`autoload/rng_svc.gd`、`autoload/event_bus.gd`、`autoload/fx.gd`（本任务全部为可运行的空壳 stub）
- Create: `tools/setup_input.gd`、`tools/run_tests.cmd`
- Create: `tests/unit/test_smoke.gd`
- Create: `docs/superpowers/reports/env.md`

**Interfaces:**
- Produces: 可运行的 Godot 工程；autoload 名 `GameDB`/`RngSvc`/`EventBus`/`Fx`；`tools/run_tests.cmd` 一键无头测试；InputMap 动作 `move_left/move_right/move_up/move_down/fire/roll/switch_weapon/interact/skill/pause`。

- [ ] **Step 1: 安装并锁定 Godot 版本**

```bash
winget install --id GodotEngine.Godot -e --accept-source-agreements --accept-package-agreements
godot --version   # 若 PATH 未刷新，用安装输出的完整路径执行；记录版本
```

预期：输出 4.x stable 版本号。将版本与可执行路径写入 `docs/superpowers/reports/env.md`。若 winget 失败：从 godotengine.org 下载 win64 zip 解压到 `D:\tools\godot\` 并把 exe 目录加入本次会话 PATH（不改系统设置）。

- [ ] **Step 2: 创建工程与目录结构**

在 `D:\workspace\thomas` 下执行 `godot -e --path . --quit` 生成 `project.godot`，然后手工写入以下配置键（合并进生成的文件）：

```ini
[application]
config/name="StarfallDepths"
run/main_scene="res://tools/blank_main.tscn"   ; 占位主场景（Node2D 空树）；m0-t12 改指向 training_room.tscn
config/features=PackedStringArray("4.4")

[display]
window/size/viewport_width=480
window/size/viewport_height=270
window/size/window_width_override=1440
window/size/window_height_override=810
window/stretch/mode="canvas_items"
window/stretch/scale_mode="integer"

[rendering]
textures/canvas_textures/default_texture_filter=0

[physics]
common/physics_ticks_per_second=60

[autoload]
EventBus="*res://autoload/event_bus.gd"
GameDB="*res://autoload/game_db.gd"
RngSvc="*res://autoload/rng_svc.gd"
Fx="*res://autoload/fx.gd"

[editor_plugins]
enabled=PackedStringArray("gdUnit4")
```

目录树一次建齐：

```
autoload/  core/player/ core/combat/ core/enemies/archetypes/ core/rooms/
data/rooms/ ui/ fx/ art/generated/ audio/generated/
tools/ tests/unit/ tests/scenes/ docs/superpowers/reports/
```

`tools/blank_main.tscn`：空 Node2D 场景（文本格式手写即可：`[gd_scene format=3][node name="Blank" type="Node2D"]`）。

`.gitignore`：

```
.godot/
*.tmp
user_export/
```

- [ ] **Step 3: 安装 GdUnit4 插件**

```bash
curl -L -o /tmp/gdunit4.zip https://github.com/MikeSchulze/gdUnit4/archive/refs/heads/master.zip
unzip -o /tmp/gdunit4.zip -d /tmp
mkdir -p addons && cp -r /tmp/gdUnit4-master/addons/gdUnit4 addons/
godot --headless --path . --import   # 首次导入资源
```

预期：`addons/gdUnit4/` 存在且无导入报错。（若 master 分支 zip 失败，改用最新 release tag 的 zip，版本记入 env.md。）

- [ ] **Step 4: 写 autoload 空壳**

`autoload/event_bus.gd`：

```gdscript
extends Node
## 全局事件总线。信号随任务追加，先声明 M0 已知的。
signal enemy_damaged(amount: int, is_crit: bool)
signal enemy_killed(enemy_id: String)
signal player_damaged(amount: int, fatal: bool)
signal status_applied(target: Node, element: int)
signal resonance_triggered(reaction: int, at: Vector2, payload: Dictionary)
signal room_cleared(room_id: String)
```

`autoload/game_db.gd`：

```gdscript
extends Node
## 数据库：加载 res://data/*.json（m0-t2 起有真实数据）。当前为可运行空壳。
var weapons: Dictionary = {}

func get_weapon(id: String) -> Dictionary:
    return weapons.get(id, {})
```

`autoload/rng_svc.gd`：

```gdscript
extends Node
## 种子化随机服务（m0-t3 实现完整逻辑，当前空壳可运行）。
var run_seed: int = 0
func setup_run(seed: int) -> void:
    run_seed = seed
```

`autoload/fx.gd`：

```gdscript
extends Node
## 打击感服务（m0-t12 实现完整逻辑，当前空壳保证 t7~t11 可调用）。
func hitstop(_ms: int) -> void: pass
func shake(_strength: float, _duration: float) -> void: pass
func on_roll(_player: Node2D) -> void: pass
func on_player_hurt(_player: Node2D, _amount: int) -> void: pass
func on_enemy_hit(_enemy: Node2D, _ctx: Dictionary) -> void: pass
func spawn_damage_number(_pos: Vector2, _amount: int, _is_crit: bool) -> void: pass
```

- [ ] **Step 5: InputMap 初始化脚本**

`tools/setup_input.gd`（一次性运行：`godot --headless --path . --script tools/setup_input.gd`）：

```gdscript
@tool
extends SceneTree
## 幂等写入 InputMap 动作并保存到 project.godot

const ACTIONS := {
    "move_left": [KEY_A, KEY_LEFT],
    "move_right": [KEY_D, KEY_RIGHT],
    "move_up": [KEY_W, KEY_UP],
    "move_down": [KEY_S, KEY_DOWN],
    "fire": [],        # 鼠标键在下方单独加
    "roll": [KEY_SHIFT, KEY_SPACE],
    "switch_weapon": [KEY_Q],
    "interact": [KEY_E],
    "skill": [KEY_F],
    "pause": [KEY_ESCAPE],
}

func _init() -> void:
    for action: String in ACTIONS:
        if not InputMap.has_action(action):
            InputMap.add_action(action, 0.2)
        for key: Key in ACTIONS[action]:
            var ev := InputEventKey.new()
            ev.physical_keycode = key
            InputMap.action_add_event(action, ev)
    var mb := InputEventMouseButton.new()
    mb.button_index = MOUSE_BUTTON_LEFT
    InputMap.action_add_event("fire", mb)
    ProjectSettings.save()
    quit(0)
```

- [ ] **Step 6: 写冒烟测试并跑通测试链路**

`tests/unit/test_smoke.gd`：

```gdscript
class_name TestSmoke
extends GdUnitTestSuite

func test_autoloads_exist() -> void:
    assert_object(GameDB).is_not_null()
    assert_object(RngSvc).is_not_null()
    assert_object(EventBus).is_not_null()
    assert_object(Fx).is_not_null()

func test_input_actions_registered() -> void:
    for a in ["move_left", "fire", "roll", "switch_weapon"]:
        assert_bool(InputMap.has_action(a)).is_true()
```

`tools/run_tests.cmd`：

```cmd
@echo off
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests %*
```

- [ ] **Step 7: 运行验证**

Run: `tools/run_tests.cmd`
Expected: 2 个测试 PASS（若 GdUnit 命令行参数有出入，按 `addons/gdUnit4/README` 校正 `run_tests.cmd` 直到绿——这是本任务交付物之一）。

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore(m0-t1): godot project scaffold, autoloads stub, input map, gdunit wired"
```

---

### Task 2: GameDB 数据加载与 schema 校验

**Files:**
- Create: `data/weapons.json`
- Modify: `autoload/game_db.gd`（替换空壳）
- Create: `tests/unit/test_game_db.gd`

**Interfaces:**
- Consumes: 无
- Produces: `GameDB.weapons: Dictionary`（id→行）、`GameDB.get_weapon(id) -> Dictionary`、`GameDB.validate() -> Array[String]`（错误清单，空=通过）、`GameDB.load_ok: bool`。武器行 schema 见下，后续任务按此读表。

- [ ] **Step 1: 写失败测试**

`tests/unit/test_game_db.gd`：

```gdscript
class_name TestGameDb
extends GdUnitTestSuite

func test_m0_weapons_loaded() -> void:
    for id in ["laohuoji", "maodingqiang", "duangong", "xuetufazhang", "tiejian", "shuangbi"]:
        assert_dict(GameDB.weapons).contains_key(id)

func test_get_weapon_returns_row() -> void:
    var w := GameDB.get_weapon("laohuoji")
    assert_str(w.get("name", "")).is_equal("老伙计")
    assert_int(w.get("damage", -1)).is_equal(2)
    assert_bool(w.get("is_melee", true)).is_false()

func test_validate_rejects_bad_row() -> void:
    var bad := {"id": "x", "damage": "many"}   # 缺键 + 类型错
    var errors: Array[String] = GameDB.validate_row(bad, GameDB.WEAPON_SCHEMA)
    assert_int(errors.size()).is_greater(0)
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/run_tests.cmd`
Expected: FAIL（`weapons` 为空 / 无 `validate_row`）。

- [ ] **Step 3: 写 weapons.json（M0 六把，出处附录 A）**

```json
{
  "laohuoji":    {"id":"laohuoji","name":"老伙计","category":"pistol","rarity":"common","damage":2,"rate":4.0,"energy_cost":0,"bullet_speed":320,"spread_deg":2.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0},
  "maodingqiang":{"id":"maodingqiang","name":"铆钉枪","category":"pistol","rarity":"common","damage":2,"rate":3.5,"energy_cost":0,"bullet_speed":320,"spread_deg":4.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0},
  "duangong":    {"id":"duangong","name":"短弓","category":"bow","rarity":"common","damage":5,"rate":1.8,"energy_cost":0,"bullet_speed":380,"spread_deg":0.5,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0},
  "xuetufazhang":{"id":"xuetufazhang","name":"学徒法杖","category":"staff","rarity":"common","damage":3,"rate":2.5,"energy_cost":0,"bullet_speed":260,"spread_deg":3.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0},
  "tiejian":     {"id":"tiejian","name":"铁剑","category":"melee","rarity":"common","damage":6,"rate":2.2,"energy_cost":0,"bullet_speed":0,"spread_deg":0.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":true,"range":40,"arc_deg":90.0},
  "shuangbi":    {"id":"shuangbi","name":"双匕","category":"melee","rarity":"common","damage":4,"rate":3.4,"energy_cost":0,"bullet_speed":0,"spread_deg":0.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":true,"range":32,"arc_deg":80.0}
}
```

- [ ] **Step 4: 实现 GameDB**

`autoload/game_db.gd` 全量替换：

```gdscript
extends Node
## 数据库 autoload：启动加载 data/*.json 并校验 schema；有错误则报错退出。

const WEAPON_SCHEMA := {
    "id": TYPE_STRING, "name": TYPE_STRING, "category": TYPE_STRING,
    "rarity": TYPE_STRING, "damage": TYPE_INT, "rate": TYPE_FLOAT,
    "energy_cost": TYPE_INT, "bullet_speed": TYPE_INT, "spread_deg": TYPE_FLOAT,
    "projectiles": TYPE_INT, "pierce": TYPE_INT, "bounce": TYPE_INT,
    "element": TYPE_STRING, "is_melee": TYPE_BOOL,
}
# 可选键及默认值
const WEAPON_OPTIONAL := {"range": 0, "arc_deg": 0.0}
const TABLES := {"weapons": "res://data/weapons.json"}

var weapons: Dictionary = {}
var load_ok := true

func _ready() -> void:
    weapons = _load_table("res://data/weapons.json", WEAPON_SCHEMA, WEAPON_OPTIONAL)
    if not load_ok:
        push_error("GameDB: data validation failed")
        get_tree().quit(1)

func get_weapon(id: String) -> Dictionary:
    return weapons.get(id, {})

func validate_row(row: Dictionary, schema: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    for key: String in schema:
        if not row.has(key):
            errors.append("missing key: %s" % key)
        elif typeof(row[key]) != schema[key]:
            errors.append("type mismatch: %s want %d got %d" % [key, schema[key], typeof(row[key])])
    return errors

func _load_table(path: String, schema: Dictionary, optional: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    if not FileAccess.file_exists(path):
        load_ok = false
        push_error("GameDB: missing %s" % path)
        return out
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
        load_ok = false
        push_error("GameDB: bad json %s" % path)
        return out
    for id: String in parsed:
        var row: Dictionary = parsed[id]
        if row.get("id", "") != id:
            load_ok = false
            push_error("GameDB: id mismatch %s" % id)
        var errs := validate_row(row, schema)
        if not errs.is_empty():
            load_ok = false
            push_error("GameDB %s row %s: %s" % [path, id, ", ".join(errs)])
        for k: String in optional:
            if not row.has(k):
                row[k] = optional[k]
        out[id] = row
    return out
```

注意：`rate`/`spread_deg` 等 JSON 小数会被 parse 成 float ✓；`damage` 写成 `2.0` 会变 float 导致类型错——表里必须写整数字面量（上表已是）。

- [ ] **Step 5: 运行测试**

Run: `tools/run_tests.cmd`
Expected: 全部 PASS（含 t1 冒烟）。

- [ ] **Step 6: Commit**

```bash
git add data/weapons.json autoload/game_db.gd tests/unit/test_game_db.gd
git commit -m "feat(m0-t2): game_db json loader with schema validation + 6 m0 weapons"
```

---

### Task 3: RngSvc 种子链 + TimeConst + Resonance/Elements 纯逻辑

**Files:**
- Modify: `autoload/rng_svc.gd`（替换空壳）
- Create: `core/combat/time_const.gd`、`core/combat/elements.gd`、`core/combat/resonance.gd`、`core/combat/damage_calc.gd`
- Create: `tests/unit/test_rng.gd`、`tests/unit/test_resonance.gd`、`tests/unit/test_damage_calc.gd`

**Interfaces:**
- Produces:
  - `RngSvc.setup_run(seed: int)`、`RngSvc.stream(floor_idx: int, salt: String) -> RandomNumberGenerator`（同参数同序列）
  - `TimeConst.ticks(seconds: float) -> int`、`TimeConst.FPS = 60.0`
  - `Elements.Id {NONE, FIRE, ICE, POISON, SHOCK}`、`Elements.from_name(String) -> int`
  - `Resonance.R {NONE, SHATTER, BLAZE, SUPERCONDUCT, ELECTROLYSIS}`、`Resonance.resolve(a: int, b: int) -> int`（对称）
  - `DamageCalc.compute(base: int, rng, crit_chance: float, crit_mult := 2.0, global_mult := 1.0) -> Dictionary{amount:int, is_crit:bool}`

- [ ] **Step 1: 写失败测试**

`tests/unit/test_rng.gd`：

```gdscript
class_name TestRng
extends GdUnitTestSuite

func test_same_seed_same_sequence() -> void:
    RngSvc.setup_run(12345)
    var a := RngSvc.stream(1, "combat")
    var b := RngSvc.stream(1, "combat")
    for _i in 10:
        assert_float(a.randf()).is_equal(b.randf())

func test_different_floor_different_sequence() -> void:
    RngSvc.setup_run(12345)
    var a := RngSvc.stream(1, "combat")
    var b := RngSvc.stream(2, "combat")
    var diff := false
    for _i in 10:
        if a.randf() != b.randf(): diff = true
    assert_bool(diff).is_true()

func test_stable_hash_known_vector() -> void:
    # FNV-1a-64("") = 0xcbf29ce484222325；对单字节 0x00：h ^= 0 → h * prime
    assert_int(RngSvc.stable_hash(0, 0)).is_equal(RngSvc.stable_hash(0, 0))
    assert_int(RngSvc.stable_hash(1, 2)).is_not_equal(RngSvc.stable_hash(2, 1))
```

`tests/unit/test_resonance.gd`：

```gdscript
class_name TestResonance
extends GdUnitTestSuite

func test_four_pairs() -> void:
    assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.ICE)).is_equal(Resonance.R.SHATTER)
    assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.POISON)).is_equal(Resonance.R.BLAZE)
    assert_int(Resonance.resolve(Elements.Id.ICE, Elements.Id.SHOCK)).is_equal(Resonance.R.SUPERCONDUCT)
    assert_int(Resonance.resolve(Elements.Id.POISON, Elements.Id.SHOCK)).is_equal(Resonance.R.ELECTROLYSIS)

func test_symmetric_and_negative() -> void:
    assert_int(Resonance.resolve(Elements.Id.ICE, Elements.Id.FIRE)).is_equal(Resonance.R.SHATTER)
    assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.FIRE)).is_equal(Resonance.R.NONE)
    assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.SHOCK)).is_equal(Resonance.R.NONE)
```

`tests/unit/test_damage_calc.gd`：

```gdscript
class_name TestDamageCalc
extends GdUnitTestSuite

func test_fixed_no_variance() -> void:
    var rng := RngSvc.stream(0, "test")
    rng.seed = 7
    for _i in 20:
        var r := DamageCalc.compute(5, rng, 0.0)   # 暴击率 0
        assert_int(r["amount"]).is_equal(5)

func test_crit_doubles() -> void:
    var rng := RngSvc.stream(0, "test")
    rng.seed = 7
    var r := DamageCalc.compute(5, rng, 1.0)       # 必暴
    assert_int(r["amount"]).is_equal(10)
    assert_bool(r["is_crit"]).is_true()

func test_min_clamp_and_global_mult() -> void:
    var rng := RngSvc.stream(0, "test")
    rng.seed = 7
    assert_int(DamageCalc.compute(3, rng, 0.0, 2.0, 0.1)["amount"]).is_equal(1)
    assert_int(DamageCalc.compute(6, rng, 0.0, 2.0, 0.5)["amount"]).is_equal(3)
```

- [ ] **Step 2: 运行确认失败** —— Run: `tools/run_tests.cmd`，Expected: 新增 3 个套件 FAIL。

- [ ] **Step 3: 实现**

`autoload/rng_svc.gd` 全量替换：

```gdscript
extends Node
## 种子化随机服务。所有逻辑随机必须经 stream() 派生，禁止全局 randi()/randf()。

var run_seed: int = 0

static func stable_hash(a: int, b: int) -> int:
    var h: int = 0xcbf29ce484222325
    for v: int in [a, b]:
        var x := v
        for _i in 8:
            h ^= x & 0xFF
            h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
            x >>= 8
    return h

func setup_run(seed: int) -> void:
    run_seed = seed

func stream(floor_idx: int, salt: String) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = stable_hash(stable_hash(run_seed, floor_idx), _salt_hash(salt))
    return rng

func _salt_hash(salt: String) -> int:
    var h: int = 0xcbf29ce484222325
    for c in salt.to_utf8_buffer():
        h ^= c
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h
```

`core/combat/time_const.gd`：

```gdscript
class_name TimeConst
const FPS := 60.0
static func ticks(seconds: float) -> int:
    return int(round(seconds * FPS))
```

`core/combat/elements.gd`：

```gdscript
class_name Elements
enum Id { NONE, FIRE, ICE, POISON, SHOCK }
const NAMES := {Id.NONE: "none", Id.FIRE: "fire", Id.ICE: "ice", Id.POISON: "poison", Id.SHOCK: "shock"}

static func from_name(s: String) -> int:
    for k: int in NAMES:
        if NAMES[k] == s:
            return k
    return Id.NONE
```

`core/combat/resonance.gd`：

```gdscript
class_name Resonance
## 共鸣表（GDD §7.3）：火+冰=淬爆 / 火+毒=燎原 / 冰+电=超导 / 毒+电=电解
enum R { NONE, SHATTER, BLAZE, SUPERCONDUCT, ELECTROLYSIS }
const TABLE := {"1_2": R.SHATTER, "1_3": R.BLAZE, "2_4": R.SUPERCONDUCT, "3_4": R.ELECTROLYSIS}

static func resolve(a: int, b: int) -> int:
    if a == b or a == Elements.Id.NONE or b == Elements.Id.NONE:
        return R.NONE
    return TABLE.get("%d_%d" % [mini(a, b), maxi(a, b)], R.NONE)
```

`core/combat/damage_calc.gd`：

```gdscript
class_name DamageCalc
## 固定伤害 + 暴击唯一随机（GDD §7.1）

static func compute(base: int, rng: RandomNumberGenerator, crit_chance: float, crit_mult: float = 2.0, global_mult: float = 1.0) -> Dictionary:
    var is_crit := rng.randf() < crit_chance
    var amount := int(floor(float(base) * global_mult * (crit_mult if is_crit else 1.0)))
    return {"amount": maxi(1, amount), "is_crit": is_crit}
```

- [ ] **Step 4: 运行测试** —— Run: `tools/run_tests.cmd`，Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add autoload/rng_svc.gd core/combat/ tests/unit/
git commit -m "feat(m0-t3): seeded rng streams, time consts, elements/resonance/damage pure logic"
```

---

### Task 4: SpatialHash 空间哈希

**Files:**
- Create: `core/combat/spatial_hash.gd`
- Create: `tests/unit/test_spatial_hash.gd`

**Interfaces:**
- Produces: `SpatialHash.new(cell_size := 32.0)`；`insert(id: int, pos: Vector2)`、`move(id, new_pos)`、`remove(id)`、`query(pos: Vector2, radius: float) -> Array[int]`（无序）、`clear()`。id 由 CombatSystem 分配（自增 int）。

- [ ] **Step 1: 写失败测试**

```gdscript
class_name TestSpatialHash
extends GdUnitTestSuite

func test_query_radius_and_borders() -> void:
    var h := SpatialHash.new(32.0)
    h.insert(1, Vector2(0, 0))
    h.insert(2, Vector2(30, 0))    # 同格
    h.insert(3, Vector2(34, 0))    # 邻格
    var r := h.query(Vector2(0, 0), 35.0)
    assert_int(r.size()).is_equal(3)

func test_move_updates_bucket() -> void:
    var h := SpatialHash.new(32.0)
    h.insert(1, Vector2(0, 0))
    h.move(1, Vector2(1000, 1000))
    assert_int(h.query(Vector2(0, 0), 10.0).size()).is_equal(0)
    assert_int(h.query(Vector2(1000, 1000), 10.0).size()).is_equal(1)

func test_remove_and_reinsert() -> void:
    var h := SpatialHash.new(32.0)
    h.insert(1, Vector2(5, 5))
    h.remove(1)
    assert_int(h.query(Vector2(5, 5), 10.0).size()).is_equal(0)
    h.insert(1, Vector2(5, 5))
    assert_int(h.query(Vector2(5, 5), 10.0).size()).is_equal(1)

func test_5000_entities_perf_sanity() -> void:
    var h := SpatialHash.new(32.0)
    var rng := RngSvc.stream(0, "perf")
    rng.seed = 1
    for i in 5000:
        h.insert(i, Vector2(rng.randf_range(0, 2000), rng.randf_range(0, 2000)))
    var t := Time.get_ticks_usec()
    for _i in 5000:
        h.query(Vector2(rng.randf_range(0, 2000), rng.randf_range(0, 2000)), 48.0)
    # 冒烟上限：宽松（无头 CI 波动），真实预算见 t13 门禁压测
    assert_int(Time.get_ticks_usec() - t).is_less(2_000_000)
```

- [ ] **Step 2: 运行确认失败** —— Expected: FAIL（类不存在）。

- [ ] **Step 3: 实现**

```gdscript
class_name SpatialHash
## 网格空间哈希（GDD §18.2），格子默认 32px。

var _cell: float
var _buckets: Dictionary = {}   # Vector2i -> Dictionary{ id: true }
var _pos: Dictionary = {}       # id -> Vector2

func _init(cell_size: float = 32.0) -> void:
    _cell = cell_size

func _key(p: Vector2) -> Vector2i:
    return Vector2i(int(floor(p.x / _cell)), int(floor(p.y / _cell)))

func insert(id: int, pos: Vector2) -> void:
    _pos[id] = pos
    _bucket(_key(pos))[id] = true

func move(id: int, new_pos: Vector2) -> void:
    if not _pos.has(id):
        insert(id, new_pos)
        return
    var old := _pos[id]
    var ok := _key(old)
    var nk := _key(new_pos)
    if ok != nk:
        _buckets[ok].erase(id)
        _bucket(nk)[id] = true
    _pos[id] = new_pos

func remove(id: int) -> void:
    if not _pos.has(id):
        return
    _buckets[_key(_pos[id])].erase(id)
    _pos.erase(id)

func query(pos: Vector2, radius: float) -> Array[int]:
    var out: Array[int] = []
    var min_c := _key(pos - Vector2(radius, radius))
    var max_c := _key(pos + Vector2(radius, radius))
    var r2 := radius * radius
    for cx in range(min_c.x, max_c.x + 1):
        for cy in range(min_c.y, max_c.y + 1):
            var b: Dictionary = _buckets.get(Vector2i(cx, cy), {})
            for id: int in b:
                var p: Vector2 = _pos[id]
                if pos.distance_squared_to(p) <= r2:
                    out.append(id)
    return out

func clear() -> void:
    _buckets.clear()
    _pos.clear()

func _bucket(k: Vector2i) -> Dictionary:
    if not _buckets.has(k):
        _buckets[k] = {}
    return _buckets[k]
```

- [ ] **Step 4: 运行测试** —— Expected: 全绿。
- [ ] **Step 5: Commit**

```bash
git add core/combat/spatial_hash.gd tests/unit/test_spatial_hash.gd
git commit -m "feat(m0-t4): grid spatial hash with move/query/remove"
```

---

### Task 5: Projectile 池与弹体

**Files:**
- Create: `core/combat/projectile.gd`、`core/combat/projectile_pool.gd`
- Create: `tests/unit/test_projectile_pool.gd`

**Interfaces:**
- Produces:
  - `Projectile.new()`（Node2D）字段：`vel: Vector2, damage: int, faction: int, element: int, pierce_left: int, bounce_left: int, life_ticks: int, radius: float`；`setup(cfg: Dictionary)`；`tick() -> bool`（false=到寿）。
  - `ProjectilePool.new(root: Node)`：`spawn(cfg) -> Projectile`、`despawn(p)`、`active: Array[Projectile]`、`active_count() -> int`；预分配 300、上限 500；despawn 后复用实例。
  - `Projectile.Faction {PLAYER=0, ENEMY=1}`；cfg 键：`pos, vel, damage, faction, element, pierce, bounce, life_seconds, radius`。

- [ ] **Step 1: 写失败测试**

```gdscript
class_name TestProjectilePool
extends GdUnitTestSuite

func test_spawn_reuses_instances() -> void:
    var root := auto_free(Node.new())
    var pool := ProjectilePool.new(root)
    var a := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.RIGHT * 100, "damage": 2, "faction": 0, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
    pool.despawn(a)
    var b := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.RIGHT * 100, "damage": 2, "faction": 0, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
    assert_that(a).is_same(b)

func test_lifetime_expiry() -> void:
    var root := auto_free(Node.new())
    var pool := ProjectilePool.new(root)
    var p := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": 0, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 0.05, "radius": 3.0})
    var alive := true
    for _i in 10:                # 0.05s = 3 ticks
        alive = p.tick()
    assert_bool(alive).is_false()

func test_cap_enforced() -> void:
    var root := auto_free(Node.new())
    var pool := ProjectilePool.new(root)
    var first := pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": 1, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
    for _i in 600:
        pool.spawn({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "damage": 1, "faction": 1, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 9.0, "radius": 3.0})
    assert_int(pool.active_count()).is_equal(500)
    # 公平性淘汰：最旧的非追踪弹被淘汰（GDD §7.5）——首个 spawn 的 first 应已不在池中
    assert_bool(pool.active.has(first)).is_false()
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

`core/combat/projectile.gd`：

```gdscript
class_name Projectile
extends Node2D
## 数据驱动的弹体；移动在此，命中判定在 CombatSystem。

enum Faction { PLAYER = 0, ENEMY = 1 }

var vel := Vector2.ZERO
var damage := 1
var faction := Faction.PLAYER
var element := Elements.Id.NONE
var pierce_left := 0
var bounce_left := 0
var life_ticks := 60
var radius := 3.0
var _ticks := 0

func setup(cfg: Dictionary) -> void:
    position = cfg.get("pos", Vector2.ZERO)
    vel = cfg.get("vel", Vector2.ZERO)
    damage = cfg.get("damage", 1)
    faction = cfg.get("faction", Faction.PLAYER)
    element = cfg.get("element", Elements.Id.NONE)
    pierce_left = cfg.get("pierce", 0)
    bounce_left = cfg.get("bounce", 0)
    life_ticks = TimeConst.ticks(cfg.get("life_seconds", 1.0))
    radius = cfg.get("radius", 3.0)
    _ticks = 0
    visible = true

func tick() -> bool:
    position += vel / TimeConst.FPS
    _ticks += 1
    return _ticks < life_ticks

func on_despawn() -> void:
    visible = false
```

`core/combat/projectile_pool.gd`：

```gdscript
class_name ProjectilePool
## 弹幕对象池（GDD §18.2）。预分配 300，上限 500；满时淘汰最旧非玩家弹，否则最旧弹。

const PREALLOC := 300
const MAX_PROJECTILES := 500

var active: Array[Projectile] = []
var _free: Array[Projectile] = []
var _root: Node

func _init(root: Node) -> void:
    _root = root
    for _i in PREALLOC:
        _free.append(_make())

func _make() -> Projectile:
    var p := Projectile.new()
    p.visible = false
    _root.add_child(p)
    return p

func spawn(cfg: Dictionary) -> Projectile:
    var p: Projectile
    if not _free.is_empty():
        p = _free.pop_back()
    elif active.size() < MAX_PROJECTILES:
        p = _make()
    else:
        p = _victim()
        active.erase(p)
    p.setup(cfg)
    active.append(p)
    return p

func despawn(p: Projectile) -> void:
    if not active.has(p):
        return
    active.erase(p)
    p.on_despawn()
    _free.append(p)

func active_count() -> int:
    return active.size()

func _victim() -> Projectile:
    for p in active:                      # 先找最旧敌方弹，否则最旧
        if p.faction == Projectile.Faction.ENEMY:
            return p
    return active[0]
```

- [ ] **Step 4: 运行测试** —— Expected: 全绿。**Step 5: Commit**

```bash
git add core/combat/projectile*.gd tests/unit/test_projectile_pool.gd
git commit -m "feat(m0-t5): pooled projectiles with lifetime and fairness culling"
```

---

### Task 6: CombatSystem（弹幕推进+命中结算+反弹/格挡 API）

**Files:**
- Create: `core/combat/combat_system.gd`
- Create: `tests/unit/test_combat_system.gd`

**Interfaces:**
- Consumes: `SpatialHash`(t4)、`ProjectilePool`(t5)、`DamageCalc`(t3)
- Produces:
  - `CombatSystem.new(root: Node, combat_rng: RandomNumberGenerator)`；加入场景树后 `_physics_process` 自行推进。
  - `register_body(node: Node2D, faction: int) -> void`、`unregister_body(node)`；实体契约：`take_hit(ctx: Dictionary)`、`combat_radius() -> float`。ctx = `{amount:int, is_crit:bool, element:int, from:Vector2}`。
  - `spawn_projectile(cfg)`（直接转发池，并登记）。
  - `projectiles_in_arc(origin: Vector2, facing: float, range_px: float, arc_deg: float, faction: int) -> Array[Projectile]`（近战用）。
  - `reflect(p: Projectile, new_damage: int)`（阵营翻转+反向+伤害改写）；`block(p)`（直接 despawn）。
  - `active_count() -> int`。

- [ ] **Step 1: 写失败测试**

```gdscript
class_name TestCombatSystem
extends GdUnitTestSuite

class DummyBody extends Node2D:
    var hits: Array = []
    func take_hit(ctx: Dictionary) -> void:
        hits.append(ctx)
    func combat_radius() -> float:
        return 6.0

func _make_cs() -> CombatSystem:
    var root := auto_free(Node2D.new())
    add_child_unchecked(root)
    var rng := RngSvc.stream(0, "combat")
    rng.seed = 11
    var cs := CombatSystem.new(root, rng)
    root.add_child(cs)
    return cs

func test_bullet_hits_registered_body() -> void:
    var cs := _make_cs()
    var body := auto_free(DummyBody.new())
    cs.get_parent().add_child(body)
    body.position = Vector2(200, 0)
    cs.register_body(body, Projectile.Faction.PLAYER)
    cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
    for _i in 30:
        await get_tree().physics_frame
    assert_int(body.hits.size()).is_equal(1)
    assert_int(body.hits[0]["amount"]).is_equal(4)

func test_same_faction_no_hit_and_pierce() -> void:
    var cs := _make_cs()
    var body := auto_free(DummyBody.new())
    cs.get_parent().add_child(body)
    body.position = Vector2(200, 0)
    cs.register_body(body, Projectile.Faction.ENEMY)
    cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.ENEMY, "element": 0, "pierce": 2, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
    for _i in 30:
        await get_tree().physics_frame
    assert_int(body.hits.size()).is_equal(0)

func test_crit_rolls_at_hit_time() -> void:
    var cs := _make_cs()
    cs.crit_chance = 1.0                      # 必暴
    var body := auto_free(DummyBody.new())
    cs.get_parent().add_child(body)
    body.position = Vector2(200, 0)
    cs.register_body(body, Projectile.Faction.PLAYER)
    cs.spawn_projectile({"pos": Vector2(100, 0), "vel": Vector2.RIGHT * 600, "damage": 4, "faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0, "life_seconds": 1.0, "radius": 3.0})
    for _i in 30:
        await get_tree().physics_frame
    assert_int(body.hits[0]["amount"]).is_equal(8)
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

```gdscript
class_name CombatSystem
extends Node
## 弹幕推进 + 命中结算（GDD §18.2：空间哈希 O(n·k)）。

const BODY_HIT_COOLDOWN_TICKS := 6   # 同一弹对同一体的重复命中抑制（穿透用）

var pool: ProjectilePool
var crit_chance := 0.05
var _hash := SpatialHash.new(32.0)
var _bodies: Dictionary = {}          # instance_id -> {node, faction, radius}
var _rng: RandomNumberGenerator
var _next_id := 1
var _proj_meta: Dictionary = {}       # projectile instance_id -> {hash_id, hit_cd: Dictionary}

func _init(root: Node, combat_rng: RandomNumberGenerator) -> void:
    pool = ProjectilePool.new(root)
    _rng = combat_rng

func register_body(node: Node2D, faction: int) -> void:
    _bodies[node.get_instance_id()] = {"node": node, "faction": faction, "radius": node.combat_radius(), "hash_id": _next_id}
    _hash.insert(_next_id, node.global_position)
    _next_id += 1

func unregister_body(node: Node2D) -> void:
    var id := node.get_instance_id()
    if _bodies.has(id):
        _hash.remove(_bodies[id]["hash_id"])
        _bodies.erase(id)

func spawn_projectile(cfg: Dictionary) -> void:
    var p := pool.spawn(cfg)
    _proj_meta[p.get_instance_id()] = {"hash_id": _next_id, "hit_cd": {}}
    _hash.insert(_next_id, p.position)
    _next_id += 1

func active_count() -> int:
    return pool.active_count()

func _physics_process(_delta: float) -> void:
    # 1) 实体位置更新
    for id: int in _bodies:
        var b: Dictionary = _bodies[id]
        _hash.move(b["hash_id"], b["node"].global_position)
    # 2) 弹体推进 + 命中
    for p in pool.active.duplicate():
        if not p.tick():
            _kill(p)
            continue
        var meta: Dictionary = _proj_meta[p.get_instance_id()]
        _hash.move(meta["hash_id"], p.position)
        var hits := _hash.query(p.position, p.radius + 12.0)
        for hid: int in hits:
            var b: Dictionary = _bodies_by_hash(hid)
            if b.is_empty() or b["faction"] == p.faction:
                continue
            var node: Node2D = b["node"]
            if node.global_position.distance_to(p.position) > p.radius + b["radius"]:
                continue
            var cd: Dictionary = meta["hit_cd"]
            if int(cd.get(node.get_instance_id(), -99)) + BODY_HIT_COOLDOWN_TICKS > Engine.get_physics_frames():
                continue
            cd[node.get_instance_id()] = Engine.get_physics_frames()
            var roll := DamageCalc.compute(p.damage, _rng, crit_chance)
            node.take_hit({"amount": roll["amount"], "is_crit": roll["is_crit"], "element": p.element, "from": p.position})
            if p.pierce_left > 0:
                p.pierce_left -= 1
            else:
                _kill(p)
                break

func _bodies_by_hash(hid: int) -> Dictionary:
    for id: int in _bodies:
        if _bodies[id]["hash_id"] == hid:
            return _bodies[id]
    return {}

func _kill(p: Projectile) -> void:
    _hash.remove(_proj_meta[p.get_instance_id()]["hash_id"])
    _proj_meta.erase(p.get_instance_id())
    pool.despawn(p)

# ---- 近战支持 ----
func projectiles_in_arc(origin: Vector2, facing: float, range_px: float, arc_deg: float, faction: int) -> Array[Projectile]:
    var out: Array[Projectile] = []
    for p in pool.active:
        if p.faction != faction:
            continue
        var to := p.position - origin
        if to.length() > range_px + p.radius:
            continue
        if absf(angle_difference(facing, to.angle())) <= deg_to_rad(arc_deg) / 2.0:
            out.append(p)
    return out

func reflect(p: Projectile, new_damage: int) -> void:
    p.faction = Projectile.Faction.PLAYER
    p.vel = -p.vel
    p.damage = new_damage
    p.life_ticks = TimeConst.ticks(1.0)
    p.modulate = Color(1.0, 1.0, 0.4)

func block(p: Projectile) -> void:
    _kill(p)
```

说明：`_bodies_by_hash` 的线性反查在 M0 体量（≤300 实体）可接受；若 t13 门禁压测超标，实现者补 `_hash_id -> body_id` 反查字典（属性能修复，接口不变）。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。**Step 5: Commit**

```bash
git add core/combat/combat_system.gd tests/unit/test_combat_system.gd
git commit -m "feat(m0-t6): combat system with hash-driven hits, pierce cooldown, melee arc/parry api"
```

---

### Task 7: Player 移动/翻滚/受击/护盾（含 MoveMath 纯函数）

**Files:**
- Create: `core/player/move_math.gd`、`core/player/player.gd`、`core/player/player.tscn`
- Create: `tests/unit/test_move_math.gd`、`tests/unit/test_player_state.gd`

**Interfaces:**
- Consumes: `TimeConst`(t3)、`EventBus`(t1)、`Fx`(t1 stub)、`CombatSystem`(t6：`take_hit` 契约)
- Produces:
  - `MoveMath.accelerate(vel, dir, max_speed, accel, friction) -> Vector2`（纯函数，内部按 1/60s 步长）
  - `Player`（CharacterBody2D）：常量区手感数值；`hp/shield/energy` 及上限；`take_hit(ctx)`（遵守 t6 契约）；`combat_radius() -> float`（6.0）；`combat_faction() -> int`；翻滚全程无敌；护盾先扣、3.0s 延迟后 1点/1.2s 回复；`is_invincible() -> bool`；`heal(n)/add_energy(n)`。
  - `player.tscn` 节点树：`Player(CharacterBody2D)[script] > CollisionShape2D(圆 r=6) + Sprite(暂用 ColorRect/多边形占位 12×14)`。

- [ ] **Step 1: 写失败测试**

`tests/unit/test_move_math.gd`：

```gdscript
class_name TestMoveMath
extends GdUnitTestSuite

func test_accel_toward_target_speed() -> void:
    var v := MoveMath.accelerate(Vector2.ZERO, Vector2.RIGHT, 80.0, 1400.0, 1800.0)
    assert_float(v.x).is_equal_approx(1400.0 / 60.0, 0.001)

func test_friction_stops_within_3_ticks() -> void:
    var v := Vector2.RIGHT * 80.0
    var ticks := 0
    while v.length() > 0.01 and ticks < 20:
        v = MoveMath.accelerate(v, Vector2.ZERO, 80.0, 1400.0, 1800.0)
        ticks += 1
    assert_int(ticks).is_less_equal(3)     # 80/1800*60 = 2.67 → ≤3 tick 停稳 (GDD §5.2)
```

`tests/unit/test_player_state.gd`（逻辑用 tick 注入，不起物理）：

```gdscript
class_name TestPlayerState
extends GdUnitTestSuite

func _player() -> Player:
    var p := auto_free(Player.new())
    p._test_init()
    return p

func test_shield_absorbs_first() -> void:
    var p := _player()
    p.hp = 8; p.shield = 4
    p.take_hit_ctx({"amount": 3}, 100)
    assert_int(p.shield).is_equal(1)
    assert_int(p.hp).is_equal(8)

func test_iframes_block_and_expire() -> void:
    var p := _player()
    p.take_hit_ctx({"amount": 1}, 100)
    assert_bool(p.is_invincible_at(110)).is_true()       # 0.8s=48 ticks
    assert_bool(p.is_invincible_at(100 + 48)).is_false()

func test_shield_regen_after_delay() -> void:
    var p := _player()
    p.hp = 8; p.shield = 0
    p.take_hit_ctx({"amount": 1}, 100)
    assert_int(p.shield_at(100 + 179)).is_equal(0)        # 3.0s 延迟内不回
    assert_int(p.shield_at(100 + 180)).is_equal(1)        # 延迟结束立即回第 1 点
    assert_int(p.shield_at(100 + 180 + 71)).is_equal(1)
    assert_int(p.shield_at(100 + 180 + 72)).is_equal(2)   # 之后每 1.2s 回 1

func test_roll_iframes_and_cooldown() -> void:
    var p := _player()
    p.start_roll(Vector2.RIGHT, 100)
    for f in range(100, 113):
        assert_bool(p.is_invincible_at(f)).is_true()      # 13 ticks 全程无敌
    assert_bool(p.roll_ready_at(100 + 13 + 42 - 1)).is_false()
    assert_bool(p.roll_ready_at(100 + 13 + 42)).is_true() # 0.7s CD 从结束起算
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

`core/player/move_math.gd`：

```gdscript
class_name MoveMath
const TICK := 1.0 / 60.0

static func accelerate(vel: Vector2, dir: Vector2, max_speed: float, accel: float, friction: float) -> Vector2:
    if dir == Vector2.ZERO:
        var sp := maxf(0.0, vel.length() - friction * TICK)
        return vel.normalized() * sp if sp > 0.001 else Vector2.ZERO
    return vel.move_toward(dir.normalized() * max_speed, accel * TICK)
```

`core/player/player.gd`（战斗相关骨架；渲染表现占位）：

```gdscript
class_name Player
extends CharacterBody2D
## 玩家。手感常量集中此处（GDD §5.2）；其余数值读 GameDB/HUD 层。

const MOVE_SPEED := 80.0
const ACCEL := 1400.0
const FRICTION := 1800.0
const ROLL_TICKS := 13
const ROLL_DIST := 56.0
const ROLL_CD_TICKS := 42          # 0.7s
const HURT_IFRAME_TICKS := 48      # 0.8s
const SHIELD_DELAY_TICKS := 180    # 3.0s
const SHIELD_INTERVAL_TICKS := 72  # 1.2s/点

var hp := 8
var hp_max := 8
var shield := 4
var shield_max := 4
var energy := 100
var energy_max := 100
var move_speed := MOVE_SPEED
var facing := Vector2.RIGHT
var _roll_left := 0
var _roll_vel := Vector2.ZERO
var _roll_end_frame := -999
var _roll_cd_until := -999
var _iframe_until := -999
var _last_damaged_frame := -999
var _shield_next_at := -999

func _test_init() -> void:
    # 纯逻辑测试入口：不进场景树也能测状态机
    pass

func _physics_process(_delta: float) -> void:
    var f := Engine.get_physics_frames()
    var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    if dir != Vector2.ZERO:
        facing = dir.normalized()
    if _roll_left > 0:
        _roll_left -= 1
        velocity = _roll_vel
    else:
        if Input.is_action_just_pressed("roll") and roll_ready_at(f):
            start_roll(dir if dir != Vector2.ZERO else facing, f)
        velocity = MoveMath.accelerate(velocity, dir, move_speed, ACCEL, FRICTION)
    move_and_slide()
    _shield_tick(f)

func start_roll(dir: Vector2, frame: int) -> void:
    var d := dir.normalized()
    _roll_vel = d * (ROLL_DIST / (float(ROLL_TICKS) / TimeConst.FPS))
    _roll_left = ROLL_TICKS
    _roll_end_frame = frame + ROLL_TICKS
    _roll_cd_until = _roll_end_frame + ROLL_CD_TICKS
    Fx.on_roll(self)

func roll_ready_at(frame: int) -> bool:
    return frame >= _roll_cd_until

func is_invincible_at(frame: int) -> bool:
    return frame < _iframe_until or frame < _roll_end_frame

func is_invincible() -> bool:
    return is_invincible_at(Engine.get_physics_frames())

func take_hit(ctx: Dictionary) -> void:
    take_hit_ctx(ctx, Engine.get_physics_frames())

func take_hit_ctx(ctx: Dictionary, frame: int) -> void:
    if is_invincible_at(frame):
        return
    _iframe_until = frame + HURT_IFRAME_TICKS
    _last_damaged_frame = frame
    var dmg: int = ctx["amount"]
    var to_hp := maxi(0, dmg - shield)
    shield = maxi(0, shield - dmg)
    if to_hp > 0:
        hp = maxi(0, hp - to_hp)
    _shield_next_at = frame + SHIELD_DELAY_TICKS
    EventBus.player_damaged.emit(dmg, hp <= 0)
    Fx.on_player_hurt(self, dmg)

func _shield_tick(frame: int) -> void:
    if shield >= shield_max or frame < _shield_next_at:
        return
    shield += 1
    _shield_next_at = frame + SHIELD_INTERVAL_TICKS

func shield_at(frame: int) -> int:
    # 纯查询：给定未来帧的护盾值（测试与 UI 预估用）
    if shield >= shield_max or frame < _shield_next_at:
        return shield
    var gained := int(floor(float(frame - _shield_next_at) / SHIELD_INTERVAL_TICKS)) + 1
    return mini(shield_max, shield + gained)

func heal(n: int) -> void:
    hp = mini(hp_max, hp + n)

func add_energy(n: int) -> void:
    energy = mini(energy_max, energy + n)

func combat_radius() -> float:
    return 6.0

func combat_faction() -> int:
    return Projectile.Faction.PLAYER
```

`player.tscn`：CharacterBody2D + CollisionShape2D(CircleShape2D r=6) + `Polygon2D`（12×14 矩形占位，色 #e8d5b0）。motion_mode = floating。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。
- [ ] **Step 5: 手动验证**：`godot --path .`（临时主场景放一个带 Player 的空房间）：WASD 移动脉冲感（≤3 帧停稳）、Shift 翻滚距离约 3.5 瓦片、视觉无抖动。记录结论到任务自检报告。
- [ ] **Step 6: Commit**

```bash
git add core/player/ tests/unit/test_move_math.gd tests/unit/test_player_state.gd
git commit -m "feat(m0-t7): player movement/roll/shield with pure move math"
```

---

### Task 8: WeaponRig 射击（双武器位/蓝耗/散布/多弹）

**Files:**
- Create: `core/player/weapon_rig.gd`
- Modify: `core/player/player.tscn`（挂 WeaponRig 子节点 + 鼠标瞄准）
- Create: `tests/unit/test_weapon_rig.gd`

**Interfaces:**
- Consumes: `GameDB`(t2)、`Player`(t7)、`CombatSystem.spawn_projectile`(t6)、`RngSvc.stream(idx,"combat")`(t3)
- Produces: `WeaponRig`（Node，父级须为 Player）：`equip(weapon_id: String) -> void`（装入当前槽并切槽）、`try_fire(aim: Vector2, frame: int) -> bool`、`switch_slot(frame: int) -> void`（0.25s=15 ticks 锁定）、`current() -> Dictionary`。房间侧负责把 `combat` 与 `combat_rng` 注入：`rig.combat = cs; rig.combat_rng = rng`。

- [ ] **Step 1: 写失败测试**

```gdscript
class_name TestWeaponRig
extends GdUnitTestSuite

class RigProbe extends WeaponRig:
    var spawned: Array = []
    func _spawn(cfg: Dictionary) -> void:
        spawned.append(cfg)

func _rig() -> RigProbe:
    var p := auto_free(Player.new())
    p._test_init()
    var r := RigProbe.new()
    p.add_child(r)
    r._test_init()
    return r

func test_rate_limiting() -> void:
    var r := _rig()
    r.equip("laohuoji")                  # 4.0/s → 15 ticks
    assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_true()
    assert_bool(r.try_fire(Vector2.RIGHT, 14)).is_false()
    assert_bool(r.try_fire(Vector2.RIGHT, 15)).is_true()

func test_energy_block_when_empty() -> void:
    GameDB.weapons["testgun3"] = {"id":"testgun3","name":"t3","category":"pistol","rarity":"common","damage":1,"rate":2.0,"energy_cost":5,"bullet_speed":300,"spread_deg":0.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0}
    var r := _rig()
    r.equip("testgun3")                  # 蓝耗 5（M0 六把初始武器全 0 耗，注入一把有耗的验证空蓝规则）
    r.get_parent().energy = 3
    assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_false()

func test_melee_weapon_not_fired_by_rig() -> void:
    var r := _rig()
    r.equip("tiejian")
    assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_false()

func test_multishot_fan_count() -> void:
    GameDB.weapons["testgun"] = {"id":"testgun","name":"t","category":"pistol","rarity":"common","damage":1,"rate":10.0,"energy_cost":0,"bullet_speed":300,"spread_deg":30.0,"projectiles":3,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0}
    var r := _rig()
    r.equip("testgun")
    r.combat_rng = RngSvc.stream(0, "combat")
    r.try_fire(Vector2.RIGHT, 0)
    assert_int(r.spawned.size()).is_equal(3)

func test_switch_lock() -> void:
    var r := _rig()
    r.equip("laohuoji")                  # equip 规则：填第一个空槽；两槽满替换当前槽
    r.equip("maodingqiang")              # -> 槽 1
    r.switch_slot(0)                     # -> 槽 1（铆钉枪），锁定至第 15 帧
    assert_bool(r.try_fire(Vector2.RIGHT, 14)).is_false()
    assert_bool(r.try_fire(Vector2.RIGHT, 15)).is_true()
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

```gdscript
class_name WeaponRig
extends Node
## 双武器位射击（GDD §8.1）。数值全部来自 GameDB 行。

const SWITCH_LOCK_TICKS := 15      # 0.25s

var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var slots: Array[Dictionary] = []
var slot := 0
var _next_fire_frame := 0
var _switch_until := 0
var _muzzle := Vector2(8, 0)       # 相对玩家，朝向时旋转

func _test_init() -> void:
    slots = [{}, {}]

func equip(weapon_id: String) -> void:
    var w := GameDB.get_weapon(weapon_id)
    if w.is_empty():
        push_error("WeaponRig: unknown weapon %s" % weapon_id)
        return
    if slots.size() < 2:
        slots.resize(2)
    slots[slot] = w

func current() -> Dictionary:
    return slots[slot] if slot < slots.size() else {}

func switch_slot(frame: int) -> void:
    if slots.size() < 2:
        return
    slot = (slot + 1) % 2
    _switch_until = frame + SWITCH_LOCK_TICKS
    _next_fire_frame = frame

func try_fire(aim: Vector2, frame: int) -> bool:
    var w := current()
    if w.is_empty() or w["is_melee"]:
        return false
    if frame < _next_fire_frame or frame < _switch_until:
        return false
    var player := get_parent() as Player
    var cost := int(w["energy_cost"])
    if cost > player.energy:
        return false                     # 空蓝禁远程（GDD §7.2）
    player.energy -= cost
    _next_fire_frame = frame + maxi(1, int(round(TimeConst.FPS / float(w["rate"]))))
    var n := int(w["projectiles"])
    var spread := float(w["spread_deg"])
    var origin: Vector2 = player.global_position + (_muzzle.rotated(aim.angle()))
    for i in n:
        var ang := aim.angle() + deg_to_rad(_fan_offset(n, i, spread)) + deg_to_rad(_jitter(spread))
        _spawn({
            "pos": origin, "vel": Vector2.RIGHT.rotated(ang) * float(w["bullet_speed"]),
            "damage": int(w["damage"]), "faction": Projectile.Faction.PLAYER,
            "element": Elements.from_name(w["element"]), "pierce": int(w["pierce"]),
            "bounce": int(w["bounce"]), "life_seconds": 1.2, "radius": 3.0,
        })
    return true

func _spawn(cfg: Dictionary) -> void:
    combat.spawn_projectile(cfg)         # 测试以子类覆写 _spawn 捕获参数

func _fan_offset(n: int, i: int, spread_deg: float) -> float:
    if n <= 1:
        return 0.0
    var step := spread_deg / float(n - 1)
    return -spread_deg / 2.0 + step * i

func _jitter(spread_deg: float) -> float:
    if combat_rng == null or spread_deg <= 0.0:
        return 0.0
    return combat_rng.randf_range(-spread_deg / 4.0, spread_deg / 4.0)
```

**equip 语义**：填第一个空槽；两槽满则替换当前槽并保留另一槽。**测试路径**：`RigProbe` 覆写 `_spawn` 捕获生成参数，不依赖 CombatSystem。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。
- [ ] **Step 5: 手动验证**：靶场场景中 老伙计 射速手感、蓝耗为 0、切武器 0.25s 锁定可感知。
- [ ] **Step 6: Commit**

```bash
git add core/player/weapon_rig.gd core/player/player.tscn tests/unit/test_weapon_rig.gd
git commit -m "feat(m0-t8): dual-slot weapon rig with rate/energy/spread/multishot"
```

---

### Task 9: 近战挥击与弹幕反弹窗口

**Files:**
- Create: `core/player/melee.gd`
- Modify: `core/player/player.tscn`（挂 Melee 子节点）
- Create: `tests/unit/test_melee_parry.gd`

**Interfaces:**
- Consumes: `WeaponRig.current()`(t8)、`CombatSystem.projectiles_in_arc/reflect/block`(t6)、`Player`(t7)
- Produces: `Melee`（Node，父级 Player）：`try_attack(frame: int) -> bool`；挥击 9 ticks（0.15s）；反弹窗口 tick∈[3,10]；窗口内敌方弹反弹（伤害=本次近战伤害），窗口外挥击弧内敌方弹被格挡消失；伤害在 tick==3 时对弧内敌方实体结算一次（走 `take_hit`，暴击由 CombatSystem 的 DamageCalc 结算路径——近战直接本地 roll：`DamageCalc.compute(dmg, combat_rng, 0.05)`）。

- [ ] **Step 1: 写失败测试**

```gdscript
class_name TestMeleeParry
extends GdUnitTestSuite

class CsProbe:
    var reflected: Array = []
    var blocked: Array = []
    func reflect(p, dmg: int) -> void:
        reflected.append([p, dmg])
    func block(p) -> void:
        blocked.append(p)

func test_parry_window_bounds() -> void:
    var p := auto_free(Player.new())
    p._test_init()
    var m := auto_free(Melee.new())
    p.add_child(m)
    m._test_init()
    m.rig = WeaponRig.new()
    m.rig.slots = [GameDB.get_weapon("tiejian"), {}]   # 近战 2.2/s → 27 ticks
    assert_bool(m.try_attack(0)).is_true()
    assert_bool(m.is_parry_tick(2)).is_false()
    assert_bool(m.is_parry_tick(3)).is_true()
    assert_bool(m.is_parry_tick(10)).is_true()
    assert_bool(m.is_parry_tick(11)).is_false()

func test_reflect_sets_melee_damage() -> void:
    # 直接测 CombatSystem.reflect 语义（与 m0-t6 接口一致性）
    var proj := auto_free(Projectile.new())
    proj.faction = Projectile.Faction.ENEMY
    proj.vel = Vector2.RIGHT * 100
    var cs := auto_free(CombatSystem.new(Node.new(), RngSvc.stream(0, "t")))
    cs.reflect(proj, 6)
    assert_int(proj.faction).is_equal(Projectile.Faction.PLAYER)
    assert_int(proj.damage).is_equal(6)
    assert_float(proj.vel.x).is_equal_approx(-100.0, 0.001)
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

```gdscript
class_name Melee
extends Node
## 近战挥击 + 反弹窗口（GDD §7.4）。挥击 9 ticks；窗口 [3,10]。

const SWING_TICKS := 9
const PARRY_FROM := 3
const PARRY_TO := 10

var rig: WeaponRig
var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var _swing_left := 0
var _swing_tick := -1
var _hit_done := false
var _next_frame := 0

func _test_init() -> void:
    pass

func try_attack(frame: int) -> bool:
    var w := rig.current()
    if w.is_empty() or not w["is_melee"]:
        return false
    if _swing_left > 0 or frame < _next_frame:
        return false
    _next_frame = frame + maxi(1, int(round(TimeConst.FPS / float(w["rate"]))))
    _swing_left = SWING_TICKS
    _swing_tick = 0
    _hit_done = false
    return true

func is_parry_tick(tick: int) -> bool:
    return tick >= PARRY_FROM and tick <= PARRY_TO

func _physics_process(_delta: float) -> void:
    if _swing_left <= 0:
        return
    _swing_tick += 1
    _swing_left -= 1
    var player := get_parent() as Player
    var w := rig.current()
    var range_px := float(w.get("range", 40))
    var arc := float(w.get("arc_deg", 90.0))
    if is_parry_tick(_swing_tick):
        for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
            combat.reflect(p, int(w["damage"]))
    else:
        for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
            combat.block(p)
    if not _hit_done:
        _hit_done = true
        var roll := DamageCalc.compute(int(w["damage"]), combat_rng, 0.05)
        for body in combat.bodies_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
            body.take_hit({"amount": roll["amount"], "is_crit": roll["is_crit"], "element": Elements.from_name(w["element"]), "from": player.global_position})
```

同时在 `combat_system.gd` 补一个与 `projectiles_in_arc` 同构的 `bodies_in_arc(origin, facing, range_px, arc_deg, faction) -> Array`（遍历 `_bodies` 做距离+角度过滤）——在此任务补齐并加一个单测（复用 t6 的 DummyBody，测角度扇形过滤）。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。
- [ ] **Step 5: 手动验证**：靶场站桩让弩兵朝你射弹，铁剑挥击反弹（弹幕变色反飞）可稳定复现；窗口外挥击弹幕消失（格挡）。
- [ ] **Step 6: Commit**

```bash
git add core/player/melee.gd core/combat/combat_system.gd core/player/player.tscn tests/unit/test_melee_parry.gd
git commit -m "feat(m0-t9): melee swing with 0.12s parry window and projectile reflect"
```

---

### Task 10: EnemyBase 状态机 + 4 原型（数据驱动）

**Files:**
- Create: `data/enemies.json`、`core/enemies/enemy_base.gd`、`core/enemies/archetypes/charger.gd`、`shooter.gd`、`orbiter.gd`、`suicide.gd`
- Modify: `autoload/game_db.gd`（加载 enemies.json，schema `ENEMY_SCHEMA`）
- Create: `tests/unit/test_enemy_ai.gd`

**Interfaces:**
- Consumes: `CombatSystem.spawn_projectile`(t6)、`StatusComponent`(t11——本任务先留 `status: StatusComponent` 可空槽位，t11 接入)、`Fx.flash`(t12 空壳)
- Produces:
  - `EnemyBase`（CharacterBody2D）：`setup(row: Dictionary)`；状态 `IDLE→ALERT(24 ticks)→ENGAGE`；`take_hit(ctx)`；`die()`（`EventBus.enemy_killed` + unregister + queue_free）；`combat_radius() -> float`（读行 `radius`，默认 6）。
  - 原型脚本只覆写 `engage_tick(frame) -> void` 与 `fire(frame) -> void`。
  - `GameDB.enemies: Dictionary`。

- [ ] **Step 1: 写失败测试**（AI 用注入帧驱动，不依赖物理；抽 `EnemyBrain` 纯逻辑类挂 EnemyBase）

```gdscript
class_name TestEnemyAI
extends GdUnitTestSuite

func test_state_transitions() -> void:
    var e := auto_free(EnemyBase.new())
    e._test_init({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108})
    e.on_player_seen(0)
    assert_int(e.state).is_equal(EnemyBase.State.ALERT)
    e.brain_tick(23)
    assert_int(e.state).is_equal(EnemyBase.State.ALERT)     # 0.4s=24 ticks 前摇
    e.brain_tick(24)
    assert_int(e.state).is_equal(EnemyBase.State.ENGAGE)

func test_shooter_cadence() -> void:
    var e := auto_free(EnemyBase.new())
    e._test_init({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108})
    e.on_player_seen(0)
    for f in range(1, 25): e.brain_tick(f)
    var shots := 0
    for f in range(25, 300):
        e.brain_tick(f)
        if e.fired_this_tick: shots += 1
    # 0.4s 警觉后首射，随后每 1.8s：约 (300-24)/108 + 1 ≈ 3
    assert_int(shots).is_between(2, 4)

func test_suicide_fuse_and_explosion_params() -> void:
    var e := auto_free(EnemyBase.new())
    e._test_init({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8})
    e.on_player_seen(0)
    for f in range(1, 25): e.brain_tick(f)
    e.brain_tick(24 + 30)     # ENGAGE 后贴身引信 30 ticks
    assert_bool(e.exploded).is_true()

func test_charger_dash_distance() -> void:
    var e := auto_free(EnemyBase.new())
    e._test_init({"id": "vine_charger", "archetype": "charger", "hp": 18, "contact_dmg": 4, "walk_speed": 45, "dash_speed": 285, "windup_ticks": 30, "dash_ticks": 27, "dash_cooldown_ticks": 90})
    e.on_player_seen(0)
    for f in range(1, 25):
        e.brain_tick(f)                   # 第 24 帧进入 ENGAGE
    for f in range(25, 55):
        e.brain_tick(f)                   # 前摇 30 ticks（蓄力原地）
    var traveled := 0.0
    var last := e.brain_pos
    for f in range(55, 55 + 27):          # 冲刺 27 ticks = 27×285/60 ≈ 128px（附录 B.2 冲 8 瓦片）
        e.brain_tick(f)
        traveled += last.distance_to(e.brain_pos)
        last = e.brain_pos
    assert_float(traveled).is_equal_approx(128.0, 8.0)
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

`data/enemies.json`（附录 B 摘录 M0 四种）：

```json
{
  "kuli_bug":     {"id":"kuli_bug","name":"苦力虫","archetype":"suicide","hp":12,"contact_dmg":0,"speed":95,"radius":5.0,"windup_ticks":0,"cd_ticks":0,"fuse_ticks":30,"aoe_radius":40,"aoe_dmg":8,"bullet_dmg":0,"bullet_speed":0,"walk_speed":95,"dash_speed":0,"dash_ticks":0,"dash_cooldown_ticks":0},
  "cave_bat":     {"id":"cave_bat","name":"穴蝠","archetype":"orbiter","hp":10,"contact_dmg":3,"speed":70,"radius":5.0,"orbit_radius":120,"windup_ticks":0,"cd_ticks":0,"bullet_dmg":0,"bullet_speed":0},
  "crossbowman":  {"id":"crossbowman","name":"弩兵","archetype":"shooter","hp":16,"contact_dmg":3,"speed":60,"radius":6.0,"windup_ticks":30,"cd_ticks":108,"bullet_dmg":3,"bullet_speed":110,"bullet_life_seconds":2.5},
  "vine_charger": {"id":"vine_charger","name":"藤蔓冲锋者","archetype":"charger","hp":18,"contact_dmg":4,"radius":6.0,"walk_speed":45,"dash_speed":285,"dash_ticks":27,"windup_ticks":30,"dash_cooldown_ticks":90}
}
```

`core/enemies/enemy_base.gd`：

```gdscript
class_name EnemyBase
extends CharacterBody2D
## 敌人状态机（GDD §12.2）：IDLE→ALERT(24t)→ENGAGE；AI 决策在 EnemyBrain（可注入帧测试）。

enum State { IDLE, ALERT, ENGAGE, DEAD }
const ALERT_TICKS := 24     # 0.4s

var row: Dictionary
var hp := 10
var state := State.IDLE
var fired_this_tick := false
var exploded := false
var brain_pos := Vector2.ZERO
var combat: CombatSystem = null    # 房间注入
var status: Node = null            # StatusComponent，m0-t11 注入
var _seen_frame := -1

func _test_init(r: Dictionary) -> void:
    row = r
    hp = int(r.get("hp", 10))
    brain_pos = Vector2.ZERO

func setup(r: Dictionary) -> void:
    _test_init(r)
    brain_pos = global_position

func on_player_seen(frame: int) -> void:
    if state == State.IDLE:
        state = State.ALERT
        _seen_frame = frame

func brain_tick(frame: int) -> void:
    fired_this_tick = false
    match state:
        State.ALERT:
            if frame - _seen_frame >= ALERT_TICKS:
                state = State.ENGAGE
        State.ENGAGE:
            _engage(frame)
        _:
            pass

func _engage(_frame: int) -> void:
    pass                                  # 原型覆写

func fire_bullet(target: Vector2, frame: int) -> void:
    fired_this_tick = true
    if combat == null:
        return
    var dir := (target - brain_pos).normalized()
    combat.spawn_projectile({
        "pos": brain_pos, "vel": dir * float(row.get("bullet_speed", 110)),
        "damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
        "element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
        "life_seconds": float(row.get("bullet_life_seconds", 2.5)), "radius": 3.0,
    })

func take_hit(ctx: Dictionary) -> void:
    if state == State.DEAD:
        return
    hp -= int(ctx["amount"])
    Fx.on_enemy_hit(self, ctx)
    if status != null:
        status.apply_hit(int(ctx.get("element", 0)), int(ctx["amount"]), Engine.get_physics_frames())
    if hp <= 0:
        die()

func die() -> void:
    state = State.DEAD
    EventBus.enemy_killed.emit(String(row.get("id", "")))
    queue_free()

func combat_radius() -> float:
    return float(row.get("radius", 6.0))

func combat_faction() -> int:
    return Projectile.Faction.ENEMY
```

（`combat: CombatSystem` 与玩家同理由房间注入。物理表现层：`_physics_process` 里按 brain 输出的速度调 `move_and_slide()`、检测玩家进入视距调 `on_player_seen(Engine.get_physics_frames())`——视距 240px。）

原型四脚本（`archetypes/*.gd`，extends EnemyBase 覆写 `_engage`）。charger 参考实现：

```gdscript
extends EnemyBase
## 藤蔓冲锋者：ENGAGE 后 windup 30t 蓄力（原地红闪）→ dash 27t 直冲锁定方向 → 冷却 90t。
var _phase := "windup"
var _phase_left := 0
var _dash_dir := Vector2.ZERO

func _engage(frame: int) -> void:
    match _phase:
        "idle":
            _phase = "windup"; _phase_left = int(row["windup_ticks"])
            _dash_dir = (player_ref.brain_pos - brain_pos).normalized()
            Fx.on_enemy_hit(self, {"telegraph": true})
        "windup":
            _phase_left -= 1
            if _phase_left <= 0:
                _phase = "dash"; _phase_left = int(row["dash_ticks"])
        "dash":
            brain_pos += _dash_dir * (float(row["dash_speed"]) / TimeConst.FPS)
            _phase_left -= 1
            if _phase_left <= 0:
                _phase = "cool"; _phase_left = int(row["dash_cooldown_ticks"])
        "cool":
            _phase_left -= 1
            if _phase_left <= 0:
                _phase = "idle"
```

（`player_ref` 由房间注入，测试中可直接赋值一个带 `brain_pos` 的替身。）其余三原型同构实现，参数来自行数据、行为按 t10 接口描述：shooter（保持 140~200px 距离游走，每 `cd_ticks` 触发 `windup_ticks` 预警后 `fire_bullet(player_pos, f)`）；orbiter（绕玩家 `orbit_radius` 公转，角速度使线速度 = `speed`，每 180t 随机俯冲 60t）；suicide（追击，距离 <14px 启动 `fuse_ticks` 倒计时→`exploded=true`，对 `aoe_radius` 内玩家结算 `aoe_dmg` 并自毁）。

GameDB 增加载入：`enemies` 字典 + `ENEMY_SCHEMA`（required: id/name/archetype/hp/radius；其余 optional 默认 0）——复用 t2 的 `validate_row`。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。
- [ ] **Step 5: 手动验证**：测试房放 4 种怪各 1：弩兵弹速可躲（110px/s）、藤蔓冲锋有 0.5s 红闪预警、苦力虫贴身 0.5s 引信有膨胀动画。
- [ ] **Step 6: Commit**

```bash
git add data/enemies.json core/enemies/ autoload/game_db.gd tests/unit/test_enemy_ai.gd
git commit -m "feat(m0-t10): data-driven enemy base + charger/shooter/orbiter/suicide archetypes"
```

---

### Task 11: StatusComponent 元素状态与共鸣结算

**Files:**
- Create: `core/combat/status_component.gd`
- Modify: `core/enemies/enemy_base.gd`（挂 StatusComponent；无元素武器场景为空操作）
- Create: `tests/unit/test_status.gd`

**Interfaces:**
- Consumes: `Elements`/`Resonance`/`TimeConst`(t3)、`EventBus`(t1)
- Produces（纯逻辑，时间全用注入帧）:
  - `StatusComponent.setup(stacks_to_trigger := 2, is_boss := false)`
  - `apply_hit(element: int, damage: int, now: int) -> void`——积累到阈值触发单元素状态并尝试共鸣。
  - `tick(now: int) -> int`——返回本帧 DoT 伤害（燃烧 3s 内每 0.5s 1 点；中毒 5s 内每 1s 1 点；由宿主自行扣血）。
  - `active: Dictionary`、`resonance_event: Dictionary`（触发后的待处理事件：`{reaction, last_damage}`，读后清空——房间层消费并执行 AoE/Cloud/超导/电解）。
  - `apply_superconduct(bonus: float, duration_ticks: int)`、`damage_multiplier() -> float`（超导 +0.4，Boss +0.2，GDD §7.3）。
  - 同一目标共鸣 ICD 2s（120 ticks，按元素对独立计）。

- [ ] **Step 1: 写失败测试**

```gdscript
class_name TestStatus
extends GdUnitTestSuite

func _sc(stacks := 2) -> StatusComponent:
    var s := auto_free(StatusComponent.new())
    s.setup(stacks)
    return s

func test_fire_triggers_burning_after_2_hits() -> void:
    var s := _sc()
    s.apply_hit(Elements.Id.FIRE, 5, 0)
    assert_dict(s.active).is_empty()
    s.apply_hit(Elements.Id.FIRE, 5, 60)
    assert_bool(s.active.has(Elements.Id.FIRE)).is_true()

func test_burn_dot_ticks() -> void:
    var s := _sc()
    s.apply_hit(Elements.Id.FIRE, 5, 0)
    s.apply_hit(Elements.Id.FIRE, 5, 10)      # 触发燃烧
    var total := 0
    for f in range(11, 11 + 180):
        total += s.tick(f)
    assert_int(total).is_equal(6)             # 3s，每 0.5s 1 点 = 6

func test_shatter_resonance_once_with_icd() -> void:
    var s := _sc()
    s.apply_hit(Elements.Id.FIRE, 8, 0)
    s.apply_hit(Elements.Id.ICE, 8, 10)       # 火+冰 → 淬爆
    assert_int(s.resonance_event.get("reaction", -1)).is_equal(Resonance.R.SHATTER)
    s.resonance_event = {}
    s.apply_hit(Elements.Id.FIRE, 8, 20)      # ICD 内（<120 ticks）不再共鸣
    s.apply_hit(Elements.Id.ICE, 8, 30)
    assert_dict(s.resonance_event).is_empty()
    s.apply_hit(Elements.Id.POISON, 8, 200)   # >2s，新元素对 火+毒 可共鸣（燎原）
    assert_int(s.resonance_event.get("reaction", -1)).is_equal(Resonance.R.BLAZE)
    s.resonance_event = {}
    s.apply_hit(Elements.Id.SHOCK, 8, 210)    # 火/毒已被燎原清除，电单独成状态
    assert_dict(s.resonance_event).is_empty()

func test_boss_threshold_four() -> void:
    var s := _sc(4)
    for f in range(0, 3):
        s.apply_hit(Elements.Id.POISON, 1, f * 10)
    assert_dict(s.active).is_empty()
    s.apply_hit(Elements.Id.POISON, 1, 40)
    assert_bool(s.active.has(Elements.Id.POISON)).is_true()
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**

```gdscript
class_name StatusComponent
## 元素状态与共鸣（GDD §7.3）。纯逻辑：时间全部用注入的物理帧号。

var stacks_to_trigger := 2
var is_boss := false
var active: Dictionary = {}            # element -> expire_frame
var resonance_event: Dictionary = {}   # {reaction: int, last_damage: int}
var _stacks: Dictionary = {}
var _icd_until: Dictionary = {}        # "a_b" -> frame
var _dot_next: Dictionary = {}         # element -> next dot frame
var last_damage := 0
var _superconduct_until := -1
var _superconduct_bonus := 0.0

func setup(stacks := 2, boss := false) -> void:
    stacks_to_trigger = stacks
    is_boss = boss

func apply_hit(element: int, damage: int, now: int) -> void:
    if element == Elements.Id.NONE:
        return
    last_damage = damage
    _stacks[element] = int(_stacks.get(element, 0)) + 1
    if _stacks[element] >= stacks_to_trigger:
        _stacks[element] = 0
        _trigger(element, now)

func _trigger(element: int, now: int) -> void:
    match element:
        Elements.Id.FIRE: active[element] = now + TimeConst.ticks(3.0); _dot_next[element] = now + TimeConst.ticks(0.5)
        Elements.Id.ICE:  active[element] = now + TimeConst.ticks(2.0)
        Elements.Id.POISON: active[element] = now + TimeConst.ticks(5.0); _dot_next[element] = now + TimeConst.ticks(1.0)
        Elements.Id.SHOCK: active[element] = now + TimeConst.ticks(2.0)
    EventBus.status_applied.emit(get_parent(), element)
    _try_resonance(element, now)

func _try_resonance(new_element: int, now: int) -> void:
    for other: int in active.keys():
        if other == new_element:
            continue
        var key := "%d_%d" % [mini(other, new_element), maxi(other, new_element)]
        if now < int(_icd_until.get(key, 0)):
            continue
        var reaction := Resonance.resolve(other, new_element)
        if reaction == Resonance.R.NONE:
            continue
        _icd_until[key] = now + TimeConst.ticks(2.0)
        active.erase(other)
        active.erase(new_element)
        resonance_event = {"reaction": reaction, "last_damage": last_damage}
        return

func tick(now: int) -> int:
    var dmg := 0
    for element: int in active.keys():
        # 先结算 DoT 再判过期：3s 燃烧的第 6 跳（0.5,1.0,...,3.0s）必须落地
        if element == Elements.Id.FIRE or element == Elements.Id.POISON:
            if now >= int(_dot_next.get(element, 0)):
                dmg += 1
                var interval := TimeConst.ticks(0.5) if element == Elements.Id.FIRE else TimeConst.ticks(1.0)
                _dot_next[element] = now + interval
        if now >= int(active[element]):
            active.erase(element)
    if _superconduct_until > 0 and now >= _superconduct_until:
        _superconduct_until = -1
    return dmg

func apply_superconduct(bonus: float, duration_ticks: int, now: int) -> void:
    _superconduct_bonus = bonus
    _superconduct_until = now + duration_ticks

func damage_multiplier() -> float:
    return 1.0 + (_superconduct_bonus if _superconduct_until > 0 else 0.0)
```

EnemyBase 接入：`take_hit` 中 `if status: status.apply_hit(...)` 已在 t10 预留；`_physics_process` 中 `var dot := status.tick(frame); if dot > 0: hp -= dot`（DoT 死亡同样走 die()）；房间层消费 `resonance_event`（t12 执行 AoE；超导调 `apply_superconduct(0.2 if is_boss else 0.4, TimeConst.ticks(4.0), now)`）。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。**Step 5: Commit**

```bash
git add core/combat/status_component.gd core/enemies/enemy_base.gd tests/unit/test_status.gd
git commit -m "feat(m0-t11): element status stacking with resonance and 2s icd"
```

---

### Task 12: 战斗房（锁门/波次/奖励）+ Juice v1 + 靶场房 + Debug HUD + 遥测

> 这是三个小交付物合成的收口任务：房间流程依赖前面全部接口，Juice/HUD/遥测在同一个可玩场景里验收，拆开反而无法独立评审。

**Files:**
- Create: `core/rooms/room_combat.gd`、`core/rooms/room_combat.tscn`、`core/rooms/training_room.gd`、`core/rooms/training_room.tscn`
- Create: `data/rooms/m0_combat.json`
- Modify: `autoload/fx.gd`（完整实现）、`autoload/event_bus.gd`（如需补信号）
- Create: `ui/debug_hud.gd`、`core/meta/telemetry.gd`、`fx/white_flash.gdshader`
- Create: `tests/unit/test_room_flow.gd`、`tests/unit/test_fx.gd`、`tests/unit/test_telemetry.gd`

**Interfaces:**
- Consumes: 全部前序任务
- Produces:
  - `RoomCombat`（Node2D）：`load_config(cfg: Dictionary)`；进入→锁门→按 `waves` 逐波刷怪（怪全灭进下一波）→清完开门+奖励爆发+`EventBus.room_cleared`。刷怪点距门 ≥64px、距玩家 ≥120px。
  - `Fx`：`hitstop(ms)`（`get_tree().paused`，真实毫秒后恢复，process_mode ALWAYS）、`shake(strength, duration)`（`Fx.trauma` 供相机衰减）、`on_enemy_hit/on_player_hurt/on_roll` 挂钩、`spawn_damage_number(pos, amount, is_crit)`。
  - `Telemetry.log_row(cols: Array) -> void`（user://telemetry.csv，表头首建）。
  - 主场景 `training_room.tscn`：假人×3（hp 9999，可开关回血）、武器架（6 把 M0 武器拾取台）、Debug HUD（FPS/实体/弹幕/无敌帧/清房计时）、可手动玩。

- [ ] **Step 1: 写失败测试**

`tests/unit/test_room_flow.gd`（无头驱动 RoomCombat 逻辑层 `RoomFlow`——把波次状态机抽成纯逻辑类）：

```gdscript
class_name TestRoomFlow
extends GdUnitTestSuite

func test_lock_waves_clear() -> void:
    var flow := auto_free(RoomFlow.new())
    flow.setup({"waves": [["a"], ["b", "c"]], "coins": 30, "energy_orbs": 4})
    flow.on_entered(0)
    assert_bool(flow.locked).is_true()
    assert_int(flow.pending_spawns()).is_equal(1)
    flow.notify_killed("a", 10)               # 第一波清
    assert_int(flow.pending_spawns()).is_equal(2)
    flow.notify_killed("b", 20)
    flow.notify_killed("c", 21)
    assert_bool(flow.locked).is_false()
    assert_bool(flow.cleared).is_true()
    assert_int(flow.rewards.get("coins", 0)).is_equal(30)
```

`tests/unit/test_fx.gd`：

```gdscript
class_name TestFx
extends GdUnitTestSuite

func test_hitstop_restores_and_coalesces() -> void:
    Fx.hitstop(40)
    Fx.hitstop(60)          # 取更长的
    assert_bool(get_tree().paused).is_true()
    await get_tree().create_timer(0.1, true, false, true).timeout   # 真实 100ms
    assert_bool(get_tree().paused).is_false()

func test_shake_decays() -> void:
    Fx.shake(6.0, 0.25)
    assert_float(Fx.trauma).is_greater(0.0)
    for _i in 300:
        Fx.decay_step()                    # 每帧衰减（×0.9），300 帧后归零
    assert_float(Fx.trauma).is_equal_approx(0.0, 0.001)
```

`tests/unit/test_telemetry.gd`：

```gdscript
class_name TestTelemetry
extends GdUnitTestSuite

func test_log_row_appends() -> void:
    DirAccess.remove_absolute("user://telemetry.csv")   # 不存在时报错可忽略
    Telemetry.log_row(["m0", 1, 2])
    assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_true()
    var text := FileAccess.get_file_as_string("user://telemetry.csv")
    assert_str(text).contains("m0,1,2")
```

- [ ] **Step 2: 运行确认失败**。**Step 3: 实现**（要点）

`RoomFlow`（`core/rooms/room_flow.gd`，纯逻辑）：

```gdscript
class_name RoomFlow
## 房间波次状态机（可无头测试）。RoomCombat 场景层消费它的事件。

var locked := false
var cleared := false
var rewards := {}
var _waves: Array = []
var _wave := -1
var _alive: Array[String] = []

func setup(cfg: Dictionary) -> void:
    _waves = cfg.get("waves", [])
    rewards = {"coins": int(cfg.get("coins", 30)), "energy_orbs": int(cfg.get("energy_orbs", 4))}

func on_entered(_frame: int) -> void:
    locked = true
    _advance_wave()

func pending_spawns() -> int:
    return 0 if _wave < 0 or _wave >= _waves.size() else (_waves[_wave] as Array).size() - _alive.size()

func current_wave_ids() -> Array:
    return [] if _wave < 0 or _wave >= _waves.size() else _waves[_wave]

func notify_killed(_id: String, _frame: int) -> void:
    _alive.pop_back()
    if _alive.is_empty() and pending_spawns() == 0:
        _advance_wave()

func _advance_wave() -> void:
    _wave += 1
    _alive.clear()
    if _wave >= _waves.size():
        locked = false
        cleared = true
        return
    _alive.assign((current_wave_ids() as Array).map(func(s): return String(s)))
```

（注：`notify_killed` 在场景层由 `EventBus.enemy_killed` 桥接；`pending_spawns` 语义=还需刷的数量。实现者按测试语义对齐。）

`RoomCombat` 场景层：读 `data/rooms/m0_combat.json`（`{"id":"m0_combat","waves":[["crossbowman","kuli_bug"],["vine_charger","cave_bat","crossbowman"]],"coins":30,"energy_orbs":4,"hearts":1}`）；`EntryZone(Area2D)` 玩家进入→`flow.on_entered`→门柱滑落动画（Tween 属表现层）→按波 `EnemyBase.setup(GameDB.enemies[id])` 刷在合格点位（过滤函数 `valid_spawn_points()` 单测覆盖：距 4 门 ≥64px、距玩家 ≥120px）→`EventBus.enemy_killed`→`flow.notify_killed`→清完：开门、生成金币×30/蓝珠×4/红心×1（`Pickup(Area2D)`，玩家接触结算 `heal(1)/add_energy(8)`/金币计数）→`EventBus.room_cleared`。

`Fx` 完整实现：hitstop 用 `get_tree().paused = true` + `create_timer(ms/1000.0, true, false, true).timeout` 恢复（真实毫秒，process_mode ALWAYS；并发调用取 max，用计数器防提前恢复）；`trauma` 衰减每帧 ×0.9；命中白闪 shader `fx/white_flash.gdshader`（`uniform float flash_amount`，mix 到白色）挂在敌人 Sprite 材质上，`on_enemy_hit` 置 1 后每帧衰减；`on_player_hurt` 调 `shake(2.0, 0.12)`；暴击伤害数字放大 1.5×+hitstop 40ms，击杀 hitstop 60ms+粒子爆散（CPUParticles2D 一次性）。

`DebugHUD`（CanvasLayer+Label）：每帧刷新 `Engine.get_frames_per_second()`、`combat.active_count()`、实体数、玩家无敌帧标志、清房计时（flow 进入帧差）。

`Telemetry`：

```gdscript
class_name Telemetry
const PATH := "user://telemetry.csv"

static func log_row(cols: Array) -> void:
    var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
    if f == null:
        f = FileAccess.open(PATH, FileAccess.WRITE)
        f.store_line("event,ts_frame,v1,v2,v3")
    f.seek_end()
    f.store_line(",".join(cols.map(func(c): return str(c))))
    f.flush()
```

事件埋点：射击（fire）、命中（hit, is_crit）、击杀（kill, ttk_ticks）、玩家受击（hurt, hp）、清房（room_clear, 用时）。

- [ ] **Step 4: 运行测试** —— Expected: 全绿。
- [ ] **Step 5: 手动验证**（完整可玩闭环）：进训练房拿 6 把武器各打一轮 → 进战斗房清两波 → 门锁/开、奖励爆发、金币磁吸、暴击 hitstop 可感知 → 死亡（站桩挨打）触发受击反馈。全程 Debug HUD 无异常（FPS ≥58 @1440×810）。
- [ ] **Step 6: Commit**

```bash
git add core/rooms/ data/rooms/ ui/ core/meta/ fx/ autoload/ tests/unit/
git commit -m "feat(m0-t12): combat room flow, juice v1, training range, debug hud, telemetry"
```

---

### Task 13: M0 门禁验收

**Files:**
- Create: `docs/superpowers/reports/m0-gate.md`
- Modify: 无代码（修复循环产生的改动随修复提交）

**Interfaces:**
- Consumes: 全部 M0 任务
- Produces: 门禁报告 + git tag `m0`（绿）或缺陷清单（红→修复循环）。

- [ ] **Step 1: 集成守卫跑全量**

Run: `tools/run_tests.cmd` → 全绿；`godot --headless --path . --quit-after 300` → 无报错退出码 0。

- [ ] **Step 2: 试玩员执行 GDD §18.5 手感清单（M0 适用子集）**

逐项实测并在 `m0-gate.md` 记录证据（截图/录屏帧）：

1. 输入到画面响应 ≤1 逻辑帧（移动/射击起手无迟滞感）。
2. 翻滚无敌可实拍验证：弹幕穿过身体无伤（录屏逐帧）。
3. TTK：老伙计打弩兵（HP16）≤2.0s（遥测 `kill` 行核对 ttk_ticks ≤120）。
4. 击杀/受击/暴击/翻滚反馈全部触发（清单勾选）。
5. 近战反弹稳定复现（10 次尝试 ≥9 次成功且手感清晰）。
6. Debug HUD：1440×810 下 FPS ≥58；同屏 300 弹压力场景（训练房输入作弊键 spawn 弹幕雨）不掉帧。
7. 30 分钟自由试玩 ≥1 次"再来一局"意愿（主观评分 ≥3/5）。

- [ ] **Step 3: 门禁结论**

- 全绿 → `git tag m0`，向用户汇报并申请 M1 计划编写授权。
- 任一 FAIL → 缺陷清单回流对应任务实现者修复 → 复测（≤2 轮）→ 仍 FAIL 升级用户（改设计数值或降标准需用户拍板）。

- [ ] **Step 4: Commit 报告**

```bash
git add docs/superpowers/reports/m0-gate.md
git commit -m "docs(m0-t13): m0 gate report"
```

---

## 附：任务依赖图

```
t1 → t2 → t3 → t4 → t5 → t6 → t7 → t8 → t9 → t10 → t11 → t12 → t13
           └────────────────┴──── 纯逻辑模块可并行 ────┘
（t4/t5 可并行；t8/t9 依赖 t6+t7；t10/t11 可并行；t12 收口）
```
