extends EnemyBase
## 苦力虫：追击；贴身（<14px）即点燃 fuse_ticks 引信→到点 exploded=true，
## 对 aoe_radius 内玩家结算 aoe_dmg，并自毁。
## 引信锚定进入 ENGAGE 的帧（deadline = _engage_frame + fuse_ticks）：注入帧语义下
## 与逐帧连续 tick 等价（ENGAGE 后贴身 0.5s 引信），稀疏 tick 也能正确判定。

const FUSE_RANGE_PX := 14.0

var _fuse_deadline := -1     # <0 = 未点燃

func _engage(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	if _fuse_deadline < 0 and to_player.length() < FUSE_RANGE_PX:
		_fuse_deadline = _engage_frame + int(row.get("fuse_ticks", 30))
	if _fuse_deadline >= 0 and frame >= _fuse_deadline:
		exploded = true
		_explode()
		return
	brain_pos += to_player.normalized() * (float(row.get("speed", 95)) / TimeConst.FPS)

func _explode() -> void:
	var aoe := float(row.get("aoe_radius", 40))
	if player_ref != null and player_ref.brain_pos.distance_to(brain_pos) <= aoe \
			and player_ref.has_method("take_hit"):
		player_ref.take_hit({"amount": int(row.get("aoe_dmg", 8)), "element": Elements.Id.NONE, "from": brain_pos})
	die()
