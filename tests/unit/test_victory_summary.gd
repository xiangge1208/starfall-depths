class_name TestVictorySummary
extends GdUnitTestSuite
## m2-t18 F-1 胜利结算完整：触发链（第 3 层 Boss 死 → InterFloorFlow.victory_achieved →
## RunRoot 切胜利场景）+ VictorySummary 统计字段上屏 + 蓝晶胜利全额入账（对照死亡 50%）。
##
## 触发链三段验证：
##   纯逻辑段：floor>=3 open_with_offerings → victory_achieved（幂等只发一次；floor 1/2 不发）；
##   场景段：  RunRoot 收 floor_scene.boss_defeated → 嵌 InterFloor → 接线 flow 信号 →
##             路由到胜利场景（victory_route_override 接缝注入，不真跳场景）；
##   面板段：  _ready 直读 RunState 全量 + Telemetry.session_summary() 填充；
##             确认 → 蓝晶全额 → SaveSystem.add_gems → dismissed → exit_override。
##
## RunState 污染守卫：before/after 各 start_run 复位（test_inter_floor 同款）+
## DeathRecorder.reset() 清 Telemetry 会话（hurt/peak_dps 断言确定性）。

const RUN_ROOT_SCENE := "res://core/rooms/run_root.tscn"
const SUMMARY_SCENE := "res://ui/victory_summary.tscn"
const WIN_SEED := 1                    # 与 test_inter_floor 同源掷签种子（此处无掷签语义，仅定序）

var _root: Node2D = null


func before_test() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 0
	DeathRecorder.reset()               # Telemetry 会话清零（受击/DPS 断言不受前序套件污染）


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	RunState.start_run("vanguard")      # 复位楼层/种子/聚合（跨套件卫生）
	RunState.coins = 0
	DeathRecorder.reset()


# ================================================================ 触发链：纯逻辑段

func test_floor3_open_emits_victory_achieved_once() -> void:
	var f := InterFloorFlow.new()
	f.setup(3, BuffManager.new())
	var fired: Array = []
	f.victory_achieved.connect(func() -> void: fired.append(1))
	f.open_with_offerings(_rng(WIN_SEED))
	assert_int(fired.size()).is_equal(1)
	assert_bool(f.victory).is_true()
	# 幂等守卫：同一 flow 重复 open 不重复触发（防双结算路由）
	f.open_with_offerings(_rng(WIN_SEED))
	assert_int(fired.size()).is_equal(1)


func test_floor1_and_floor2_do_not_emit_victory() -> void:
	for floor_i in [1, 2]:
		var f := InterFloorFlow.new()
		f.setup(floor_i, BuffManager.new())
		var fired: Array = []
		f.victory_achieved.connect(func() -> void: fired.append(1))
		f.open_with_offerings(_rng(WIN_SEED))
		assert_int(fired.size()).is_equal(0)
		assert_bool(f.victory).is_false()


# ================================================================ 触发链：场景段（RunRoot）

func test_floor3_boss_death_routes_to_victory_scene() -> void:
	# 全链：floor_scene.boss_defeated → RunRoot 嵌 InterFloor(floor=3) → open →
	# flow.victory_achieved → _on_victory_achieved → 胜利路由（override 接缝捕获）。
	_root = _make_root()
	add_child(_root)
	_root._begin()
	RunState.floor_idx = 3
	var routed: Array = []
	_root.victory_route_override = func() -> void: routed.append(1)
	_root.floor_scene.boss_defeated.emit(_root.floor_scene.flow.boss_room())
	assert_int(routed.size()).is_equal(1)
	assert_object(_root.inter_floor).is_not_null()
	assert_bool(_root.inter_floor.flow.victory).is_true()
	assert_int(_root.inter_floor.flow.phase).is_equal(InterFloorFlow.Phase.DONE)


func test_floor1_boss_death_does_not_route_to_victory() -> void:
	# 对照：非第 3 层 Boss 死亡走正常层间（BUFF 起），不触发胜利路由
	_root = _make_root()
	add_child(_root)
	_root._begin()
	var routed: Array = []
	_root.victory_route_override = func() -> void: routed.append(1)
	_root.floor_scene.boss_defeated.emit(_root.floor_scene.flow.boss_room())
	assert_int(routed.size()).is_equal(0)
	assert_object(_root.inter_floor).is_not_null()
	assert_int(_root.inter_floor.flow.phase).is_equal(InterFloorFlow.Phase.BUFF)


func test_scene_router_has_victory_route_to_summary_scene() -> void:
	# 路由注册：SceneRouter "victory" 键 → victory_summary.tscn（生产切换路径存在）
	assert_bool(SceneRouter.ROUTES.has("victory")).is_true()
	assert_str(String(SceneRouter.ROUTES.get("victory", ""))).is_equal(SUMMARY_SCENE)
	assert_bool(ResourceLoader.exists(SUMMARY_SCENE)).is_true()


# ================================================================ 面板：统计字段上屏

func test_summary_labels_filled_from_run_state_and_telemetry() -> void:
	RunState.kills = 34
	RunState.rooms_cleared = 21
	RunState.coins = 56
	RunState.gems = 180
	RunState.floor_idx = 3
	RunState.add_buff("vigor")
	RunState.add_buff("swift_trigger")
	RunState.record_weapon(0, "laohuoji")
	RunState.record_weapon(1, "tiejian")
	Telemetry.log_row(["hurt", 100])
	Telemetry.log_row(["hurt", 130])
	Telemetry.record_player_damage(9, 100)     # 同 60t 窗口：峰值 9+4=13
	Telemetry.record_player_damage(4, 130)
	var node: Control = _summary()
	var texts: Array[String] = node.label_texts()
	var joined := "\n".join(texts)
	assert_bool(texts.any(func(t: String) -> bool: return t.contains("守夜人凯旋"))).is_true()
	assert_bool(joined.contains("骑士·凛")).is_true()            # RunState.hero_id → 英雄中文名
	assert_bool(joined.contains("击杀 34")).is_true()            # RunState.kills
	assert_bool(joined.contains("房数 21")).is_true()            # RunState.rooms_cleared
	assert_bool(joined.contains("金币 56")).is_true()            # RunState.coins
	assert_bool(joined.contains("通关层数 3")).is_true()          # RunState.floor_idx
	assert_bool(joined.contains("受击 2 次")).is_true()           # Telemetry hurt_count
	assert_bool(joined.contains("DPS 峰值 13")).is_true()        # Telemetry peak_dps
	assert_bool(joined.contains("时长")).is_true()               # Telemetry run_time（总时长）
	assert_bool(joined.contains("增益 2 个")).is_true()           # RunState.buffs 全量
	assert_bool(joined.contains("老伙计")).is_true()             # RunState.weapons → 中文名
	assert_bool(joined.contains("铁剑")).is_true()
	assert_bool(joined.contains("蓝晶结算：+180（通关全额入账）")).is_true()
	assert_bool(joined.contains("更多内容与试炼模式即将开放")).is_true()   # 预告（编排者裁定文案）
	assert_bool(joined.contains("按任意键")).is_true()            # 任意键回主菜单提示


func test_summary_hero_fallback_when_hero_row_missing() -> void:
	# fail-soft：GameDB 无此英雄行时显示原始 id，不崩不空
	RunState.start_run("ghost_hero")
	RunState.floor_idx = 3
	var node: Control = _summary()
	var joined := "\n".join(node.label_texts())
	assert_bool(joined.contains("ghost_hero")).is_true()


# ================================================================ 面板：蓝晶全额入账

func test_confirm_awards_full_gems_once() -> void:
	RunState.gems = 7
	var before := SaveSystem.gems()
	var node: Control = _summary()
	var dismissed: Array = []
	node.dismissed.connect(func() -> void: dismissed.append(1))
	var exits: Array = []
	node.exit_override = func() -> void: exits.append(1)

	node._confirm()
	assert_int(SaveSystem.gems()).is_equal(before + 7)   # 胜利全额（非死亡 floor/2）
	assert_int(RunState.gems).is_equal(0)                # 本局待结算蓝晶已消费
	assert_int(dismissed.size()).is_equal(1)
	assert_int(exits.size()).is_equal(1)                 # 任意键 → 回主菜单（接缝捕获）

	node._confirm()                                      # 双键守卫：不再入账不再退出
	assert_int(SaveSystem.gems()).is_equal(before + 7)
	assert_int(RunState.gems).is_equal(0)
	assert_int(exits.size()).is_equal(1)


func test_victory_full_amount_contrasts_death_half() -> void:
	# 口径钉死：同 7 待结算蓝晶，死亡 settle_death_gems 只得 floor(7/2)=3，
	# 胜利面板全额 7 入账（GDD §14 死亡/胜利入账口径差）。
	RunState.gems = 7
	var half_via_death := RunState.settle_death_gems()
	assert_int(half_via_death).is_equal(3)
	RunState.gems = 7
	var before := SaveSystem.gems()
	var node: Control = _summary()
	node.exit_override = func() -> void: pass
	node._confirm()
	assert_int(SaveSystem.gems()).is_equal(before + 7)
	assert_int(RunState.gems).is_equal(0)


# ================================================================ helpers

func _make_root() -> Node2D:
	return (load(RUN_ROOT_SCENE) as PackedScene).instantiate() as Node2D


func _summary() -> Control:
	var node: Control = auto_free((load(SUMMARY_SCENE) as PackedScene).instantiate())
	add_child(node)                      # 入树触发 _ready → _fill 读 RunState/Telemetry
	return node


func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r
