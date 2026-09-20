class_name WeaponVisual
extends Node2D
## 角色武器持握与动作表现（对标《元气骑士》武器视觉）：
## - 360° 平滑旋转瞄准（跟随鼠标/右摇杆 aim 方向）
## - 朝左瞄准自动垂直翻转（flip_v，防止枪械倒立）
## - 上下走动/瞄准自动调整身体前后深度（Z-Index）
## - 射击后坐力顿挫回弹（Kickback Recoil Tween）
## - 近战武器挥击弧光与挥砍动作（Slash Arc & Swing Tween）
## - 狂潮双持齐射副手外观同步展现

const WEAPON_TEX_FMT := "res://art/generated/weapons/%s.png"
const SLASH_TEX := "res://art/generated/fx/fx_slash.png"
const DEFAULT_OFFSET_X := 5.0
const RECOIL_DIST := 2.5
const RECOIL_DURATION := 0.08

var player: Player = null
var rig: WeaponRig = null
var melee: Melee = null

var pivot: Node2D = null
var main_sprite: Sprite2D = null
var sub_sprite: Sprite2D = null
var slash_sprite: Sprite2D = null

var _current_weapon_id := ""
var _sub_weapon_id := ""
var _is_melee := false
var _recoil_tween: Tween = null
var _swing_tween: Tween = null
var _slash_tween: Tween = null

func _ready() -> void:
	player = get_parent() as Player
	_build_nodes()
	_wire_rig()

func _build_nodes() -> void:
	pivot = Node2D.new()
	pivot.name = "WeaponPivot"
	pivot.position = Vector2(0.0, 1.0)
	add_child(pivot)

	main_sprite = Sprite2D.new()
	main_sprite.name = "MainWeapon"
	main_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	main_sprite.position = Vector2(DEFAULT_OFFSET_X, 0.0)
	main_sprite.visible = false
	pivot.add_child(main_sprite)

	sub_sprite = Sprite2D.new()
	sub_sprite.name = "SubWeapon"
	sub_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_sprite.position = Vector2(DEFAULT_OFFSET_X, 4.0)
	sub_sprite.visible = false
	pivot.add_child(sub_sprite)

	slash_sprite = Sprite2D.new()
	slash_sprite.name = "SlashArc"
	slash_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slash_sprite.texture = ArtLookup.tex(SLASH_TEX)
	slash_sprite.position = Vector2(14.0, 0.0)
	slash_sprite.visible = false
	slash_sprite.z_index = 2
	pivot.add_child(slash_sprite)

func _wire_rig() -> void:
	if player == null:
		return
	rig = player.get_node_or_null("WeaponRig") as WeaponRig
	melee = player.get_node_or_null("Melee") as Melee
	if rig != null:
		if not rig.is_connected("weapon_changed", _on_weapon_changed):
			rig.connect("weapon_changed", _on_weapon_changed)
		if not rig.is_connected("weapon_fired", _on_weapon_fired):
			rig.connect("weapon_fired", _on_weapon_fired)
		_refresh_weapons()
	if melee != null:
		if not melee.is_connected("melee_swung", _on_melee_swung):
			melee.connect("melee_swung", _on_melee_swung)

func _process(_delta: float) -> void:
	if player == null or pivot == null:
		return
	if rig == null:
		_wire_rig()
	_update_aim_and_depth()
	_update_dual_wield()

func _update_aim_and_depth() -> void:
	var aim := player.facing
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	var angle := aim.angle()
	pivot.rotation = angle

	# 朝左瞄准时垂直翻转贴图（防止武器倒挂）
	var flip := absf(angle) > (PI * 0.5)
	main_sprite.flip_v = flip
	sub_sprite.flip_v = flip

	# 朝向上方瞄准时置于角色背后（Z-index），其余置于身前
	var is_aiming_up := angle < -0.3 and angle > -2.84
	var z := -1 if is_aiming_up else 1
	main_sprite.z_index = z
	sub_sprite.z_index = z

func _update_dual_wield() -> void:
	if rig == null:
		return
	var frame := Engine.get_physics_frames()
	var is_dual := frame < rig.dual_wield_until
	if is_dual and not _sub_weapon_id.is_empty():
		sub_sprite.visible = true
		main_sprite.position.y = -3.0
		sub_sprite.position.y = 3.0
	else:
		sub_sprite.visible = false
		main_sprite.position.y = 0.0

func _refresh_weapons() -> void:
	if rig == null:
		return
	var w: Dictionary = rig.current()
	var wid := String(w.get("id", ""))
	_is_melee = bool(w.get("is_melee", false))

	# 副手武器
	var alt := (rig.slot + 1) % 2
	var aw: Dictionary = rig.slots[alt] if alt < rig.slots.size() else {}
	var awid := String(aw.get("id", ""))

	_set_weapon(wid, awid)

func _set_weapon(wid: String, awid: String = "") -> void:
	_current_weapon_id = wid
	_sub_weapon_id = awid

	if wid.is_empty():
		main_sprite.visible = false
	else:
		var path := WEAPON_TEX_FMT % wid
		var t := ArtLookup.tex(path)
		if t != null:
			main_sprite.texture = t
			main_sprite.visible = true
		else:
			main_sprite.visible = false

	if not awid.is_empty():
		var apath := WEAPON_TEX_FMT % awid
		var at := ArtLookup.tex(apath)
		if at != null:
			sub_sprite.texture = at

func _on_weapon_changed(_w: Dictionary, _alt_w: Dictionary = {}) -> void:
	_refresh_weapons()

## 开火后坐力反馈（Kickback）
func _on_weapon_fired(_w: Dictionary, _aim: Vector2, _mirrored: bool) -> void:
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	main_sprite.position.x = DEFAULT_OFFSET_X - RECOIL_DIST
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(main_sprite, "position:x", DEFAULT_OFFSET_X, RECOIL_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 近战斩击弧光与武器挥扫
func _on_melee_swung(w: Dictionary, _aim: Vector2) -> void:
	var range_px := float(w.get("range", 40.0))
	var arc_deg := float(w.get("arc_deg", 90.0))

	# 1. 刀光半月弧特效
	if slash_sprite != null:
		if _slash_tween != null and _slash_tween.is_valid():
			_slash_tween.kill()
		slash_sprite.visible = true
		slash_sprite.modulate = Color(1.5, 1.5, 1.5, 0.9)  # HDR 微亮
		slash_sprite.scale = Vector2.ONE * (range_px / 16.0 * 1.2)
		slash_sprite.position = Vector2(range_px * 0.5, 0.0)

		_slash_tween = create_tween()
		_slash_tween.tween_property(slash_sprite, "modulate:a", 0.0, 0.14)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_slash_tween.tween_callback(func(): slash_sprite.visible = false)

	# 2. 近战武器挥砍扇形动作
	if main_sprite != null:
		if _swing_tween != null and _swing_tween.is_valid():
			_swing_tween.kill()
		var start_rot := -deg_to_rad(arc_deg * 0.5)
		var end_rot := deg_to_rad(arc_deg * 0.5)
		main_sprite.rotation = start_rot
		_swing_tween = create_tween()
		_swing_tween.tween_property(main_sprite, "rotation", end_rot, 0.12)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_swing_tween.tween_property(main_sprite, "rotation", 0.0, 0.05)
