class_name TestFacilities
extends GdUnitTestSuite
## m1-t16 设施单测（雕像×4 + 饮料机）：
## 1) drinks.json 8 行 schema + 附录 F.1 逐条数值 + GameDB fail-closed 校验
## 2) 饮料机：购买扣费/效果逐条落地/次数耗尽售罄/金币不足拒绝/神秘混合注入 rng 从 7 选 1
## 3) 雕像：四类效果落地（meta 接缝）、每局每类限 1 次、金币不足拒绝
## 4) 护盾精灵：拦截敌方弹扣次数、射程外/友方弹忽略、3 次耗尽自灭、无 combat 只跟随
## 替身构造：wallet/combat/projectile 全部走 duck-typed 替身（同 T14 wallet 契约），
## 不进树（headless 无物理树依赖），frame 用显式参数注入保证确定性。

const ENEMY_FACTION := 1  # Projectile.Faction.ENEMY（替身避免依赖真实弹构造）

var _run_seed_before := 0
var _floor_idx_before := 0

func before_test() -> void:
	_run_seed_before = RngSvc.run_seed
	_floor_idx_before = RunState.floor_idx

func after_test() -> void:
	# 兜底流回归会显式切 run/floor；逐例还原，避免污染同套件后续项或其它套件。
	RngSvc.setup_run(_run_seed_before)
	RunState.floor_idx = _floor_idx_before

# ---- duck-typed 替身 ----

class StubWallet extends RefCounted:
	var coins := 0
	var spend_calls := 0
	func spend_coins(n: int) -> bool:
		spend_calls += 1
		if coins >= n:
			coins -= n
			return true
		return false

class StubPool extends RefCounted:
	var active: Array = []

class StubCombat extends RefCounted:
	var pool: StubPool = StubPool.new()
	var block_calls: Array = []
	func block(p: Node2D) -> void:
		block_calls.append(p)

class StubCombatNoBlock extends RefCounted:
	# 有 pool（查询接缝）但无 block 方法（T18 接缝落地前真实 CombatSystem 的现状）
	var pool: StubPool = StubPool.new()

class StubProjectile extends Node2D:
	var faction := ENEMY_FACTION
	var radius := 3.0
	var life_ticks := 60
	var on_despawn_calls := 0
	func on_despawn() -> void:
		on_despawn_calls += 1

# ---- 公共构造 ----

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	return p

func _machine(wallet: StubWallet, rng_seed := -1) -> DrinkMachine:
	var m: DrinkMachine = auto_free(DrinkMachine.new())
	if rng_seed >= 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		m.rng = rng
	m.wallet = wallet
	return m

func _shrine(kind: String, wallet: StubWallet, used: Dictionary = {}) -> Shrine:
	var s: Shrine = auto_free(Shrine.new()).setup(kind, used)
	s.wallet = wallet
	return s

# ================= 1) drinks.json + GameDB =================

func test_drinks_loaded_8_rows() -> void:
	assert_int(GameDB.drinks.size()).is_equal(8)
	for id in ["shengming_soda", "nengliang_qishui", "jifeng_bohe", "yingyan_kafei",
			"chongneng_keke", "qingyu_qipao", "xingsui_tete", "shenmi_hunhe"]:
		assert_dict(GameDB.drinks).contains_keys(id)

func test_drink_rows_match_appendix_f1() -> void:
	# 附录 F.1 逐条：名称/效果/数值/价格 verbatim
	var expected := {
		"shengming_soda": ["生命苏打", "hp_max", 2, 30],
		"nengliang_qishui": ["蓝能汽水", "energy_max", 20, 25],
		"jifeng_bohe": ["疾风薄荷", "move_speed_pct", 5, 20],
		"yingyan_kafei": ["鹰眼咖啡", "crit_pct", 3, 35],
		"chongneng_keke": ["充能可可", "shield_delay_reduction_ticks", 30, 25],
		"qingyu_qipao": ["轻羽气泡", "roll_cd_ticks", 3, 30],
		"xingsui_tete": ["星髓特调", "status_rate_pct", 20, 35],
		"shenmi_hunhe": ["神秘混合", "random", 0, 20],
	}
	for id: String in expected:
		var row := GameDB.get_drink(id)
		var e: Array = expected[id]
		assert_str(row.get("name", "?")).is_equal(e[0])
		assert_str(row.get("effect", "?")).is_equal(e[1])
		assert_int(row.get("value", -1)).is_equal(e[2])
		assert_int(row.get("price", -1)).is_equal(e[3])

func test_drink_row_value_and_price_are_int() -> void:
	for id: String in GameDB.drinks:
		var row: Dictionary = GameDB.drinks[id]
		assert_int(typeof(row["value"])).is_equal(TYPE_INT)
		assert_int(typeof(row["price"])).is_equal(TYPE_INT)
		assert_int(typeof(row["effect"])).is_equal(TYPE_STRING)

func test_validate_drink_row_rejects_unknown_effect() -> void:
	var errors: Array[String] = GameDB.validate_drink_row(
		{"id": "x", "name": "x", "effect": "fly", "value": 0, "price": 1})
	assert_int(errors.size()).is_greater(0)

func test_validate_drink_row_accepts_known_effect() -> void:
	var errors: Array[String] = GameDB.validate_drink_row(
		{"id": "x", "name": "x", "effect": "hp_max", "value": 2, "price": 30})
	assert_int(errors.size()).is_equal(0)

func test_validate_drink_row_rejects_nonpositive_tick_effect() -> void:
	var errors: Array[String] = GameDB.validate_drink_row(
		{"id": "x", "name": "x", "effect": "roll_cd_ticks", "value": 0, "price": 30})
	assert_int(errors.size()).is_greater(0)

func test_validate_drink_row_rejects_random_with_value() -> void:
	var errors: Array[String] = GameDB.validate_drink_row(
		{"id": "x", "name": "x", "effect": "random", "value": 3, "price": 20})
	assert_int(errors.size()).is_greater(0)

func test_drinks_table_fail_closed_on_bad_effect() -> void:
	# 同 buffs fail-closed 路径：白名单外 effect 行拒绝入库，load_ok 置假
	var path := "user://test_bad_drink_16.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"x": {"id":"x","name":"x","effect":"fly","value":0,"price":1}}')
	f = null
	var db2: Variant = auto_free(load("res://autoload/game_db.gd").new())
	var loaded2: Dictionary = db2._load_table(path, GameDB.DRINK_SCHEMA,
		GameDB.DRINK_OPTIONAL, GameDB.validate_drink_row)
	assert_dict(loaded2).is_empty()
	assert_bool(db2.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_drinks_table_fail_closed_fractional_value() -> void:
	# value 声明 TYPE_INT：带小数（0.5s 直写秒数）必须被拒绝（须换算 ticks）
	var path := "user://test_frac_drink_16.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"x": {"id":"x","name":"x","effect":"hp_max","value":2.5,"price":30}}')
	f = null
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())
	var loaded: Dictionary = db._load_table(path, GameDB.DRINK_SCHEMA,
		GameDB.DRINK_OPTIONAL, GameDB.validate_drink_row)
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

# ================= 2) 饮料机 =================

func test_buy_spends_price_and_applies_effect() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var m := _machine(wallet)
	var p := _player()
	m.open({}, wallet, p)
	var idx: int = m.drink_ids().find("shengming_soda")
	assert_bool(m.buy(idx)).is_true()
	assert_int(wallet.coins).is_equal(70)          # 100 - 30
	assert_int(p.hp_max).is_equal(10)              # 8 + 2
	assert_int(m.uses_left).is_equal(2)            # 3/层 - 1

func test_buy_rejected_on_insufficient_coins() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 10
	var m := _machine(wallet)
	var p := _player()
	m.open({}, wallet, p)
	var idx: int = m.drink_ids().find("yingyan_kafei")   # 35 金
	assert_bool(m.buy(idx)).is_false()
	assert_int(wallet.coins).is_equal(10)
	assert_int(m.uses_left).is_equal(3)                  # 拒绝不扣次数
	assert_int(p.hp_max).is_equal(8)                     # 不落地效果
	assert_int(wallet.spend_calls).is_equal(1)           # 确实尝试过扣费

func test_uses_exhaust_after_three_buys() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 1000
	var m := _machine(wallet)
	var p := _player()
	m.open({}, wallet, p)
	var idx: int = m.drink_ids().find("jifeng_bohe")     # 最便宜 20 金 ×3
	for i in 3:
		assert_bool(m.buy(idx)).is_true()
	assert_bool(m.buy(idx)).is_false()                   # 第 4 次 → 售罄
	assert_int(m.uses_left).is_equal(0)
	assert_int(wallet.coins).is_equal(940)

func test_open_uses_machine_state_and_writes_back() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var m := _machine(wallet)
	var state := {"uses_left": 1}
	m.open(state, wallet, _player())
	assert_int(m.uses_left).is_equal(1)
	var idx: int = m.drink_ids().find("jifeng_bohe")
	assert_bool(m.buy(idx)).is_true()
	assert_int(state["uses_left"]).is_equal(0)           # 状态字典回写（跨楼层持久归调用方）
	assert_bool(m.buy(idx)).is_false()

func test_configure_binds_persistent_floor_state_before_open() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var state := {"uses_left": 1}
	var m := _machine(wallet)
	m.configure(state, wallet)
	assert_int(m.uses_left).is_equal(1)
	m.open(state, wallet, _player())
	var idx: int = m.drink_ids().find("jifeng_bohe")
	assert_bool(m.buy(idx)).is_true()
	assert_int(state["uses_left"]).is_equal(0)

func test_configure_initializes_missing_floor_state() -> void:
	var state := {}
	var m := _machine(StubWallet.new())
	m.configure(state, m.wallet)
	assert_int(state["uses_left"]).is_equal(DrinkMachine.USES_PER_FLOOR)
	assert_int(m.uses_left).is_equal(DrinkMachine.USES_PER_FLOOR)

func test_buy_invalid_index_rejected() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var m := _machine(wallet)
	m.open({}, wallet, _player())
	assert_bool(m.buy(-1)).is_false()
	assert_bool(m.buy(99)).is_false()
	assert_int(wallet.coins).is_equal(100)

func test_random_drink_rolls_one_of_seven_concrete() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var m := _machine(wallet, 42)
	var p := _player()
	m.open({}, wallet, p)
	var captured: Array = []
	m.drink_bought.connect(func(id: String) -> void: captured.append(id))
	var idx: int = m.drink_ids().find("shenmi_hunhe")
	assert_bool(m.buy(idx)).is_true()
	# 确定性复算：同 seed 的 rng 在同一 concrete 列表上应得同一 id
	var expect_rng := RandomNumberGenerator.new()
	expect_rng.seed = 42
	var expected: String = m.concrete_ids()[expect_rng.randi_range(0, 6)]
	assert_int(captured.size()).is_equal(1)
	assert_str(captured[0]).is_equal(expected)
	assert_str(expected).is_not_equal("shenmi_hunhe")    # 只从 7 条具体饮料中选
	assert_int(wallet.coins).is_equal(80)                # 神秘混合本身 20 金（非抽中者价格）

func test_random_drink_uninjected_fallback_uses_current_run_loot_stream() -> void:
	# 未注入不是非确定随机的许可：兜底结果须与当前 RunState loot 分盐流首掷完全一致。
	RngSvc.setup_run(160016)
	RunState.floor_idx = 2
	var wallet := StubWallet.new()
	var m := _machine(wallet)
	var expected_rng := RunState.stream(RunState.SALT_LOOT)
	var pool := m.concrete_ids()
	var expected: String = pool[expected_rng.randi_range(0, pool.size() - 1)]
	assert_str(m._roll_concrete()).is_equal(expected)
	assert_object(m.rng).is_not_null()

func test_apply_drink_effects_one_by_one() -> void:
	# 效果应用器纯逻辑逐条断言（附录 F.1 全部 7 条具体效果；pct 落 meta 为分数，tick 为整数）
	var p_hp := _player()
	DrinkMachine._apply_drink("hp_max", 2, p_hp)
	assert_int(p_hp.hp_max).is_equal(10)                       # 8 + 2
	var p_en := _player()
	DrinkMachine._apply_drink("energy_max", 20, p_en)
	assert_int(p_en.energy_max).is_equal(120)                  # 100 + 20
	var p_ms := _player()
	DrinkMachine._apply_drink("move_speed_pct", 5, p_ms)
	assert_float(p_ms.move_speed).is_equal(84.0)               # 80 × 1.05
	var p_cr := _player()
	DrinkMachine._apply_drink("crit_pct", 3, p_cr)
	assert_float(p_cr.crit_bonus).is_equal(0.03)
	var p_sd := _player()
	DrinkMachine._apply_drink("shield_delay_reduction_ticks", 30, p_sd)
	assert_int(p_sd.shield_delay_reduction_ticks).is_equal(30)
	var p_rc := _player()
	DrinkMachine._apply_drink("roll_cd_ticks", 3, p_rc)
	assert_int(p_rc.roll_cd_reduction_ticks).is_equal(3)
	var p_sr := _player()
	DrinkMachine._apply_drink("status_rate_pct", 20, p_sr)
	assert_float(p_sr.status_rate_bonus).is_equal(0.20)

func test_apply_drink_meta_effects_accumulate() -> void:
	var p := _player()
	DrinkMachine._apply_drink("crit_pct", 3, p)
	DrinkMachine._apply_drink("crit_pct", 3, p)
	assert_float(p.crit_bonus).is_equal(0.06)

func test_apply_drink_unknown_effect_fail_closed() -> void:
	var p := _player()
	DrinkMachine._apply_drink("fly", 9, p)
	assert_int(p.hp_max).is_equal(8)                     # 未知效果不落地（GameDB 校验外第二道防线）

# ================= 3) 雕像 =================

func test_shrine_four_kinds_setup_and_label() -> void:
	var labels := {"zhanshen": "战神像", "jingling": "精灵像", "fengshen": "风神像", "xingsui": "星髓像"}
	for kind: String in labels:
		var s := _shrine(kind, StubWallet.new())
		assert_str(s.kind).is_equal(kind)
		assert_str(s.action_label).is_equal(labels[kind])
		assert_bool(s.can_interact(null)).is_true()

func test_shrine_unknown_kind_not_interactable() -> void:
	var s := _shrine("bogus", StubWallet.new())
	assert_bool(s.can_interact(null)).is_false()

func test_shrine_zhanshen_applies_atk_speed_meta() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("zhanshen", wallet)
	var p := _player()
	assert_bool(s.activate(p, 1000)).is_true()
	assert_int(wallet.coins).is_equal(75)                          # 100 - 25
	assert_int(int(p.get_meta("atk_speed_boost_until", -1))).is_equal(1600)   # 1000 + 600t
	assert_float(float(p.get_meta("atk_speed_boost_pct", 0.0))).is_equal(0.25)
	assert_bool(s.used_kinds.has("zhanshen")).is_true()

func test_shrine_once_per_kind_per_run() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var used := {}
	var s := _shrine("zhanshen", wallet, used)
	var p := _player()
	assert_bool(s.activate(p, 1000)).is_true()
	assert_bool(s.activate(p, 2000)).is_false()                    # 第二次拒绝
	assert_int(wallet.coins).is_equal(75)
	assert_int(wallet.spend_calls).is_equal(1)
	assert_int(int(p.get_meta("atk_speed_boost_until", -1))).is_equal(1600)   # 效果不刷新

func test_shrine_used_state_shared_across_instances() -> void:
	# 每局每类限 1 次：used_kinds 字典由调用方持有，同 kind 另一座也 gating
	var wallet := StubWallet.new()
	wallet.coins = 100
	var used := {}
	var a := _shrine("jingling", wallet, used)
	var b := _shrine("jingling", wallet, used)
	assert_bool(a.activate(_player(), 100)).is_true()
	assert_bool(b.can_interact(null)).is_false()
	assert_bool(b.activate(_player(), 200)).is_false()

func test_shrine_other_kind_still_usable() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var used := {}
	var a := _shrine("zhanshen", wallet, used)
	var b := _shrine("fengshen", wallet, used)
	assert_bool(a.activate(_player(), 100)).is_true()
	assert_bool(b.can_interact(null)).is_true()

func test_shrine_wallet_rejection() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 10
	var s := _shrine("zhanshen", wallet)
	var p := _player()
	assert_bool(s.activate(p, 1000)).is_false()                    # 金币不足拒绝
	assert_bool(s.used_kinds.has("zhanshen")).is_false()           # 不标记已用（可再试）
	assert_int(p.get_meta("atk_speed_boost_until", -1)).is_equal(-1)

func test_shrine_fengshen_applies_move_and_free_energy_meta() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("fengshen", wallet)
	var p := _player()
	assert_bool(s.activate(p, 1000)).is_true()
	assert_int(int(p.get_meta("move_speed_boost_until", -1))).is_equal(1300)   # 1000 + 300t
	assert_float(float(p.get_meta("move_speed_boost_pct", 0.0))).is_equal(0.30)
	assert_int(int(p.get_meta("energy_free_until", -1))).is_equal(1300)

func test_shrine_xingsui_applies_random_enchant() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("xingsui", wallet)
	var p := _player()
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig.enchant_element = Elements.Id.FIRE
	p.weapon_rig = rig
	assert_bool(s.activate(p, 1000)).is_true()
	assert_int(rig.temporary_enchant_element).is_not_equal(Elements.Id.NONE)
	assert_bool([Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.POISON, Elements.Id.SHOCK]
		.has(rig.temporary_enchant_element)).is_true()
	assert_int(int(p.get_meta("enchant_element_until", -1))).is_equal(4600)    # 1000 + 3600t
	assert_int(int(p.get_meta("enchant_element_prev", -1))).is_equal(Elements.Id.FIRE)  # 恢复接缝

func test_shrine_xingsui_uninjected_fallback_uses_current_run_loot_stream() -> void:
	RngSvc.setup_run(160016)
	RunState.floor_idx = 3
	var expected_rng := RunState.stream(RunState.SALT_LOOT)
	var expected: int = Shrine.ENCHANTABLE[
		expected_rng.randi_range(0, Shrine.ENCHANTABLE.size() - 1)]
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("xingsui", wallet)
	var p := _player()
	var rig: WeaponRig = auto_free(WeaponRig.new())
	p.weapon_rig = rig
	assert_bool(s.activate(p, 10)).is_true()
	assert_int(rig.temporary_enchant_element).is_equal(expected)
	assert_object(s.rng).is_not_null()

func test_shrine_xingsui_requires_rig() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("xingsui", wallet)
	var p := _player()
	assert_bool(s.activate(p, 1000)).is_false()                    # 无 rig 不消费不扣费
	assert_int(wallet.coins).is_equal(100)
	assert_bool(s.used_kinds.has("xingsui")).is_false()

func test_shrine_jingling_spawns_shield_spirit() -> void:
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("jingling", wallet)
	var p := _player()
	assert_bool(s.activate(p, 1000)).is_true()
	var found: Array = p.get_children().filter(
		func(c: Node) -> bool: return c is ShieldSpirit)
	assert_int(found.size()).is_equal(1)
	var spirit: ShieldSpirit = found[0]
	assert_int(spirit.charges).is_equal(3)
	assert_bool(spirit.player == p).is_true()

func test_shrine_interact_path_marks_used() -> void:
	# interact(player) 默认帧路径（Engine 帧）：扣费 + 标记已用
	var wallet := StubWallet.new()
	wallet.coins = 100
	var s := _shrine("fengshen", wallet)
	var p := _player()
	s.interact(p)
	assert_bool(s.used_kinds.has("fengshen")).is_true()
	assert_int(wallet.coins).is_equal(75)

# ================= 4) 护盾精灵 =================

func test_spirit_follows_player_at_offset_24px() -> void:
	var p := _player()
	var spirit: ShieldSpirit = auto_free(ShieldSpirit.new()).setup(p)
	p.add_child(spirit)
	assert_vector(spirit.position).is_equal(Vector2(0, -24))       # 24px 偏移（子节点跟随免逐拍搬移）
	assert_int(spirit.charges).is_equal(3)

func test_spirit_blocks_enemy_projectile_in_range() -> void:
	var p := _player()
	var spirit: ShieldSpirit = auto_free(ShieldSpirit.new()).setup(p)
	p.add_child(spirit)
	var combat := StubCombat.new()
	var proj: StubProjectile = auto_free(StubProjectile.new())                               # 未进树：position 即 global
	proj.position = Vector2(5, -24)                                # 精灵在 (0,-24)：距离 5 ≤ 12+3r
	combat.pool.active.append(proj)
	spirit.combat = combat
	assert_bool(spirit.guard_tick()).is_true()
	assert_int(combat.block_calls.size()).is_equal(1)              # 经 combat.block 拦截
	assert_bool(combat.block_calls[0] == proj).is_true()
	assert_int(spirit.charges).is_equal(2)

func test_spirit_ignores_far_and_friendly_projectiles() -> void:
	var p := _player()
	var spirit: ShieldSpirit = auto_free(ShieldSpirit.new()).setup(p)
	p.add_child(spirit)
	var combat := StubCombat.new()
	var far: StubProjectile = auto_free(StubProjectile.new())
	far.position = Vector2(30, -24)                                # > 12px + 3r
	var friendly: StubProjectile = auto_free(StubProjectile.new())
	friendly.faction = 0                                           # PLAYER 弹不拦
	friendly.position = Vector2(4, -24)                            # 距离 4（在射程内但阵营不符）
	combat.pool.active.append_array([far, friendly])
	spirit.combat = combat
	assert_bool(spirit.guard_tick()).is_false()
	assert_int(combat.block_calls.size()).is_equal(0)
	assert_int(spirit.charges).is_equal(3)

func test_spirit_exhausts_after_three_blocks_and_frees() -> void:
	var p := _player()
	var spirit: ShieldSpirit = auto_free(ShieldSpirit.new()).setup(p)
	p.add_child(spirit)
	var combat := StubCombat.new()
	for i in 3:
		var proj: StubProjectile = auto_free(StubProjectile.new())
		proj.position = Vector2(3 + 2 * i, -24)                    # 与精灵同 y：距离 ≤ 12+3r
		combat.pool.active.append(proj)
	spirit.combat = combat
	for i in 3:
		assert_bool(spirit.guard_tick()).is_true()
	assert_int(spirit.charges).is_equal(0)
	assert_int(combat.block_calls.size()).is_equal(3)
	assert_bool(spirit.is_queued_for_deletion()).is_true()         # 耗尽自灭

func test_spirit_without_combat_just_follows() -> void:
	var p := _player()
	var spirit: ShieldSpirit = auto_free(ShieldSpirit.new()).setup(p, null)
	p.add_child(spirit)
	assert_bool(spirit.guard_tick()).is_false()
	assert_int(spirit.charges).is_equal(3)

func test_spirit_fallback_despawn_when_combat_has_no_block() -> void:
	# combat.block 接缝落地前（T18）：退化为 life_ticks=0 + on_despawn，
	# 且同发弹不得重复扣次数（_blocked_ids 去重）
	var p := _player()
	var spirit: ShieldSpirit = auto_free(ShieldSpirit.new()).setup(p)
	p.add_child(spirit)
	var combat := StubCombatNoBlock.new()                           # 有 pool 无 block 方法
	var proj: StubProjectile = auto_free(StubProjectile.new())
	proj.position = Vector2(2, -24)                                # 与精灵同 y：距离 2 ≤ 12+3r
	combat.pool.active.append(proj)
	spirit.combat = combat
	assert_bool(spirit.guard_tick()).is_true()
	assert_int(proj.life_ticks).is_equal(0)
	assert_int(proj.on_despawn_calls).is_equal(1)
	assert_int(spirit.charges).is_equal(2)
	assert_bool(spirit.guard_tick()).is_false()                     # 同弹去重：不再扣
	assert_int(spirit.charges).is_equal(2)
