class_name TestMetaWiring
extends GdUnitTestSuite
## m2-t35（补充卡）meta 生效接线契约测试（裁定⑨）：
## ① T12 的 25 个增益键 buff_* meta 逐键消费（player/pickup/shop/drink/rig 侧真实行为；
##    纯展示键与所有权外交接键如实列单——见类尾「无行为键清单」断言）。
## ② T15 天赋 4 键（talent_dmg_pct / talent_hurt_iframe_pct / talent_coin_gain_pct /
##    talent_pickup_radius_pct）消费 + run_root 开局 Hero→Buffs→Talents 固定顺序 apply。
## ③ buff 重 apply（层重建 floor setup / 层间三选一）后补天赋 re-apply（同键叠加语义）。
## ⑤ shop/drink 购买成功点 shop_purchase(kind) 信号发射（T3 K 表同名）。
## RED→GREEN：本文件先于实现提交跑出 RED（缺字段/缺信号/缺方法 = 编译级失败），
## 实现后翻绿；组合叠加语义（同键 buff+talent、phoenix 每局一次、haggle 负值 clamp）在此锁定。

const RUN_ROOT_SCENE := "res://core/rooms/run_root.tscn"
const INTER_FLOOR_SCENE := "res://core/rooms/inter_floor.tscn"
const PLAYER_SCENE := "res://core/player/player.tscn"


# ---------------------------------------------------------------- 替身与桩

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	return p


class RigProbe extends WeaponRig:
	var spawned: Array = []
	func _spawn(cfg: Dictionary) -> void:
		spawned.append(cfg)


func _rig_with_player() -> RigProbe:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	return r


## 隔离真实档的中性/指定已购 TalentSystem（读真实 autoload 后立即摘除后端，密封裁定㉔同源）。
func _talents(ids: Array = []) -> TalentSystem:
	var ts := TalentSystem.new()
	ts.save_system = null
	ts.purchased.assign(ids)
	return ts


## 测试用弹幕夹具（damage 5 → talent_dmg_pct 0.10 后 round(5.5)=6，可分辨乘区生效）。
func _inject_testgun() -> void:
	GameDB.weapons["testgun_m2t35"] = {
		"id": "testgun_m2t35", "name": "测试枪", "rarity": "common", "damage": 5,
		"rate": 2.0, "energy_cost": 0, "projectiles": 1, "spread_deg": 0.0,
		"bullet_speed": 200.0, "pierce": 0, "bounce": 0, "is_melee": false,
		"element": "none",
	}


func after_test() -> void:
	GameDB.weapons.erase("testgun_m2t35")


# ================================================================ ②③ 组合叠加（裁定 RED 组）

func test_run_root_begin_applies_talents_fixed_order_hero_buffs_talents() -> void:
	# 开局固定顺序：Hero（HeroApplier）→ Buffs（floor setup 空基线）→ Talents（本卡接线）。
	RunState.start_run("vanguard")
	var root: Node2D = auto_free((load(RUN_ROOT_SCENE) as PackedScene).instantiate())
	root.talents = _talents(["blue_vitality"])        # hp_max +2
	add_child(root)
	root._begin()
	var p: Player = root.player
	assert_object(p).is_not_null()
	assert_int(p.hp_max).is_equal(10)                 # vanguard 8 + blue_vitality 2
	assert_dict(TalentSystem.effects_of(p)).contains_keys("talent_dmg_pct")


func test_run_root_floor_rebuild_reapplies_talents_after_buff_reapply() -> void:
	# ③ buff 重 apply（层重建 floor setup）绝不吞掉天赋贡献（T15 披露的绝对写覆盖缝）。
	RunState.start_run("vanguard")
	var root: Node2D = auto_free((load(RUN_ROOT_SCENE) as PackedScene).instantiate())
	root.talents = _talents(["blue_vitality", "red_deadeye"])   # hp+2, crit+4%
	add_child(root)
	root._begin()
	var p: Player = root.player
	assert_int(p.hp_max).is_equal(10)
	root.buffs.pick("vigor")                          # hp_max +2（层间三选一语义）
	root._on_next_floor_requested(1)                  # 重建层：floor setup 重 apply buffs
	assert_int(p.hp_max).is_equal(12)                 # 8 + buff2 + talent2（不被覆盖回 10）
	assert_float(p.crit_bonus).is_equal_approx(0.04, 0.0001)   # 天赋 crit 不被 buff 重 apply 清零


func test_inter_floor_buff_pick_reapplies_talents_same_key_stacks() -> void:
	# 层间三选一 pick → buffs.apply（绝对写 wipe）→ repair 补六键天赋贡献；同键（crit_pct）
	# 叠加语义：天赋 red_deadeye 0.04（开局首拍落地）+ buff precision 0.06 = 0.10。
	var inter: InterFloor = auto_free((load(INTER_FLOOR_SCENE) as PackedScene).instantiate())
	var p: Player = auto_free((load(PLAYER_SCENE) as PackedScene).instantiate())
	var buffs := BuffManager.new()
	var ts := _talents(["red_deadeye"])
	add_child(inter)                                  # 入树（玩家收养 + rig/_ready 就位）
	inter.setup(p, buffs, 1, ts)
	ts.apply_to_player(p)                             # 开局首拍等价（run_root._start_floor）
	assert_float(p.crit_bonus).is_equal_approx(0.04, 0.0001)
	inter.flow.offered = ["precision"]                # 白盒制造确定名录（flow.setup 后 phase=BUFF）
	inter._on_buff_chosen("precision")                # buffs 0.06 绝对写 → repair 补 0.04
	assert_float(p.crit_bonus).is_equal_approx(0.10, 0.0001)
	assert_int(buffs.picked.size()).is_equal(1)


func test_phoenix_survives_fatal_once_per_run_even_after_buff_reapply() -> void:
	# 不死鸟（附录 C：致死伤害保留 1 HP，每局 1 次）：首次致死 → hp=1 且 fatal=false；
	# buff 重 apply 绝对重写 flag=1 也不复活第二次（消费记号独立于聚合 meta）。
	var p := _player()
	p.hp = 1
	p.shield = 0
	p.set_meta("buff_phoenix_flag", 1)
	var fatal_seen: Array = []
	EventBus.player_damaged.connect(func(a: int, f: bool) -> void: fatal_seen.append(f))
	p.take_hit_ctx({"amount": 10}, 100)
	assert_int(p.hp).is_equal(1)                      # 保留 1 HP
	assert_bool(fatal_seen[0]).is_false()
	# flag 被 BuffManager 绝对重写回 1（幂等落地语义），但每局只复活一次
	p.set_meta("buff_phoenix_flag", 1)
	p.take_hit_ctx({"amount": 10}, 200)               # 新一拍（过无敌帧）
	assert_int(p.hp).is_equal(0)
	assert_bool(fatal_seen[1]).is_true()


func test_haggle_negative_pct_reduces_and_clamps_price_floor() -> void:
	# 议价（haggle_pct 负值 = 折扣）：×(1+pct) 取整到 5；下限 5 永不为负/为零；正值不加价。
	assert_int(ShopLogic.haggle_price(20, -0.15)).is_equal(15)     # 17 → 15
	assert_int(ShopLogic.haggle_price(85, -0.15)).is_equal(70)     # 72.25 → 70
	assert_int(ShopLogic.haggle_price(260, -0.15)).is_equal(220)   # 221 → 220
	assert_int(ShopLogic.haggle_price(20, -0.95)).is_equal(5)      # 1 → clamp 5
	assert_int(ShopLogic.haggle_price(20, 0.0)).is_equal(20)
	assert_int(ShopLogic.haggle_price(20, 0.5)).is_equal(20)       # 防御：正值不乘


# ================================================================ ① buff 键逐键消费（player 侧）

func test_nerve_reflex_and_talent_pct_extend_hurt_iframes() -> void:
	# 神经反射 +15t；天赋 talent_hurt_iframe_pct 0.15 → round(48×1.15)=55；合计 70t。
	var p := _player()
	p.set_meta("buff_hurt_iframe_bonus_ticks", 15)
	# m2-t35 评审 Minor⑥（T33 顺手清）：原首个 neutral_effects() set_meta 被下行
	# 立即覆写，死调用删除。
	p.set_meta("talent_effects", {"talent_hurt_iframe_pct": 0.15})
	p.take_hit_ctx({"amount": 1}, 100)
	assert_bool(p.is_invincible_at(169)).is_true()    # 100+70-1
	assert_bool(p.is_invincible_at(170)).is_false()


func test_carapace_reduces_projectile_damage_only() -> void:
	# 甲壳 -8%：只对弹幕（source_type "projectile"）生效，向下取整且不低于 1。
	var p := _player()
	p.hp = 100
	p.shield = 0
	p.set_meta("buff_bullet_dmg_taken_pct", -0.08)
	p.take_hit_ctx({"amount": 10, "source_type": "projectile"}, 100)
	assert_int(p.hp).is_equal(91)                     # floor(9.2)=9
	p.take_hit_ctx({"amount": 10, "source_type": "contact"}, 200)
	assert_int(p.hp).is_equal(81)                     # 非弹幕不减
	p.take_hit_ctx({"amount": 10, "source_type": "status"}, 300)
	assert_int(p.hp).is_equal(71)                     # 状态 DoT 不减


func test_thorn_armor_reflects_contact_damage_to_attacker() -> void:
	# 荆棘护甲：被接触（source_type "contact"）时对来敌反伤 3。
	var p: Player = auto_free(Player.new())
	p._test_init()
	add_child(p)
	p.set_meta("buff_thorns_contact_dmg", 3)
	var enemy: ThornsEnemyStub = auto_free(ThornsEnemyStub.new())
	enemy.position = Vector2(100, 0)                  # 来敌方位（ctx.from 同点）
	enemy.add_to_group("enemies")                     # M0 分组契约（RoomCombat 刷怪同款）
	add_child(enemy)
	p.take_hit_ctx({"amount": 2, "from": Vector2(100, 0), "source_type": "contact"}, 100)
	assert_int(enemy.hit_amounts.size()).is_equal(1)
	assert_int(enemy.hit_amounts[0]).is_equal(3)
	# 非接触源不反伤
	p.take_hit_ctx({"amount": 2, "from": Vector2(100, 0), "source_type": "projectile"}, 200)
	assert_int(enemy.hit_amounts.size()).is_equal(1)


func test_thorn_armor_reflects_to_nearest_contact_enemy_not_group_order() -> void:
	# T35 评审 Minor⑤：反伤目标是「就近来敌」（ctx.from 距离最近），非组序首个。
	# 组序故意先加 12px 远敌、后加 5px 近敌——组序首个 = 远敌，就近 = 近敌。
	var p: Player = auto_free(Player.new())
	p._test_init()
	add_child(p)
	p.set_meta("buff_thorns_contact_dmg", 3)
	var far: ThornsEnemyStub = auto_free(ThornsEnemyStub.new())
	far.position = Vector2(112, 0)                    # 距 from 12px（16px 环内）
	far.add_to_group("enemies")
	add_child(far)
	var near: ThornsEnemyStub = auto_free(ThornsEnemyStub.new())
	near.position = Vector2(105, 0)                   # 距 from 5px
	near.add_to_group("enemies")
	add_child(near)
	p.take_hit_ctx({"amount": 2, "from": Vector2(100, 0), "source_type": "contact"}, 100)
	assert_int(far.hit_amounts.size()).is_equal(0)    # 组序首个（远敌）不挨打
	assert_int(near.hit_amounts.size()).is_equal(1)   # 就近来敌挨打
	assert_int(near.hit_amounts[0]).is_equal(3)


func test_thorn_armor_still_reflects_on_lethal_contact() -> void:
	# T35 评审 Minor⑤（致死弹行为显式化）：附录 C「被接触时反伤 3」无致死例外——
	# 荆棘结算位于受击收尾，致死接触照常反伤（设计口径钉死，非疏漏）。
	var p: Player = auto_free(Player.new())
	p._test_init()
	add_child(p)
	p.hp = 1
	p.shield = 0
	p.set_meta("buff_thorns_contact_dmg", 3)
	var enemy: ThornsEnemyStub = auto_free(ThornsEnemyStub.new())
	enemy.position = Vector2(100, 0)
	enemy.add_to_group("enemies")
	add_child(enemy)
	p.take_hit_ctx({"amount": 5, "from": Vector2(100, 0), "source_type": "contact"}, 100)
	assert_int(p.hp).is_equal(0)                      # 致死
	assert_int(enemy.hit_amounts.size()).is_equal(1)  # 荆棘仍反伤
	assert_int(enemy.hit_amounts[0]).is_equal(3)


func test_dash_extend_increases_roll_distance() -> void:
	# 冲刺延伸 +25%：翻滚初速 = 56×1.25 / (13/60) ≈ 323.08 px/s。
	var p := _player()
	p.set_meta("buff_roll_distance_pct", 0.25)
	p.start_roll(Vector2.RIGHT, 100)
	assert_float(p._roll_vel.length()).is_equal_approx(70.0 / (13.0 / 60.0), 0.01)
	var plain := _player()
	plain.start_roll(Vector2.RIGHT, 100)
	assert_float(plain._roll_vel.length()).is_equal_approx(56.0 / (13.0 / 60.0), 0.01)


func test_anti_ice_blocks_ice_slow_and_ice_floor_slip() -> void:
	# 抗冰：免疫冰系弹缓（element ICE 的 slow ctx）+ 冰面打滑（friction_mult 强制 1.0）。
	var p := _player()
	p.take_hit_ctx({"amount": 1, "element": Elements.Id.ICE, "slow_pct": 0.3, "slow_ticks": 60}, 100)
	assert_float(p.incoming_slow_pct).is_equal_approx(0.3, 0.0001)   # 无抗性照常减速
	var q := _player()
	q.set_meta("buff_anti_ice", 1)
	q.take_hit_ctx({"amount": 1, "element": Elements.Id.ICE, "slow_pct": 0.3, "slow_ticks": 60}, 100)
	assert_float(q.incoming_slow_pct).is_equal_approx(0.0, 0.0001)   # 冰缓免疫
	# 非冰系减速不受抗冰影响
	var r := _player()
	r.set_meta("buff_anti_ice", 1)
	r.take_hit_ctx({"amount": 1, "element": Elements.Id.NONE, "slow_pct": 0.3, "slow_ticks": 60}, 100)
	assert_float(r.incoming_slow_pct).is_equal_approx(0.3, 0.0001)
	# 冰面打滑：IceZone 写入 0.25 后，抗冰者拍内强制回 1.0
	r.friction_mult = 0.25
	r.apply_anti_ice_friction()
	assert_float(r.friction_mult).is_equal_approx(1.0, 0.0001)
	var s := _player()
	s.friction_mult = 0.25
	s.apply_anti_ice_friction()
	assert_float(s.friction_mult).is_equal_approx(0.25, 0.0001)      # 无抗性不干预


func test_energy_siphon_gains_energy_on_enemy_kill() -> void:
	# 蓝能汲取：击杀 10% 概率回 2 蓝（RNG 走 RunState 分盐流；测试以 1.0/0.0 两锚点钉语义）。
	var p: Player = auto_free(load(PLAYER_SCENE).instantiate())
	add_child(p)                                      # 入树 → _ready 订阅 enemy_killed
	p.energy = 0
	p.set_meta("buff_kill_energy_chance", 1.0)
	p.set_meta("buff_kill_energy_amount", 2)
	EventBus.enemy_killed.emit("slime")
	assert_int(p.energy).is_equal(2)
	p.set_meta("buff_kill_energy_chance", 0.0)
	EventBus.enemy_killed.emit("slime")
	assert_int(p.energy).is_equal(2)                  # 0 概率不回蓝
	p.energy = 98
	p.set_meta("buff_kill_energy_chance", 1.0)
	EventBus.enemy_killed.emit("slime")
	assert_int(p.energy).is_equal(100)                # 溢出 clamp 到 energy_max


func test_ammo_convert_passive_energy_interval() -> void:
	# 弹药转化：每 interval ticks 被动回 amount 蓝（聚合键可叠加：interval/amount 各自求和）。
	var p := _player()
	p.energy = 0
	p.set_meta("buff_passive_energy_interval_ticks", 10)
	p.set_meta("buff_passive_energy_amount", 10)
	for i in 25:
		p.passive_energy_tick(1000 + i)
	assert_int(p.energy).is_equal(20)                 # 第 10、20 拍各回 10
	# 未拾取该增益 = 无被动回蓝
	var q := _player()
	q.energy = 50
	for i in 100:
		q.passive_energy_tick(1000 + i)
	assert_int(q.energy).is_equal(50)


func test_anti_fire_flag_lands_for_existing_hazard_consumers() -> void:
	# 抗火：HazardMagma/magma_tyrant 既有消费先例——本卡只锁 meta 落地契约。
	var p := _player()
	var buffs := BuffManager.new()
	buffs.pick("anti_fire")
	buffs.apply_to_player(p)
	assert_int(int(p.get_meta("buff_anti_fire", 0))).is_equal(1)


func test_rig_meta_keys_land_for_combat_side_consumers() -> void:
	# 猎杀者/共鸣增幅/复仇者：消费点在 CombatSystem/Resonance 命中结算路径（本卡所有权外，
	# 交接清单键）——本卡锁 rig meta 落地契约，供后续卡 get_meta 接线。
	var p := _player()
	var rig := RigProbe.new()
	p.add_child(rig)
	rig._test_init()
	var buffs := BuffManager.new()
	buffs.pick("hunter")
	buffs.apply_to_rig(rig)
	assert_float(float(rig.get_meta("buff_dmg_vs_statused_pct", 0.0))).is_equal_approx(0.2, 0.0001)


# ================================================================ ① pickup 侧（wealth / pickup_magnet）

func test_wealth_pct_multiplies_coin_gain_with_carry() -> void:
	# 财富 +20%：金币计数乘区，零头跨拾取累加（5 枚 → 6 次 on_collect）。
	var collector := CoinCounter.new()
	var p := _player()
	p.set_meta("buff_wealth_pct", 0.2)
	for i in 5:
		var coin: Pickup = auto_free(Pickup.new())
		coin.kind = "coin"
		coin.on_collect = collector.collect
		coin._on_body_entered(p)
	assert_int(collector.count).is_equal(6)


func test_talent_coin_gain_pct_multiplies_coin_gain() -> void:
	# 天赋金币获取 +15%（绿系天赋）：7 枚 → 8 次（零头累加语义）。
	var collector := CoinCounter.new()
	var p := _player()
	p.set_meta("talent_effects", {"talent_coin_gain_pct": 0.15})
	for i in 7:
		var coin: Pickup = auto_free(Pickup.new())
		coin.kind = "coin"
		coin.on_collect = collector.collect
		coin._on_body_entered(p)
	assert_int(collector.count).is_equal(8)


func test_wealth_and_talent_coin_gain_stack_additively() -> void:
	# 同键叠加：buff 0.2 + talent 0.15 = 0.35/枚 → 5 枚 6 次（1.35 步进 carry 推演）。
	var collector := CoinCounter.new()
	var p := _player()
	p.set_meta("buff_wealth_pct", 0.2)
	p.set_meta("talent_effects", {"talent_coin_gain_pct": 0.15})
	for i in 5:
		var coin: Pickup = auto_free(Pickup.new())
		coin.kind = "coin"
		coin.on_collect = collector.collect
		coin._on_body_entered(p)
	assert_int(collector.count).is_equal(6)


func test_default_coin_gain_is_exactly_one_per_pickup() -> void:
	# 无增益：恒 1 枚/次（carry 不漂移）。
	var collector := CoinCounter.new()
	var p := _player()
	for i in 5:
		var coin: Pickup = auto_free(Pickup.new())
		coin.kind = "coin"
		coin.on_collect = collector.collect
		coin._on_body_entered(p)
	assert_int(collector.count).is_equal(5)


func test_pickup_magnet_and_talent_radius_stack() -> void:
	# 捡拾磁铁 +60% 与天赋磁吸 +30% 叠加：56×1.9 = 106.4；无增益回落基线 56。
	var p := _player()
	p.set_meta("buff_pickup_radius_pct", 0.6)
	p.set_meta("talent_effects", {"talent_pickup_radius_pct": 0.3})
	assert_float(Pickup.magnet_range_px(p)).is_equal_approx(106.4, 0.001)
	assert_float(Pickup.magnet_range_px(_player())).is_equal_approx(56.0, 0.001)


# ================================================================ ① drink / shop 侧（glutton / haggle）

func test_glutton_scales_drink_effect_values() -> void:
	# 大胃王 +50%：饮料效果值 ×1.5（hp_max +2→+3；移速 +10%→+15%；同口径覆盖商店饮料卡）。
	var p := _player()
	p.set_meta("buff_drink_effect_pct", 0.5)
	DrinkMachine._apply_drink("hp_max", 2.0, p)
	assert_int(p.hp_max).is_equal(11)                 # 8 + int(3.0)
	DrinkMachine._apply_drink("move_speed_pct", 10.0, p)
	assert_float(p.move_speed).is_equal_approx(92.0, 0.001)   # 80 × 1.15
	var plain := _player()
	DrinkMachine._apply_drink("hp_max", 2.0, plain)
	assert_int(plain.hp_max).is_equal(10)             # 无增益回归基线（既有契约不回归）


func test_shop_applies_haggle_to_weapon_and_drink_prices() -> void:
	# 议价：商店武器/饮料卡按 haggle_pct 折价（道具为规格固定价，不参与议价——披露）。
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	holder.add_child(shop)
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.set_meta("buff_haggle_pct", -0.15)
	var wallet := WalletProbe.new()
	wallet.coins = 10000
	shop.open({"weapons": ["laohuoji"], "items": [{"kind": "heart"}],
		"drink": "shenmi_hunhe", "floor_idx": 1}, wallet, p, false)
	shop._buy_weapon(0)
	assert_int(wallet.spent[0]).is_equal(15)          # common A1 20 → 15
	var spent_after_weapon := wallet.spent.size()
	shop._buy_item("heart")
	assert_int(wallet.spent[spent_after_weapon]).is_equal(25)   # 道具固定价不议价
	var spent_after_item := wallet.spent.size()
	shop._buy_drink()
	assert_int(wallet.spent[spent_after_item]).is_equal(15)     # 饮料 20 × 0.85 = 17 → round5 = 15


class WalletProbe:
	var coins: int = 0
	var spent: Array[int] = []
	func spend_coins(n: int) -> bool:
		if coins < n:
			return false
		coins -= n
		spent.append(n)
		return true
	func add_coins(n: int) -> void:
		coins += n


class CoinCounter:
	var count := 0
	func collect() -> void:
		count += 1


class ThornsEnemyStub extends Node2D:
	var hit_amounts: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hit_amounts.append(int(ctx.get("amount", 0)))


# ================================================================ ② talent 键消费（rig / pickup / player）

func test_talent_dmg_pct_scales_ranged_bullet_damage() -> void:
	# 处刑/磨刃（talent_dmg_pct）：远程落弹伤害乘区（同 rate_mult 模式）。
	_inject_testgun()
	var holder := _rig_with_player()
	holder.get_parent().set_meta("talent_effects", {"talent_dmg_pct": 0.10})
	holder.equip("testgun_m2t35")
	holder._fire_slot(holder.current(), Vector2.RIGHT, false, 100)
	assert_int(int(holder.spawned[0]["damage"])).is_equal(6)   # round(5×1.1)
	var plain := _rig_with_player()
	plain.equip("testgun_m2t35")
	plain._fire_slot(plain.current(), Vector2.RIGHT, false, 100)
	assert_int(int(plain.spawned[0]["damage"])).is_equal(5)


# ================================================================ ⑤ shop_purchase 信号

func test_shop_and_drink_machine_emit_shop_purchase_with_kind() -> void:
	# T3 K 表同名信号：购买成功点发射（weapon/heart/energy/drink）；失败点不发。
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	holder.add_child(shop)
	var p: Player = auto_free(Player.new())
	p._test_init()
	var wallet := WalletProbe.new()
	wallet.coins = 10000
	shop.open({"weapons": ["laohuoji"], "items": [{"kind": "heart"}, {"kind": "energy"}],
		"drink": "shenmi_hunhe", "floor_idx": 1}, wallet, p, false)
	var kinds: Array[String] = []
	shop.shop_purchase.connect(func(k: String) -> void: kinds.append(k))
	shop._buy_weapon(0)
	shop._buy_item("heart")
	shop._buy_drink()
	assert_str(kinds[0]).is_equal("weapon")
	assert_str(kinds[1]).is_equal("heart")
	assert_str(kinds[2]).is_equal("drink")
	# 失败点（余额不足）不发射
	var poor := WalletProbe.new()
	poor.coins = 0
	shop.open({"weapons": ["laohuoji"], "items": [], "drink": "", "floor_idx": 1}, poor, p, false)
	var before := kinds.size()
	shop._buy_weapon(0)
	assert_int(kinds.size()).is_equal(before)
	# 饮料机购买成功点
	var machine: DrinkMachine = auto_free(DrinkMachine.new())
	var mw := WalletProbe.new()
	mw.coins = 1000
	machine.configure({"uses_left": 3}, mw)
	var drink_kinds: Array[String] = []
	machine.shop_purchase.connect(func(k: String) -> void: drink_kinds.append(k))
	assert_bool(machine.buy(0)).is_true()
	assert_str(drink_kinds[0]).is_equal("drink")
	assert_int(machine.uses_left).is_equal(2)
