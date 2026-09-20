class_name PostProcess
extends Node
## 画面后处理管线（对标《元气骑士》现代像素氛围）：
## - WorldEnvironment CanvasItem HDR Bloom (泛光发光)
## - 全屏边缘暗角 (Radial Vignette)，强化地牢纵深与视野聚焦
## - 受击与残血脉冲反馈 (Hurt Vignette Pulse)

static func apply_to_scene(target_scene: Node) -> Node:
	if target_scene == null:
		return null
	var existing = target_scene.get_node_or_null("PostProcess")
	if existing != null:
		return existing
	var script: Script = load("res://fx/post_process.gd")
	var pp: Node = script.new()
	pp.name = "PostProcess"
	target_scene.add_child(pp)
	return pp

var world_env: WorldEnvironment = null
var vignette_layer: CanvasLayer = null
var vignette_rect: TextureRect = null
var _hurt_tween: Tween = null

func _ready() -> void:
	_setup_environment()
	_setup_vignette()
	if not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)

func _exit_tree() -> void:
	if EventBus != null and EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.22
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world_env.environment = env
	add_child(world_env)

func _setup_vignette() -> void:
	vignette_layer = CanvasLayer.new()
	vignette_layer.name = "VignetteLayer"
	vignette_layer.layer = 85  # 高于世界层，低于核心HUD与弹窗

	vignette_rect = TextureRect.new()
	vignette_rect.name = "VignetteRect"
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 柔和暗角：中央透明，向四周边缘平滑过渡至半透明黑
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.38))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 1.0)
	vignette_rect.texture = grad_tex
	vignette_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	vignette_layer.add_child(vignette_rect)
	add_child(vignette_layer)

## 玩家受击时屏幕边缘红光微闪（Juice 沉浸感）
func _on_player_damaged(_amount: int, _fatal: bool = false) -> void:
	if vignette_rect == null:
		return
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	vignette_rect.self_modulate = Color(1.8, 0.4, 0.4, 1.0)
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(vignette_rect, "self_modulate", Color.WHITE, 0.28)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 计算弹幕的 HDR 发光颜色（让能量弹和暴击弹在 Bloom 作用下璀璨发光）
static func get_bullet_hdr_modulate(base_col: Color, is_crit: bool, has_element: bool) -> Color:
	var mult: float = 1.6 if is_crit else (1.35 if has_element else 1.22)
	return Color(base_col.r * mult, base_col.g * mult, base_col.b * mult, base_col.a)
