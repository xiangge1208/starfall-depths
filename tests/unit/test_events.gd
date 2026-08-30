class_name TestEvents
extends GdUnitTestSuite
## m1-t19 事件房（4 选 1）契约测试。
## 1) open_random_event 确定性（注入 rng：同 seed 同事件）+ 合法 id + 4 id 全覆盖
## 2) 神秘商人：仅 hp > 2 时可用 2 HP 交易（绕盾）+ 随机饮料效果经 apply_effect
##    接缝落地（spy）；hp=1/2 fail-closed，面板保持可拒绝且不发成功信号/奖励；
##    无接缝时默认 _apply_effect 落地（hp_max 路径实证）
## 3) 乞丐：接受 = spend_coins(40) 成功 → pending_investment=120 + beggar_paid_floor 记层；
##    余额不足拒绝零副作用（70% 返还掷签归 T20 跨层结算，本任务只记账——规格明示）
## 4) 星髓泉：shield_max+1 且 shield+1，每局一次（RunState.star_spring_used 守卫，二次无效）
## 5) 涂鸦墙：提示来自 10 条中文文案池（非空、确定性）
## 6) 每房一事件（used 守卫：重开/随机重开均拒绝）；Esc=拒绝；接受/拒绝按钮接线；
##    event_resolved 信号；未 setup 守卫。

const SEED := 20260828


# ---------------------------------------------------------------- 替身与桩

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 建房 + setup + 指定事件开面板（per-event 用例的直开捷径）。
func _room(event_id: String, seed_value := SEED) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var room: EventRoom = auto_free(EventRoom.new())
	root.add_child(room)
	room.setup(player, _rng(seed_value))
	assert_bool(room.open_event(event_id)).is_true()
	return {"room": room, "player": player, "root": root}


func before_test() -> void:
	# 快照 RunState 相关字段（after_test 恢复，保全套件无串扰）
	_saved = {
		"coins": RunState.coins,
		"floor_idx": RunState.floor_idx,
		"pending_investment": RunState.pending_investment,
		"beggar_paid_floor": RunState.beggar_paid_floor,
		"star_spring_used": RunState.star_spring_used,
	}


var _saved: Dictionary = {}


func after_test() -> void:
	RunState.coins = int(_saved["coins"])
	RunState.floor_idx = int(_saved["floor_idx"])
	RunState.pending_investment = int(_saved["pending_investment"])
	RunState.beggar_paid_floor = int(_saved["beggar_paid_floor"])
	RunState.star_spring_used = bool(_saved["star_spring_used"])


# ================================================================ 1) 抽取确定性

func test_open_random_event_same_seed_same_event() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var a: EventRoom = auto_free(EventRoom.new())
	root.add_child(a)
	a.setup(auto_free(Player.new()), _rng(SEED))
	var b: EventRoom = auto_free(EventRoom.new())
	root.add_child(b)
	b.setup(auto_free(Player.new()), _rng(SEED))
	var id_a := a.open_random_event()
	var id_b := b.open_random_event()
	assert_str(id_a).is_equal(id_b)
	assert_bool(EventRoom.EVENT_IDS.has(id_a)).is_true()


func test_open_random_event_always_returns_valid_id() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	for i in 32:
		var room: EventRoom = auto_free(EventRoom.new())
		root.add_child(room)
		room.setup(auto_free(Player.new()), _rng(SEED + i))
		assert_bool(EventRoom.EVENT_IDS.has(room.open_random_event())).is_true()


func test_open_random_event_covers_all_four_ids() -> void:
	# 200 抽全缺席任一 id 的概率 ~4×(3/4)^200 ≈ 0——覆盖性 sanity
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var seen := {}
	for i in 200:
		var room: EventRoom = auto_free(EventRoom.new())
		root.add_child(room)
		room.setup(auto_free(Player.new()), _rng(i * 7919))
		seen[room.open_random_event()] = true
	assert_int(seen.size()).is_equal(4)


func test_open_event_unknown_id_rejected() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var room: EventRoom = auto_free(EventRoom.new())
	root.add_child(room)
	room.setup(auto_free(Player.new()), _rng(SEED))
	assert_bool(room.open_event("bogus")).is_false()
	assert_bool(room.ui_visible()).is_false()


func test_each_event_once_per_room() -> void:
	# 每房 4 选 1 一次性：开过即 used，同房再开（指定或随机）均拒绝
	var ctx := _room("graffiti")
	var room: EventRoom = ctx["room"]
	assert_bool(room.ui_visible()).is_true()
	room.refuse()
	assert_bool(room.open_event("beggar")).is_false()
	assert_str(room.open_random_event()).is_equal("")
	assert_bool(room.ui_visible()).is_false()


func test_open_random_event_without_setup_guarded() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var room: EventRoom = auto_free(EventRoom.new())
	root.add_child(room)
	assert_str(room.open_random_event()).is_equal("")
	assert_bool(room.ui_visible()).is_false()


# ================================================================ 2) 神秘商人

func test_merchant_accept_loses_2_hp_bypassing_shield() -> void:
	# 规格明示：2 HP 直扣（hp 字段直写，绕盾——不经 take_hit）
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.hp = 8
	player.shield = 4
	room.accept()
	assert_int(player.hp).is_equal(6)
	assert_int(player.shield).is_equal(4)


func test_merchant_accept_applies_random_effect_via_seam_spy() -> void:
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	var calls: Array[Dictionary] = []
	room.apply_effect = func(effect: String, value: float, _p: Node2D) -> void:
		calls.append({"effect": effect, "value": value})
	room.accept()
	assert_int(calls.size()).is_equal(1)
	# 效果抽取确定：open_event 时的预掷 = 同 seed rng 对 7 效果池的首掷
	var probe := _rng(SEED)
	var expected: String = EventRoom.DRINK_EFFECT_IDS[probe.randi_range(0, EventRoom.DRINK_EFFECT_IDS.size() - 1)]
	assert_str(String(calls[0]["effect"])).is_equal(expected)
	assert_float(float(calls[0]["value"])).is_equal(float(EventRoom.DRINK_EFFECTS[expected]))
	# 池口径 = GDD §13.2 八饮料去「随机」（7 条）
	assert_int(EventRoom.DRINK_EFFECT_IDS.size()).is_equal(7)


func test_merchant_accept_with_one_hp_is_fail_closed_and_panel_can_still_refuse() -> void:
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.hp = 1
	var effects: Array[Dictionary] = []
	var resolved: Array[Dictionary] = []
	room.apply_effect = func(_effect: String, _value: float, _p: Node2D) -> void:
		effects.append({})
	room.event_resolved.connect(func(id: String, accepted: bool) -> void:
		resolved.append({"id": id, "accepted": accepted}))

	room.accept()

	assert_int(player.hp).is_equal(1)
	assert_array(effects).is_empty()
	assert_array(resolved).is_empty()
	assert_bool(room.ui_visible()).is_true()
	assert_str(room.current_event()).is_equal("mystery_merchant")
	room.refuse()
	assert_bool(room.ui_visible()).is_false()
	assert_int(resolved.size()).is_equal(1)
	assert_str(String(resolved[0]["id"])).is_equal("mystery_merchant")
	assert_bool(bool(resolved[0]["accepted"])).is_false()


func test_merchant_accept_with_exact_cost_is_fail_closed_without_reward() -> void:
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.hp = EventRoom.MERCHANT_HP_COST
	var effects: Array[Dictionary] = []
	var resolved: Array[Dictionary] = []
	room.apply_effect = func(_effect: String, _value: float, _p: Node2D) -> void:
		effects.append({})
	room.event_resolved.connect(func(id: String, accepted: bool) -> void:
		resolved.append({"id": id, "accepted": accepted}))

	room.accept()

	assert_int(player.hp).is_equal(EventRoom.MERCHANT_HP_COST)
	assert_array(effects).is_empty()
	assert_array(resolved).is_empty()
	assert_bool(room.ui_visible()).is_true()
	assert_str(room.current_event()).is_equal("mystery_merchant")
	room.refuse()
	assert_bool(room.ui_visible()).is_false()
	assert_int(resolved.size()).is_equal(1)
	assert_str(String(resolved[0]["id"])).is_equal("mystery_merchant")
	assert_bool(bool(resolved[0]["accepted"])).is_false()


func test_merchant_accept_with_three_hp_pays_and_resolves_successfully() -> void:
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.hp = EventRoom.MERCHANT_HP_COST + 1
	var effects: Array[Dictionary] = []
	var resolved: Array[Dictionary] = []
	room.apply_effect = func(effect: String, value: float, _p: Node2D) -> void:
		effects.append({"effect": effect, "value": value})
	room.event_resolved.connect(func(id: String, accepted: bool) -> void:
		resolved.append({"id": id, "accepted": accepted}))

	room.accept()

	assert_int(player.hp).is_equal(1)
	assert_int(effects.size()).is_equal(1)
	assert_int(resolved.size()).is_equal(1)
	assert_str(String(resolved[0]["id"])).is_equal("mystery_merchant")
	assert_bool(bool(resolved[0]["accepted"])).is_true()
	assert_bool(room.ui_visible()).is_false()


func test_merchant_refuse_no_side_effects() -> void:
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.hp = 8
	var calls: Array[Dictionary] = []
	room.apply_effect = func(_effect: String, _value: float, _p: Node2D) -> void:
		calls.append({})
	room.refuse()
	assert_int(player.hp).is_equal(8)
	assert_int(calls.size()).is_equal(0)
	assert_bool(room.ui_visible()).is_false()


func test_merchant_default_apply_increases_hp_max() -> void:
	# 无接缝注入时走默认 _apply_effect：找预掷命中 hp_max 的 seed 实证 +2 HP 上限
	var hit := -1
	for seed_value in range(1, 500):
		var probe := _rng(seed_value)
		if EventRoom.DRINK_EFFECT_IDS[probe.randi_range(0, 6)] == "hp_max":
			hit = seed_value
			break
	assert_int(hit).is_greater(0)                       # 1/7 概率，500 seed 内必中
	var ctx := _room("mystery_merchant", hit)
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.hp_max = 8
	room.accept()
	assert_int(player.hp_max).is_equal(10)


func test_merchant_default_path_all_seven_effects_have_real_consumers() -> void:
	# 不依赖随机抽中：直接走 EventRoom 的缺省消费者，覆盖七种具名效果。
	var player: Player = auto_free(Player.new())
	player.hp_max = 8
	player.energy_max = 100
	player.move_speed = Player.MOVE_SPEED
	var room: EventRoom = auto_free(EventRoom.new())
	room._apply_effect("hp_max", 2.0, player)
	room._apply_effect("energy_max", 20.0, player)
	room._apply_effect("move_speed_pct", 0.05, player)
	room._apply_effect("crit_pct", 3.0, player)
	room._apply_effect("shield_delay_reduction_ticks", 30.0, player)
	room._apply_effect("roll_cd_pct", 0.05, player)
	room._apply_effect("status_rate_pct", 0.20, player)
	assert_int(player.hp_max).is_equal(10)
	assert_int(player.energy_max).is_equal(120)
	assert_float(player.move_speed).is_equal_approx(Player.MOVE_SPEED * 1.05, 0.001)
	assert_float(player.crit_bonus).is_equal_approx(0.03, 0.0001)
	assert_int(player.shield_delay_reduction_ticks).is_equal(30)
	assert_int(player.roll_cd_reduction_ticks).is_equal(3)
	assert_float(player.status_rate_bonus).is_equal_approx(0.20, 0.0001)


func test_merchant_accept_closes_panel_and_consumes_event() -> void:
	var ctx := _room("mystery_merchant")
	var room: EventRoom = ctx["room"]
	room.accept()
	assert_bool(room.ui_visible()).is_false()
	assert_str(room.current_event()).is_equal("")


# ================================================================ 3) 乞丐

func test_beggar_accept_deducts_and_records_investment() -> void:
	var ctx := _room("beggar")
	var room: EventRoom = ctx["room"]
	RunState.coins = 100
	RunState.floor_idx = 2
	room.accept()
	assert_int(RunState.coins).is_equal(60)             # 40 金投出
	assert_int(RunState.pending_investment).is_equal(120)
	assert_int(RunState.beggar_paid_floor).is_equal(2)  # 记付款层（T20 跨层返还消费）


func test_beggar_insufficient_coins_rejected_no_side_effects() -> void:
	var ctx := _room("beggar")
	var room: EventRoom = ctx["room"]
	RunState.coins = 10
	RunState.floor_idx = 3
	RunState.pending_investment = 0
	RunState.beggar_paid_floor = 0
	room.accept()
	assert_int(RunState.coins).is_equal(10)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.beggar_paid_floor).is_equal(0)
	assert_bool(room.ui_visible()).is_false()


func test_beggar_refuse_no_side_effects() -> void:
	var ctx := _room("beggar")
	var room: EventRoom = ctx["room"]
	RunState.coins = 100
	RunState.floor_idx = 1
	room.refuse()
	assert_int(RunState.coins).is_equal(100)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.beggar_paid_floor).is_equal(0)


# ================================================================ 4) 星髓泉

func test_star_spring_accept_adds_shield_max_and_shield() -> void:
	var ctx := _room("star_spring")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.shield_max = 4
	player.shield = 2
	RunState.star_spring_used = false
	room.accept()
	assert_int(player.shield_max).is_equal(5)
	assert_int(player.shield).is_equal(3)
	assert_bool(RunState.star_spring_used).is_true()


func test_star_spring_second_use_no_op() -> void:
	# 每局一次守卫：RunState 星全局旗——新房间实例再开再接受也不生效
	var ctx := _room("star_spring")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.shield_max = 4
	player.shield = 4
	RunState.star_spring_used = false
	room.accept()
	assert_int(player.shield_max).is_equal(5)
	# 第二间房（星髓泉 used 旗是房间级的，RunState 旗才是局级守卫）
	var ctx2 := _room("star_spring")
	var room2: EventRoom = ctx2["room"]
	var player2: Player = ctx2["player"]
	room2.accept()
	assert_int(player2.shield_max).is_equal(4)
	assert_int(player2.shield).is_equal(4)


func test_star_spring_refuse_no_side_effects() -> void:
	var ctx := _room("star_spring")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	player.shield_max = 4
	RunState.star_spring_used = false
	room.refuse()
	assert_int(player.shield_max).is_equal(4)
	assert_bool(RunState.star_spring_used).is_false()


# ================================================================ 5) 涂鸦墙

func test_graffiti_pool_is_10_nonempty_chinese_tips() -> void:
	assert_int(EventRoom.GRAFFITI_TIPS.size()).is_equal(10)
	for tip: String in EventRoom.GRAFFITI_TIPS:
		assert_str(tip).is_not_empty()


func test_graffiti_panel_shows_tip_from_pool_deterministic() -> void:
	var ctx := _room("graffiti")
	var room: EventRoom = ctx["room"]
	var tip := room.desc_text()
	assert_bool(EventRoom.GRAFFITI_TIPS.has(tip)).is_true()
	# 同 seed 同提示
	var ctx2 := _room("graffiti")
	assert_str(ctx2["room"].desc_text()).is_equal(tip)
	# 接受/拒绝均无副作用，仅关面板
	room.accept()
	assert_bool(room.ui_visible()).is_false()


# ================================================================ 6) 面板与交互

func test_panel_texts_per_event() -> void:
	for id: String in EventRoom.EVENT_IDS:
		var ctx := _room(id)
		var room: EventRoom = ctx["room"]
		assert_bool(room.ui_visible()).is_true()
		assert_str(room.title_text()).is_not_empty()
		assert_str(room.desc_text()).is_not_empty()
		assert_str(room.current_event()).is_equal(id)
		assert_str(room.accept_button().text).is_equal("接受")
		assert_str(room.refuse_button().text).is_equal("拒绝")


func test_accept_button_triggers_path() -> void:
	# 按钮接线：pressed 信号 → accept() 行为路径
	var ctx := _room("star_spring")
	var room: EventRoom = ctx["room"]
	var player: Player = ctx["player"]
	RunState.star_spring_used = false
	room.accept_button().pressed.emit()
	assert_int(player.shield_max).is_equal(5)


func test_refuse_button_closes_without_side_effects() -> void:
	var ctx := _room("beggar")
	var room: EventRoom = ctx["room"]
	RunState.coins = 100
	room.refuse_button().pressed.emit()
	assert_int(RunState.coins).is_equal(100)
	assert_bool(room.ui_visible()).is_false()


func test_esc_refuses_no_side_effects() -> void:
	var ctx := _room("beggar")
	var room: EventRoom = ctx["room"]
	RunState.coins = 100
	RunState.pending_investment = 0
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	room._unhandled_input(ev)
	assert_int(RunState.coins).is_equal(100)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_bool(room.ui_visible()).is_false()


func test_event_resolved_signal_emitted() -> void:
	var ctx := _room("graffiti")
	var room: EventRoom = ctx["room"]
	var seen: Array[Dictionary] = []
	room.event_resolved.connect(func(id: String, accepted: bool) -> void:
		seen.append({"id": id, "accepted": accepted}))
	room.refuse()
	assert_int(seen.size()).is_equal(1)
	assert_str(String(seen[0]["id"])).is_equal("graffiti")
	assert_bool(bool(seen[0]["accepted"])).is_false()
