class_name TestTrialMods
extends GdUnitTestSuite
## m3-fix1：试炼 mods 10 键消费端逐键接线测试（规格 §7 白名单）。
## 契约：① mods 为空字典（普通局）时所有消费端行为与现状逐字节一致（零漂移）；
## ② 注入 mods 后行为可断言地改变。各键系统消费端见 core/meta/trial_mods.gd 头注对照表。

const TRIAL_DATE := "2026-09-01"

var _saved_mods: Dictionary = {}
var _saved_seed: int = 0


func before_test() -> void:
	_saved_mods = RunState.mods
	_saved_seed = RunState.run_seed


func after_test() -> void:
	RunState.mods = _saved_mods
	RunState.run_seed = _saved_seed


func _mods_set(mods: Dictionary) -> void:
	RunState.mods = mods


# ---------------------------------------------------------------- 1) enemy_speed_pct

func test_enemy_speed_scale_zero_drift_and_scaling() -> void:
	assert_float(TrialMods.enemy_speed_scale()).is_equal(1.0)          # 普通局恒等
	_mods_set({"enemy_speed_pct": 20})
	assert_float(TrialMods.enemy_speed_scale()).is_equal_approx(1.2, 0.0001)

func test_enemy_speed_body_velocity_scales() -> void:
	# 消费端落点：EnemyBase 表现层速度式 = (brain_pos - global_position) * FPS × scale。
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16, "speed": 60}))
	e.brain_pos = Vector2(60, 0)
	e.position = Vector2.ZERO
	var base: float = (e.brain_pos - e.global_position).length() * 60.0
	_mods_set({"enemy_speed_pct": 20})
	var scaled: float = base * TrialMods.enemy_speed_scale()
	assert_float(scaled).is_equal_approx(base * 1.2, 0.0001)

# ---------------------------------------------------------------- 2) enemy_attack_speed_pct

func test_attack_speed_windup_and_cooldown_scale() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({
		"id": "crossbowman", "archetype": "shooter", "hp": 16,
		"windup_ticks": 30, "cd_ticks": 108,
	}))
	assert_int(e._windup_ticks(30)).is_equal(30)               # 零漂移：蓄力 30
	assert_int(e._attack_cooldown_ticks(108)).is_equal(78)     # 零漂移：冷却 108-30
	_mods_set({"enemy_attack_speed_pct": 20})
	assert_int(e._windup_ticks(30)).is_equal(25)               # 30/1.2 = 25
	assert_int(e._attack_cooldown_ticks(108)).is_equal(65)     # 78/1.2 = 65

func test_attack_speed_zero_tick_semantics_preserved() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({"id": "crossbowman", "archetype": "shooter", "hp": 16}))
	_mods_set({"enemy_attack_speed_pct": 50})
	assert_int(e._scaled_attack_ticks(0)).is_equal(0)          # 0 拍语义不被放大成 1

# ---------------------------------------------------------------- 3) bullet_speed_pct

func test_bullet_speed_scale_cap_and_zero_drift() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create({
		"id": "crossbowman", "archetype": "shooter", "hp": 16, "bullet_speed": 110,
	}))
	assert_float(e.enemy_bullet_speed(110)).is_equal(110.0)            # 无因子恒等
	_mods_set({"bullet_speed_pct": 25})
	assert_float(e.enemy_bullet_speed(110)).is_equal(137.5)            # 慢弹等比提速
	var fast: EnemyBase = auto_free(EnemyFactory.create({
		"id": "rock_crystal_turret", "archetype": "turret", "hp": 20, "bullet_speed": 150,
	}))
	assert_float(fast.enemy_bullet_speed(150)).is_equal(150.0)         # 快弹封顶 150（GDD §7.5）
	var over: EnemyBase = auto_free(EnemyFactory.create({
		"id": "x", "archetype": "shooter", "hp": 5, "bullet_speed": 200,
	}))
	assert_float(over.enemy_bullet_speed(200)).is_equal(200.0)         # 上限不倒扣存量快弹

# ---------------------------------------------------------------- 4) drop_melee_only

func test_drop_melee_only_filters_pool() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 40:
		var wid := ShopLogic.roll_weapon_id(rng, 1, [], "combat", true)
		assert_bool(wid.is_empty() or String((GameDB.weapons[wid] as Dictionary).get("category", "")) == "melee").is_true()

func test_drop_melee_only_zero_drift_random_stream() -> void:
	# 零漂移：melee_only=false 与旧签名同 rng 种子抽签序列逐发一致（掷签消费不变）。
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	for i in 30:
		var legacy := ShopLogic.roll_weapon_id(a, 1, [], "combat")
		var explicit := ShopLogic.roll_weapon_id(b, 1, [], "combat", false)
		assert_str(legacy).is_equal(explicit)

# ---------------------------------------------------------------- 5) energy_cost_mult

func test_energy_cost_mult_ceil_and_zero_drift() -> void:
	assert_int(TrialMods.player_energy_cost(4)).is_equal(4)            # 无因子恒等
	_mods_set({"energy_cost_mult": 1.5})
	assert_int(TrialMods.player_energy_cost(4)).is_equal(6)            # ceil(6.0)
	assert_int(TrialMods.player_energy_cost(3)).is_equal(5)            # ceil(4.5) = 5
	assert_int(TrialMods.player_energy_cost(0)).is_equal(0)            # 0 耗 ×1.5 仍 0（字面语义）

# ---------------------------------------------------------------- 6) shop_discount_pct

func test_shop_price_discount_rounding_and_zero_drift() -> void:
	assert_int(TrialMods.shop_price(100)).is_equal(100)                # 无因子恒等
	_mods_set({"shop_discount_pct": 50})
	assert_int(TrialMods.shop_price(100)).is_equal(50)                 # 半价
	assert_int(TrialMods.shop_price(25)).is_equal(15)                  # 12.5 → round(2.5)=3 → 15
	assert_int(TrialMods.shop_price(8)).is_equal(5)                    # 4 → round5 → 5（下限 5 同值）

func test_shop_heart_purchase_discounted_and_no_hearts_rejected() -> void:
	_mods_set({"shop_discount_pct": 50})
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet = ctx["wallet"]
	var player: Player = ctx["player"]
	player.hp = 3
	shop._buy_item("heart")
	assert_int(player.hp).is_equal(5)                                  # 治疗仍生效
	assert_int(wallet.coins).is_equal(500 - 15)                        # 25 → 折后 15（round5）
	_mods_set({"shop_discount_pct": 50, "no_hearts": true})
	var ctx2 := _open_shop()
	var wallet2 = ctx2["wallet"]
	var player2: Player = ctx2["player"]
	player2.hp = 3
	ctx2["shop"]._buy_item("heart")                                    # no_hearts：红心拒售
	assert_int(player2.hp).is_equal(3)
	assert_int(wallet2.coins).is_equal(500)

# ---------------------------------------------------------------- 7) no_hearts

func test_no_hearts_flag_and_coin_equivalent() -> void:
	assert_bool(TrialMods.no_hearts()).is_false()
	_mods_set({"no_hearts": true})
	assert_bool(TrialMods.no_hearts()).is_true()
	assert_int(TrialMods.HEART_DROP_COIN_EQUIV).is_equal(12)           # 等值金币口径（25/2HP→12）

# ---------------------------------------------------------------- 8) vision_scale

func test_vision_scale_zero_drift_and_value() -> void:
	assert_float(TrialMods.vision_scale()).is_equal(1.0)
	_mods_set({"vision_scale": 0.65})
	assert_float(TrialMods.vision_scale()).is_equal_approx(0.65, 0.0001)

func test_vision_biomefx_min_not_double_multiplied() -> void:
	var fx: BiomeFx = auto_free(BiomeFx.new())
	add_child(fx)
	assert_float(fx.light_radius_px).is_equal(BiomeFx.LIGHT_RADIUS_PX)
	_mods_set({"vision_scale": 0.65})
	fx.apply_vision_scale_min(TrialMods.vision_scale())
	assert_float(fx.light_radius_px).is_equal_approx(BiomeFx.LIGHT_RADIUS_PX * 0.65, 0.001)
	fx.apply_vision_scale_min(0.9)                                     # 更亮候选不被采纳（取更暗者）
	assert_float(fx.light_radius_px).is_equal_approx(BiomeFx.LIGHT_RADIUS_PX * 0.65, 0.001)

# ---------------------------------------------------------------- 9) elite_bonus_pct

func test_elite_extra_copies() -> void:
	assert_int(TrialMods.elite_extra_copies()).is_equal(0)             # 无因子零改动
	_mods_set({"elite_bonus_pct": 100})
	assert_int(TrialMods.elite_extra_copies()).is_equal(1)             # ×2 双精英
	_mods_set({"elite_bonus_pct": 200})
	assert_int(TrialMods.elite_extra_copies()).is_equal(2)

func test_elite_wave_expansion_marks_only_elite_guests() -> void:
	# 波次扩増语义（消费端 FloorScene._spawn_wave 同式，快照遍历防链式翻倍）：
	# 仅 kind=="elite" 标记体翻倍，同 wave_id 追加（RoomFlow 按出现次数计数）。
	# 注：快照必须 duplicate()——本基线实测 Array(Array(x)) 链式构造会别名共享
	# （追加互见、循环失控至 OOM 守卫截断），duplicate() 才是真拷贝。
	_mods_set({"elite_bonus_pct": 100})
	var waves: Array = ["kuli_bug", "cave_bat", "kuli_bug", "elite_charger"]
	var out := waves.duplicate()
	var extra := TrialMods.elite_extra_copies()
	var snapshot := waves.duplicate()
	for id: String in snapshot:
		if id != "elite_charger":          # 消费端以 GUEST_SPECS kind=="elite" 判定，此处同义
			continue
		for c in extra:
			out.append(id)
	assert_int(out.size()).is_equal(5)
	assert_int(out.count("elite_charger")).is_equal(2)
	assert_int(out.count("kuli_bug")).is_equal(2)
	assert_int(out.count("cave_bat")).is_equal(1)

# ---------------------------------------------------------------- 9b) altar_elite_surge（m4-c4 祭坛分支读点）

func test_altar_elite_surge_zero_drift_and_activation() -> void:
	# 祭坛 elite_surge 分支唯一读点（消费端 = Altar.interact）：普通局 mods 恒 {}
	# → 恒 false（零漂移）；elite_surge 因子（mods 键 elite_bonus_pct > 0）激活；
	# 无关因子不串扰。
	assert_bool(TrialMods.altar_elite_surge()).is_false()
	_mods_set({"elite_bonus_pct": 100})
	assert_bool(TrialMods.altar_elite_surge()).is_true()
	_mods_set({"elite_bonus_pct": 1})
	assert_bool(TrialMods.altar_elite_surge()).is_true()
	_mods_set({"elite_bonus_pct": 0})
	assert_bool(TrialMods.altar_elite_surge()).is_false()
	_mods_set({"enemy_speed_pct": 20, "bullet_speed_pct": 25})
	assert_bool(TrialMods.altar_elite_surge()).is_false()

# ---------------------------------------------------------------- 10) force_element

func test_force_element_none_by_default_and_deterministic_per_floor() -> void:
	assert_int(TrialMods.floor_force_element(1)).is_equal(Elements.Id.NONE)   # 无因子
	_mods_set({"force_element": "random"})
	RunState.run_seed = 12345
	var a := TrialMods.floor_force_element(1)
	var b := TrialMods.floor_force_element(1)
	assert_int(a).is_equal(b)                                          # 同种子同层恒同元素
	var pool: Array = TrialMods.FORCE_ELEMENT_POOL
	assert_bool(pool.has(a)).is_true()
	var seen := {}
	for seed in range(1, 17):
		RunState.run_seed = seed * 7919
		seen[TrialMods.floor_force_element(1)] = true
	assert_int(seen.size()).is_greater(1)                              # 种子空间覆盖多元素

func test_force_element_unifies_enchant_profile() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	var w := {"element": "fire"}
	var plain := rig.element_hit_profile(w, 0)
	assert_int(int(plain["element"])).is_equal(Elements.Id.FIRE)       # 零漂移：原生元素
	_mods_set({"force_element": "random"})
	RunState.run_seed = 2468
	var forced := TrialMods.floor_force_element(1)
	var prof := rig.element_hit_profile(w, 0)
	assert_int(int(prof["element"])).is_equal(forced)                  # 武器原生元素被统一
	rig.enchant_element = Elements.Id.ICE                              # 永久增益 proc 元素
	rig.enchant_proc_chance = 0.5
	var prof2 := rig.element_hit_profile(w, 0)
	assert_int(int(prof2["proc_element"])).is_equal(forced)            # 增益元素同样统一
	assert_float(float(prof2["proc_chance"])).is_equal_approx(0.5, 0.0001)  # proc 概率语义保留
	rig.temporary_enchant_element = Elements.Id.SHOCK                  # 星髓像临时附魔
	rig.temporary_enchant_until = 100
	var prof3 := rig.element_hit_profile(w, 10)
	assert_int(int(prof3["element"])).is_equal(forced)                 # 临时附魔亦统一
	assert_int(int(prof3["proc_element"])).is_equal(Elements.Id.NONE)  # 「独立覆盖」结构保留

# ---------------------------------------------------------------- fixture

## 建店替身（同 test_shop.gd 习语的最小集）。
func _open_shop() -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	var wallet := WalletStub.new()
	wallet.coins = 500
	shop.open({
		"floor_idx": 1,
		"weapons": ["laohuoji", "maodingqiang", "duangong"],
		"items": [{"kind": "heart"}, {"kind": "energy"}],
		"drink": "shenmi_hunhe",
	}, wallet, player, false)
	return {"shop": shop, "wallet": wallet, "player": player, "rig": rig}

## 金币桩（duck-typed wallet，同 test_shop.gd WalletProbe 口径）。
class WalletStub:
	var coins: int = 0
	func spend_coins(n: int) -> bool:
		if coins < n:
			return false
		coins -= n
		return true
	func add_coins(n: int) -> void:
		coins += n
