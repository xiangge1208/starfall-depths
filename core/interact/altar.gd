class_name Altar
extends Interactable
## 增益祭坛（m4-c4，m3-fix1 §残留收口）：战斗房内概率生成的战斗期设施，每座限交互
## 1 次，交互分支由试炼因子单点决定——
## - 非试炼局 / 试炼局无 elite_surge：纯增益设施。BuffManager.roll_three 三选一
##   （ui/buff_pick.tscn 浮层，1/2/3 或点击），选中经 apply_buff_cb 落地——数值全部
##   取自 data/buffs.json 既有池（本设施零新数值键，同 inter_floor 三选一口径）。
## - 试炼局 elite_surge 因子激活（TrialMods.altar_elite_surge()，RunState.mods 单点，
##   mods 键 elite_bonus_pct 同 elite_extra_copies 口径）：交互改为「追加 1 精英」，
##   经 spawn_elite_cb 走 FloorScene 既有嘉宾生成缝（真实行 + 楼层词缀）。
## 生成（概率/互斥）数据驱动：房间模板 altar_chance / altar_excludes（schema
## fail-closed 校验），掷签判定收口在 roll_pending 纯函数。
## 遥测：altar_spawn（设施建成）/ altar_offer（三选一掷出）/ altar_pick（选中 id）/
## trial_elite_bonus（复用既有事件，第 4 列 "altar" 区分精英房波次来源）。

const BUFF_PICK_SCENE := preload("res://ui/buff_pick.tscn")
const PICK_LAYER := 30                      # 同 FloorScene 灾厄面板 / inter_floor 三选一
const VIS_COLOR := Color(0.62, 0.4, 0.9)

var buffs: BuffManager = null
var rng: RandomNumberGenerator = null
## 增益落地接缝：(id) -> void（FloorScene 提供：pick + add_buff + apply + talent 修补）
var apply_buff_cb := Callable()
## 精英追加接缝：(world_pos) -> void（FloorScene 提供：既有嘉宾生成缝）
var spawn_elite_cb := Callable()

var _used := false
var _offerings: Array[String] = []
var _pick: BuffPick = null


## 装配（Shrine.setup 习语）：注入增益管理器、掷签流与两条分支回调。
func setup(p_buffs: BuffManager, p_rng: RandomNumberGenerator,
		p_apply_cb: Callable, p_elite_cb: Callable) -> Altar:
	buffs = p_buffs
	rng = p_rng
	apply_buff_cb = p_apply_cb
	spawn_elite_cb = p_elite_cb
	action_label = "触碰增益祭坛"
	return self


func is_used() -> bool:
	return _used


func can_interact(_player: Node2D) -> bool:
	return not _used


func interact(_player: Node2D) -> void:
	if _used:
		return
	_used = true
	if TrialMods.altar_elite_surge():
		# 试炼 elite_surge 分支：增益替换为「追加 1 精英」（m3-fix1 §残留另一半边）。
		Telemetry.log_row(["trial_elite_bonus", Engine.get_physics_frames(), 1, "altar"])
		if spawn_elite_cb.is_valid():
			spawn_elite_cb.call(global_position)
		return
	_roll_offerings()
	Telemetry.log_row(["altar_offer", Engine.get_physics_frames(), _offerings.size()])
	_open_pick()


## 当前三选一（供生产选卡缝 / bot / 测试只读视图；增益分支交互后非空）。
func offerings() -> Array[String]:
	return _offerings.duplicate()


## 生产选卡缝（BuffPick UI 信号与 bot 共用路径）：越界/空拒绝；成功经 apply_buff_cb
## 落地并清空候选（一次性语义第二道防线，_used 为主门）。
func choose(idx: int) -> bool:
	if idx < 0 or idx >= _offerings.size():
		return false
	var id := _offerings[idx]
	_offerings = []
	_close_pick()
	Telemetry.log_row(["altar_pick", Engine.get_physics_frames(), id])
	if apply_buff_cb.is_valid():
		apply_buff_cb.call(id)
	return true


# ---------------------------------------------------------------- 生成判定（纯函数）

## 掷签判定收口：roll < altar_chance 且房内既有设施（present）与 altar_excludes
## 无交集。chance <= 0（模板缺省/未选型）恒 false——数据缺省 fail-closed，
## 不生成是缺省行为。同输入必同输出（单测钉死）。
static func roll_pending(roll: float, chance: float, excludes: Array,
		present: Array) -> bool:
	if chance <= 0.0 or roll >= chance:
		return false
	for kind: Variant in present:
		if excludes.has(kind):
			return false
	return true


# ---------------------------------------------------------------- 内部

func _roll_offerings() -> void:
	_offerings = []
	if buffs != null and rng != null:
		_offerings = buffs.roll_three(rng)


func _open_pick() -> void:
	if _offerings.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "AltarPickLayer"
	layer.layer = PICK_LAYER
	add_child(layer)
	_pick = BUFF_PICK_SCENE.instantiate() as BuffPick
	_pick.buff_chosen.connect(func(id: String) -> void:
		var idx := _offerings.find(id)
		if idx >= 0:
			choose(idx))
	layer.add_child(_pick)
	_pick.open(_offerings)


func _close_pick() -> void:
	if _pick != null and is_instance_valid(_pick):
		_pick.hide()
	_pick = null
