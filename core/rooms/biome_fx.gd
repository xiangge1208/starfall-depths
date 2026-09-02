class_name BiomeFx
extends Node2D
## A2 暗视野生态组件（M2-T4 / GDD §10 A2「暗视野（玩家周身光圈）」）：
## CanvasModulate 全屏调暗 + 玩家 PointLight2D 光圈 + 光圈外敌人剪影下限（公平性）。
## 由 FloorScene.set_biome_a2(true) 挂载；setup(player) 注入玩家；_process 每帧
## 让光圈跟随玩家并按与玩家距离调敌人 modulate（光圈外下限 0.4，剪影可辨）。
## 常量与剪影曲线均为纯参数，可无头单测（tests/unit/test_biome_a2.gd）。

const DARK_COLOR := Color(0.25, 0.25, 0.35)   # 全屏 CanvasModulate 调暗色
const LIGHT_RADIUS_PX := 140.0                # 玩家光圈半径（px）
const LIGHT_ENERGY := 1.2                     # 光圈能量
const LIGHT_TEXTURE_PX := 256                 # 径向渐变光斑纹理边长
const SILHOUETTE_FLOOR := 0.4                 # 光圈外敌人 modulate 下限（公平性剪影）
## m2-t37 A2 光圈批处理（§18.3 F2 draw call 超标修复）：光圈收口到专属可见位——
## 只有 opt-in 本位的世界条目（ArtLookup 工厂产出的静态地形面/陈设 + 敌人剪影 +
## 玩家外观 + fix1 的预警纹）参与光照重渲；高计数瞬态条目（弹幕/伤害数字/FX 粒子）
## 留在默认位 1，不再被逐项重渲——弹幕的可读性由 bullet_aid self_modulate 折叠
## 承担（探针实测参与集方案 +47 draw 被否，折叠 +0.8）。实测（task-37 报告）：
## 全量参与 ~150 draw → opt-in 配置 ~110-119（= 无光圈基线），批处理沿 lit/unlit
## 翻转的碎裂增量归零。
const LIT_ITEM_MASK := 2

var player: Player = null
var canvas_modulate: CanvasModulate = null
var light: PointLight2D = null
var light_radius_px := LIGHT_RADIUS_PX   # 剪影判定口径（m2-t26 灾厄缩径实例与实际光圈同比，评审 Minor-1）
## m2-t36（裁定㉑）：视野灾厄复合系数——挑战房「视野-35%」复合进本组件参数（单
## CanvasModulate），不再二次实例（双实例后挂者胜出会把生态 0.25 暗反亮成 0.65）。
var _vision_factor := 1.0
## m4-k3（K-3 披露收口）：当前挂载的暗视野组件——autoload 表现端（伤害数字/FX
## 粒子折叠增亮）的只读状态源。_ready 注册、_exit_tree 清空（含楼层销毁路径），
## 无常驻引用；多实例后挂者胜出（同 CanvasModulate 既有语义）。
static var _live: BiomeFx = null


## 玩家注入（FloorScene.set_biome_a2 调用；未注入时 _process 安全 no-op）。
## m2-t37：玩家外观 opt-in 光照专属位（光圈中心玩家亮度与既往行为一致）；
## 缺 Sprite 节点静默跳过（纯逻辑宿主无外观）。
func setup(p_player: Player) -> void:
	player = p_player
	if player != null and is_instance_valid(player):
		var spr := player.get_node_or_null("Sprite") as CanvasItem
		if spr != null:
			spr.light_mask = LIT_ITEM_MASK


## m2-t36（裁定㉑）：复合一个视野系数（0~1 调暗）到暗视野色/光圈/剪影口径上。
## 可叠加（多次 compound 连乘）；房清 restore_vision_factor 复位。
func compound_vision_factor(factor: float) -> void:
	_vision_factor *= factor
	_apply_vision_factor()


## m2-t36（裁定㉑）：复位复合系数（生态暗视野回基线；组件本体保留）。
func restore_vision_factor() -> void:
	_vision_factor = 1.0
	_apply_vision_factor()


## m3-fix1 试炼 vision_scale 消费端（规格 §3 边界：与 A2 暗视野叠加时取更暗者，
## 不双乘）：_vision_factor 取 min(当前, f) 后落地。灾厄复合走 compound_vision_factor
## （连乘）语义不变；本方法只被整层试炼视野使用。
func apply_vision_scale_min(factor: float) -> void:
	_vision_factor = minf(_vision_factor, factor)
	_apply_vision_factor()


## 复合系数落地：CanvasModulate 基色逐通道乘系数（alpha 不动），光圈纹理缩放与
## 剪影判定半径同比缩径（三口径一致，同 m2-t26 评审 Minor-1 结论）。
func _apply_vision_factor() -> void:
	if canvas_modulate != null:
		canvas_modulate.color = Color(DARK_COLOR.r * _vision_factor,
			DARK_COLOR.g * _vision_factor, DARK_COLOR.b * _vision_factor, DARK_COLOR.a)
	if light != null:
		light.texture_scale = LIGHT_RADIUS_PX * _vision_factor * 2.0 / float(LIGHT_TEXTURE_PX)
	light_radius_px = LIGHT_RADIUS_PX * _vision_factor


## 剪影亮度纯函数：玩家身边 1.0 → 光圈边 0.4 → 圈外恒 0.4（单调，公平性下限）。
static func silhouette_modulate(dist_px: float, light_radius: float = LIGHT_RADIUS_PX) -> float:
	if light_radius <= 0.0:
		return SILHOUETTE_FLOOR
	return clampf(lerpf(1.0, SILHOUETTE_FLOOR, dist_px / light_radius), SILHOUETTE_FLOOR, 1.0)


## 光斑径向衰减纯函数（0:1 → 0.5:0.25 → 1:0 分段线性，复刻 _aura_texture 渐变；
## t = 距离/光圈半径 ∈ [0,1]）。单测与弹幕增亮折叠共用。
static func aura_gradient(t: float) -> float:
	if t <= 0.5:
		return lerpf(1.0, 0.25, t * 2.0)
	return lerpf(0.25, 0.0, (t - 0.5) * 2.0)


## m2-t37 fix1（评审 Important-1）弹幕可读性折叠：光圈内弹幕的自增亮系数。
## 返回 (1 + LIGHT_ENERGY×g) 的灰度 Color——近似既往 PointLight2D 对弹幕的加亮
## （引擎光照精确式未公开，折叠为同形近似；半径随 _vision_factor 缩径同步）。
## 纯静态可单测；半径 ≤0（无光圈）返回 WHITE。
static func bullet_aid(dist_px: float, light_radius: float) -> Color:
	if light_radius <= 0.0:
		return Color.WHITE
	var f := 1.0 + LIGHT_ENERGY * aura_gradient(clampf(dist_px / light_radius, 0.0, 1.0))
	return Color(f, f, f)


## m4-k3 只读查询①：A2 光圈增亮源是否在位（消费端常态零成本早退依据）。
## 组件或玩家不在树内 → false（光圈跟随玩家，无玩家即无光圈口径）。
static func light_aid_active() -> bool:
	if _live == null or not is_instance_valid(_live):
		return false
	var p := _live.player
	return p != null and is_instance_valid(p) and p.is_inside_tree()


## m4-k3 只读查询②：世界点的光圈增亮折叠色（bullet_aid 同形——同 aura_gradient
## 曲线、同 LIGHT_ENERGY、同 light_radius_px 缩径口径，勿自建第二套）。
## 消费端：Fx.spawn_damage_number / ParticlesPool（伤害数字/FX 粒子不进光照参与集
## ——T37 探针 +47 draw 已否决——表现侧 self_modulate 折叠，零判定影响、零批处理
## 成本）。无光圈 → WHITE（消费端零漂移）。随 bullet_aid 先例不发遥测（表现侧
## 折叠，无判定语义，无既有事件口径可比照）。
static func light_aid_at(world_pos: Vector2) -> Color:
	if not light_aid_active():
		return Color.WHITE
	return bullet_aid(_live.player.global_position.distance_to(world_pos),
		_live.light_radius_px)


## 卸载/复用前恢复敌人 modulate（disable 路径与 _exit_tree 都走这里）。
func restore_enemies() -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as CanvasItem
		if e != null and is_instance_valid(e):
			e.modulate = Color.WHITE


func _ready() -> void:
	_live = self                            # m4-k3：autoload 表现端查询注册（_exit_tree 清空）
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "BiomeDarkness"
	canvas_modulate.color = DARK_COLOR
	add_child(canvas_modulate)
	light = PointLight2D.new()
	light.name = "PlayerAura"
	light.texture = _aura_texture()
	light.texture_scale = LIGHT_RADIUS_PX * 2.0 / float(LIGHT_TEXTURE_PX)   # 纹理半径 → 光圈半径
	light.energy = LIGHT_ENERGY
	light.range_item_cull_mask = LIT_ITEM_MASK   # m2-t37 批处理：仅 opt-in 条目参与
	add_child(light)
	_apply_vision_factor()   # m2-t36：挂载前已复合（理论不可达）时落地复合口径


## 径向渐变光斑（中心白 → 边缘透明，二次衰减 (1-d)^2 分段线性近似：中点半径处
## α=0.25；程序生成，无贴图资产依赖，headless 可建）。
func _aura_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.5, Color(1, 1, 1, 0.25))   # (1-0.5)^2 = 0.25 → 二次衰减锚点
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)     # 圆心
	tex.fill_to = Vector2(0.5, 0.0)       # 半径 = 纹理半宽
	tex.width = LIGHT_TEXTURE_PX
	tex.height = LIGHT_TEXTURE_PX
	return tex


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	if light != null:
		light.global_position = player.global_position    # 光圈跟随玩家
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("enemies"):
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		var dist := e.global_position.distance_to(player.global_position)
		var m := silhouette_modulate(dist, light_radius_px)
		e.modulate = Color(m, m, m)


func _exit_tree() -> void:
	if _live == self:
		_live = null                         # m4-k3：消亡即撤销状态源（消费端下帧回落 WHITE）
	restore_enemies()
	# 楼层销毁路径（run_root 换层 queue_free，不经 set_biome_a2(false)）也须复位玩家
	# 摩擦——层间 PROCESS_MODE_DISABLED 已冻结 tick，站冰面换层会把 0.25 泄漏到
	# 下一层且新层 biome_ice==null 永无恢复。组件存活期间 tick 每帧覆写，此复位
	# 只在组件消亡时生效，无双写竞争。
	if player != null and is_instance_valid(player):
		player.friction_mult = 1.0
