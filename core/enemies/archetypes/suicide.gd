extends EnemyBase
## 苦力虫：追击；首次贴身（<14px 接触）点燃 fuse_ticks 引信并给出 telegraph 预警→
## 到点 exploded=true，对 aoe_radius 内玩家结算 aoe_dmg，并自毁。
## 引信自接触拍起算（deadline = 接触帧 + fuse_ticks），全程独立于 ENGAGE 起点：
## 远距离追击不预燃，贴身时总有完整 0.5s 膨胀预警可躲。

const FUSE_RANGE_PX := 14.0

var _fuse_deadline := -1     # <0 = 未点燃

## ENGAGE 转换拍：替身测试贴身距离为 0，转换拍即接触，须在该拍点燃（24+30=54）。
func _on_engage_start(frame: int) -> void:
	_try_arm_fuse(frame, _player_pos() - brain_pos)

func _engage(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	_try_arm_fuse(frame, to_player)
	if _fuse_deadline >= 0 and frame >= _fuse_deadline:
		exploded = true
		_explode()
		return
	brain_pos += to_player.normalized() * (float(row.get("speed", 95)) / TimeConst.FPS)

## 首次接触（未点燃且距离 < 14px）→ 引信 deadline = 当前帧 + fuse_ticks，并出预警钩子。
func _try_arm_fuse(frame: int, to_player: Vector2) -> void:
	if _fuse_deadline >= 0 or to_player.length() >= FUSE_RANGE_PX:
		return
	_fuse_deadline = frame + int(row.get("fuse_ticks", 30))
	Fx.on_enemy_hit(self, {"telegraph": true})

func _explode() -> void:
	var aoe := float(row.get("aoe_radius", 40))
	if player_ref != null and player_ref.brain_pos.distance_to(brain_pos) <= aoe \
			and player_ref.has_method("take_hit"):
		player_ref.take_hit({"amount": int(row.get("aoe_dmg", 8)), "element": Elements.Id.NONE, "from": brain_pos})
	die()
