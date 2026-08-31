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
	if p.global_position.distance_to(global_position) <= MAGNET_RANGE_PX:
		position = position.move_toward(p.global_position, MAGNET_SPEED * delta)

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	var pl := body as Player
	match kind:
		"coin":
			if on_collect.is_valid():
				on_collect.call()
		"energy":
			pl.add_energy(8)
		"heart":
			pl.heal(1)
		"gem":
			if on_collect.is_valid():
				on_collect.call()
	Telemetry.log_row(["pickup", Engine.get_physics_frames(), kind])
	AudioMgr.play("pickup_" + kind)      # m2-t5：coin/energy/heart → pickup_* 三连 key
	queue_free()                             # flush 上下文中安全（延迟到帧末释放）

func _find_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _shape_for(k: String) -> PackedVector2Array:
	match k:
		"coin":
			return PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
		"energy":
			return PackedVector2Array([Vector2(0, -4), Vector2(4, 0), Vector2(0, 4), Vector2(-4, 0)])
		_:
			return PackedVector2Array([Vector2(-2, 4), Vector2(-2, 1), Vector2(0, -3), Vector2(2, 1), Vector2(2, 4)])
