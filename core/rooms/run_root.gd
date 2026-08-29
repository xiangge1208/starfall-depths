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
##   层数数据门：M1 仅交付 A1 模板（data/rooms/a1_templates.json）。请求层缺
##   start_a<idx> 模板或 combat_a<idx>_* 池时不再构建（缺门几何必软锁/报错），
##   改显示 M1 完结浮层（"M1 完结——第 2 层及胜利结算将于 M2 到来"；第 3 层胜利
##   结算桩已由 InterFloorFlow.VICTORY_FLOOR 原生持有，M2 接完整结算）。
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

const OVERLAY_TEXT := "M1 完结——第 2 层及胜利结算将于 M2 到来"
const OVERLAY_HINT := "（胜利结算与后续层数将在 M2 接入）"

var player: Player = null
var floor_scene: FloorScene = null
var inter_floor: Node2D = null
var buffs := BuffManager.new()             # 局内共享（跨层保留已取增益，T20 契约）
var _overlay: CanvasLayer = null

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
	DeathRecorder.reset()                  # T22 建议的开局复位（清致死窗/遥测会话）
	if player == null:
		_spawn_hero_player()
	_start_floor(RunState.floor_idx)


## 英雄装配（T11 HeroApplier 契约）：面板字段 + 初始武器 + 技能换装 + meta。
func _spawn_hero_player() -> void:
	var hero := GameDB.get_hero(RunState.hero_id)
	if hero.is_empty():
		push_error("RunRoot: unknown hero '%s'" % RunState.hero_id)
		return
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)                      # 先入树（@onready WeaponRig/Skill 就位再装配）
	HeroApplier.apply(hero, player)


## 构建一层：旧层释放 → DungeonBuilder（RunState.run_seed, floor_idx）→ FloorScene 接线。
func _start_floor(idx: int) -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		floor_scene.queue_free()
	var build := DungeonBuilder.build(RunState.run_seed, idx)
	floor_scene = FloorScene.new()
	add_child(floor_scene)
	floor_scene.boss_defeated.connect(_on_boss_defeated)
	floor_scene.setup(build, player)       # 玩家有父（RunRoot）→ 不被收养，落位 start


## boss 死亡（FloorScene.boss_defeated，boss 房清时发出）：嵌层间中转于楼层之上。
func _on_boss_defeated(_room_id: int) -> void:
	if inter_floor != null:
		return
	inter_floor = INTER_FLOOR_SCENE.instantiate() as Node2D
	add_child(inter_floor)
	inter_floor.setup(player, buffs, RunState.floor_idx)
	inter_floor.next_floor_requested.connect(_on_next_floor_requested)
	inter_floor.open()


## 层间门（InterFloorFlow.enter_next_floor 已推层 + §14.1 蓝晶结算）：
## 释放层间 → 有当层数据则重建楼层；无（M1 仅 A1）→ M1 完结浮层。
func _on_next_floor_requested(new_floor: int) -> void:
	if inter_floor != null and is_instance_valid(inter_floor):
		inter_floor.queue_free()
	inter_floor = null
	if _floor_data_available(new_floor):
		_start_floor(new_floor)
	else:
		_show_m1_end_overlay()


## 层数数据门：start_a<idx> 固定模板在库 且 combat_a<idx>_* 池非空（缺一即无法装配）。
func _floor_data_available(idx: int) -> bool:
	return GameDB.rooms.has("start_a%d" % idx) \
		and not DungeonBuilder.combat_pool(idx).is_empty()


## M1 完结浮层：全屏暗幕 + 居中中文文案（胜利结算 M2 接入；第 3 层逻辑桩见
## InterFloorFlow.VICTORY_FLOOR——M1 数据只到 A1，实际到不了）。
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
