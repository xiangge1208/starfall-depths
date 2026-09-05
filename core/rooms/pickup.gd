class_name Pickup
extends Area2D
## 掉落拾取（m0-t12）：coin / energy / heart / gem。玩家接触结算；coin 带磁吸。
## 结算：coin → 房间计数（on_collect 回调）；energy → add_energy(8)；heart → heal(1)；
## gem → on_collect 回调（m2-t24：蓝晶拾取，接线方落 RunState.add_gems）。

const COLORS := {
	"coin": Color(1.0, 0.85, 0.2),
	"energy": Color(0.3, 0.6, 1.0),
	"heart": Color(1.0, 0.3, 0.4),
	"gem": Color(0.35, 0.6, 1.0),
}
const MAGNET_RANGE_PX := 56.0
const MAGNET_SPEED := 140.0

var kind := "coin"
var on_collect := Callable()               # 房间注入（金币计数）

func _ready() -> void:
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	cs.shape = shape
	add_child(cs)
	# m1-t28：pickups/<kind>.png 接线（coin/energy/heart 8x8）；未知种类回落色块。
	var vis: Node2D = ArtLookup.make_sprite(ArtLookup.pickup_texture_path(kind))
	if vis == null:
		var poly := Polygon2D.new()
		poly.polygon = _shape_for(kind)
		poly.color = COLORS.get(kind, Color.WHITE)
		vis = poly
	vis.name = "Sprite"
	add_child(vis)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if kind != "coin":
		return
	var p := _find_player()
	if p == null:
		return
	if p.global_position.distance_to(global_position) <= magnet_range_px(p):
		# m4p-ui3：必须全程走 global_position。曾写成 `position = position.move_toward(
		# p.global_position, ...)`——局部坐标朝全局目标推进，在带偏移的父节点下
		# （FloorScene 的房间 position = 房号世界落点）金币会被拉向偏移了整个
		# room.position 的错误点（表现：清房后币群诡异地贴向房间边缘）。
		# RoomCombat 路径房间偏移恰为零，所以症状只在正式楼层出现。
		global_position = global_position.move_toward(p.global_position, MAGNET_SPEED * delta)

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	var pl := body as Player
	match kind:
		"coin":
			_emit_coin_gain(pl)
		"energy":
			pl.add_energy(8)
		"heart":
			pl.heal(1)
			AchievementSystem.notify_heart_pickup()   # m2-t33 补线：拒绝治疗会话源（K.3）
		"gem":
			if on_collect.is_valid():
				on_collect.call()
	Telemetry.log_row(["pickup", Engine.get_physics_frames(), kind])
	AudioMgr.play("pickup_" + kind)      # m2-t5：coin/energy/heart → pickup_* 三连 key
	queue_free()                             # flush 上下文中安全（延迟到帧末释放）

func _find_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

## m2-t35 捡拾磁铁（buff_pickup_radius_pct）+ 天赋磁吸（talent_pickup_radius_pct）：
## 磁吸半径 = 基线 ×(1+两者加法叠加)。static 纯读数（测试直锚）。
static func magnet_range_px(pl: Player) -> float:
	var pct := float(pl.get_meta("buff_pickup_radius_pct", 0.0)) \
		+ pl.talent_effect_value("talent_pickup_radius_pct")
	return MAGNET_RANGE_PX * (1.0 + pct)

## m2-t35 金币计数乘区：财富（buff_wealth_pct）+ 天赋金币获取（talent_coin_gain_pct）
## 加法叠加为每枚金币期望 gain；整数化用跨拾取 carry 累加器（player meta 持有）——
## 无增益时恒 1 枚/次，零头不丢失（5 枚 +20% = 6 次）。
func _emit_coin_gain(pl: Player) -> void:
	if not on_collect.is_valid():
		return
	var gain := 1.0 + float(pl.get_meta("buff_wealth_pct", 0.0)) \
		+ pl.talent_effect_value("talent_coin_gain_pct")
	var carry := float(pl.get_meta("coin_gain_carry", 0.0)) + gain
	carry = roundf(carry * 1e6) / 1e6   # 浮点零头卫生：0.8+1.2 类累积极易掉到 1.99...98 漏一枚
	var whole := int(floor(carry))
	pl.set_meta("coin_gain_carry", carry - float(whole))
	for i in whole:
		on_collect.call()

func _shape_for(k: String) -> PackedVector2Array:
	match k:
		"coin":
			return PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
		"energy":
			return PackedVector2Array([Vector2(0, -4), Vector2(4, 0), Vector2(0, 4), Vector2(-4, 0)])
		_:
			return PackedVector2Array([Vector2(-2, 4), Vector2(-2, 1), Vector2(0, -3), Vector2(2, 1), Vector2(2, 4)])
