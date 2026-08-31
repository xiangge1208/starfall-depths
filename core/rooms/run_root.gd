extends Node2D
## 局根节点（m1-t27 最终整合卡）：一局的跨层宿主，M1 主循环的装配点。
##
## 职责链（本卡四处死缝的第 1/4 缝）：
##   选角承接：RunState.select_hero（T11 选角卡守卫调用）已开局（种子激活）；
##   本节点 _ready 读 RunState.hero_id（空则 HeroSelect.last_chosen，再空则首英雄）
##   → HeroApplier.apply 装配玩家（面板/初始武器/技能换装）→ 按 RunState.run_seed
##   构建 FloorScene（DungeonBuilder.build(seed, RunState.floor_idx)）。
##   跨层常驻：监听 FloorScene.boss_defeated（本卡新增）→ 嵌入 inter_floor.tscn
##   （三选一→喷泉→门）；inter_floor 的 next_floor_requested(new_floor) → 释放旧层
##   → 按新层号重建（RunState.next_floor() 已由 InterFloorFlow.enter_next_floor()
##   调用并结算蓝晶——本节点只消费 RunState.floor_idx / new_floor，不重复推层）。
##   层数数据门：M1 仅交付 A1 完整模板。A1 门推进到 floor_idx=2 时进入一个真实的
##   A2 入口/里程碑场景（玩家实例、HUD 与第 2 层种子语义均已切换），但不扩做 A2
##   战斗内容；第 3 层胜利结算桩仍由 InterFloorFlow.VICTORY_FLOOR 持有，M2 接入。
##   死亡：DeathRecorder autoload 全局接管——本节点经 SceneRouter 路由为前台场景
##   （res://core/rooms/ 非工具区），致命伤直接 goto("death")，整棵（含本节点/
##   FloorScene/层间）随换场景干净释放，DeathSummary 确认后回主菜单。
##
## 种子口径（披露）：DungeonBuilder.build(seed, floor_idx) 内部走
## RngSvc.setup_run(seed)+stream(floor_idx,"dungeon")——直接传 RunState.run_seed
## （start_run 已写 RngSvc.run_seed 同值，幂等）；各盐流派生链含 floor_idx，
## 跨层构建不污染其它盐。RunState.run_seed 为任意 int64（可为负），
## RngSvc.stable_hash 按二补码位型运算，负种子安全。

const INTER_FLOOR_SCENE := preload("res://core/rooms/inter_floor.tscn")
const PLAYER_SCENE := preload("res://core/player/player.tscn")

const A2_ENTRY_FLOOR := 2
const OVERLAY_TEXT := "已进入第 2 层 · 晶核洞穴入口"
const OVERLAY_HINT := "M1 垂直切片完成（A2 战斗内容将在 M2 接入）"
## m2-t22：层数 → 生态 BGM 键（GDD §17 生态三曲；越界 clamp 到 A3）。
const FLOOR_MUSIC := ["garden", "crystal", "magma"]

var player: Player = null
var floor_scene: FloorScene = null
var inter_floor: Node2D = null
var buffs := BuffManager.new()             # 局内共享（跨层保留已取增益，T20 契约）
var _overlay: CanvasLayer = null
var _a2_entry: Node2D = null
var _facility_run_seed := 0
var _drink_states: Dictionary = {}         # floor_idx -> {uses_left}; 同层重建不补次数
var _used_shrine_kinds: Dictionary = {}    # 四类雕像整局一次

## 测试/嵌入缝：_ready 仅在「当前活动场景」时自举（同 FloorScene/InterFloor 约定）；
## 测试挂为子节点后直调 _begin()。
func _ready() -> void:
	if get_tree() != null and get_tree().current_scene == self:
		_begin()


## 生产入口：开局种子守卫 → 英雄装配 → 首层构建。
func _begin() -> void:
	if RunState.run_seed == 0 or RunState.hero_id.is_empty():
		var hero := HeroSelect.last_chosen
		if hero.is_empty() and not GameDB.heroes.is_empty():
			hero = String(GameDB.heroes.keys()[0])
		if hero.is_empty():
			hero = "vanguard"              # 兜底（GameDB 空表的极端防御）
		RunState.start_run(hero)
	# 同一个 RunRoot 被测试/重开流程复用时，新 run_seed 必须代表一套全新的
	# 运行时对象；只清设施字典会让旧玩家身上的 Buff、饮料、雕像临时效果、
	# 武器附魔与旧 BuffManager 基线跨局泄漏。正常换场景会创建新根节点，
	# 此守卫在生产路径仍保持幂等。
	if _facility_run_seed != RunState.run_seed:
		_facility_run_seed = RunState.run_seed
		_reset_runtime_for_new_run()
	DeathRecorder.reset()                  # T22 建议的开局复位（清致死窗/遥测会话）
	if player == null:
		_spawn_hero_player()
	_start_floor(RunState.floor_idx)


## 新局硬隔离：丢弃所有持有上一局运行时状态的对象，再由 _begin 重新装配英雄/楼层。
## 使用 immediate free 是因为 _begin 随后同拍就要创建同名玩家与新 FloorScene；若仅
## queue_free，旧节点会在本帧继续连着 EventBus，并与新节点短暂并存。
func _reset_runtime_for_new_run() -> void:
	for node: Node in [inter_floor, floor_scene, _overlay, _a2_entry, player]:
		if node != null and is_instance_valid(node):
			node.free()
	inter_floor = null
	floor_scene = null
	_overlay = null
	_a2_entry = null
	player = null
	buffs = BuffManager.new()
	_drink_states.clear()
	_used_shrine_kinds.clear()


## 英雄装配（T11 HeroApplier 契约）：面板字段 + 初始武器 + 技能换装 + meta。
func _spawn_hero_player() -> void:
	var hero := GameDB.get_hero(RunState.hero_id)
	if hero.is_empty():
		push_error("RunRoot: unknown hero '%s'" % RunState.hero_id)
		return
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)                      # 先入树（@onready WeaponRig/Skill 就位再装配）
	var rig := player.get_node_or_null("WeaponRig") as WeaponRig
	if rig != null:
		player.weapon_rig = rig
		rig.bind_run_state(RunState)
	HeroApplier.apply(hero, player)


## 构建一层：旧层释放 → DungeonBuilder（RunState.run_seed, floor_idx）→ FloorScene 接线。
func _start_floor(idx: int) -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		floor_scene.queue_free()
	AudioMgr.play_music(FLOOR_MUSIC[clampi(idx - 1, 0, FLOOR_MUSIC.size() - 1)])   # m2-t22：生态曲 1→garden 2→crystal 3→magma
	var build := DungeonBuilder.build(RunState.run_seed, idx)
	floor_scene = FloorScene.new()
	floor_scene.floor_idx = idx
	if not _drink_states.has(idx):
		_drink_states[idx] = {"uses_left": DrinkMachine.USES_PER_FLOOR}
	floor_scene.bind_facility_state(_drink_states[idx], _used_shrine_kinds)
	add_child(floor_scene)
	floor_scene.boss_defeated.connect(_on_boss_defeated)
	floor_scene.setup(build, player, buffs) # 玩家有父（RunRoot）→ 不被收养，落位 start


## boss 死亡（FloorScene.boss_defeated，boss 房清时发出）：嵌层间中转于楼层之上。
func _on_boss_defeated(_room_id: int) -> void:
	if inter_floor != null:
		return
	_quiesce_floor_combat_for_inter_floor()
	inter_floor = INTER_FLOOR_SCENE.instantiate() as Node2D
	add_child(inter_floor)
	inter_floor.setup(player, buffs, RunState.floor_idx)
	inter_floor.next_floor_requested.connect(_on_next_floor_requested)
	inter_floor.open()


## 层间是安全中转房，不是旧 Boss 房上的 UI 覆盖层。Boss 清房后旧 FloorScene
## 仍保留到下一层门确认，以便门回调负责释放/换层；这段等待期必须同时满足：
## - 旧楼层整棵不再推进敌人、弹幕、环境效果或进房检测；
## - 玩家从旧 CombatSystem 的空间哈希注销；
## - 玩家、武器、近战与护盾精灵不再持有旧房战斗引用。
func _quiesce_floor_combat_for_inter_floor() -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		var old_combat: CombatSystem = floor_scene._registered_combat
		if old_combat != null and is_instance_valid(old_combat) and player != null:
			old_combat.unregister_body(player)
		floor_scene._registered_combat = null
		floor_scene.process_mode = Node.PROCESS_MODE_DISABLED
	if player == null or not is_instance_valid(player):
		return
	player.combat = null
	var rig := player.weapon_rig
	if rig == null:
		rig = player.get_node_or_null("WeaponRig") as WeaponRig
	if rig != null:
		rig.combat = null
		rig.combat_rng = null
	var melee := player.get_node_or_null("Melee") as Melee
	if melee != null:
		melee.combat = null
		melee.combat_rng = null
	for child in player.get_children():
		if child is ShieldSpirit:
			(child as ShieldSpirit).combat = null


## 层间门（InterFloorFlow.enter_next_floor 已推层 + §14.1 蓝晶结算）：
## 释放层间 → 有当层数据则重建楼层；无（M1 仅 A1）→ M1 完结浮层。
func _on_next_floor_requested(new_floor: int) -> void:
	if inter_floor != null and is_instance_valid(inter_floor):
		inter_floor.queue_free()
	inter_floor = null
	if _floor_data_available(new_floor):
		_start_floor(new_floor)
	elif new_floor == A2_ENTRY_FLOOR:
		_enter_a2_milestone()
	else:
		_show_m1_end_overlay()


## 层数数据门：start_a<idx> 固定模板在库 且 combat_a<idx>_* 池非空（缺一即无法装配）。
func _floor_data_available(idx: int) -> bool:
	return GameDB.rooms.has("start_a%d" % idx) \
		and not DungeonBuilder.combat_pool(idx).is_empty()


## A2 入口里程碑：真正离开 A1 楼层并把玩家实例安置到标记为 floor_idx=2 的入口。
## 这里不伪造完整 A2 地牢；它是 Task 20/26 要求“进入第 2 层”的最小可玩端点。
func _enter_a2_milestone() -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		floor_scene.queue_free()
		floor_scene = null
	_a2_entry = Node2D.new()
	_a2_entry.name = "A2Entry"
	_a2_entry.set_meta("floor_idx", RunState.floor_idx)
	add_child(_a2_entry)
	if player != null:
		player.position = Vector2(240, 135)
	var marker := Polygon2D.new()
	marker.name = "CrystalCaveThreshold"
	marker.polygon = PackedVector2Array([
		Vector2(150, 70), Vector2(330, 70), Vector2(360, 135),
		Vector2(330, 200), Vector2(150, 200), Vector2(120, 135),
	])
	marker.color = Color(0.08, 0.16, 0.24)
	marker.z_index = -5
	_a2_entry.add_child(marker)
	var crystal := Polygon2D.new()
	crystal.polygon = PackedVector2Array([
		Vector2(240, 78), Vector2(268, 126), Vector2(240, 192), Vector2(212, 126),
	])
	crystal.color = Color(0.35, 0.75, 1.0, 0.75)
	_a2_entry.add_child(crystal)
	var hud := HUD.new()
	hud.player = player
	_a2_entry.add_child(hud)
	_show_m1_end_overlay()


## 里程碑提示：全屏 UI 明示已经位于第 2 层，而非停留在 A1 预告“将进入”。
func _show_m1_end_overlay() -> void:
	if _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = OVERLAY_TEXT
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var hint := Label.new()
	hint.text = OVERLAY_HINT
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	center.add_child(box)
	add_child(_overlay)


# ================================================================ 查询面（测试）

func m1_overlay_visible() -> bool:
	return _overlay != null


func overlay_text() -> String:
	if _overlay == null:
		return ""
	var center := _overlay.get_child(1) as CenterContainer
	return (((center.get_child(0) as VBoxContainer).get_child(0)) as Label).text


func a2_entry_active() -> bool:
	return _a2_entry != null and is_instance_valid(_a2_entry) \
		and int(_a2_entry.get_meta("floor_idx", 0)) == A2_ENTRY_FLOOR
