extends EnemyBase
## 苦力虫：追击；首次贴身（<14px 接触）点燃 fuse_ticks 引信并给出 telegraph 预警→
## 到点 exploded=true，die() 内对 aoe_radius 内玩家结算 aoe_dmg 并自毁
## （m0-final fix4：爆炸伤害统一由 EnemyBase.die() 持有，引信路径只置标记+致死——
## 单一爆炸源，「死亡即刻爆」受击致死同样生效）。
## 引信自接触拍起算（deadline = 接触帧 + fuse_ticks），全程独立于 ENGAGE 起点：
## 远距离追击不预燃，贴身时总有完整 0.5s 膨胀预警可躲。
##
## m4-c1 派味特技（行键门控，无键行逐行为零变化）——偷币（窃晶鼠群，steal_coins 键）：
## 首次贴身改行窃（自 RunState.coins 窃 min(余额, steal_coins)）→ 得手转逃跑
## （背向玩家全速离场，不再点燃引信）；一命一窃（一次性语义）。余额为 0 时窃不到，
## 保持原引信自爆行为。房间可清不变量：得手逃跑仍可被击杀；死亡经 die() 全额返还
## 窃走金币（RunState.add_coins）——偷币永不造成玩家金币净损失。

const FUSE_RANGE_PX := 14.0

var _fuse_deadline := -1     # <0 = 未点燃
var _stolen := 0             # m4-c1：已窃未还金额（>0 = 得手逃跑中）
var _fleeing := false        # m4-c1：得手逃跑态（背向玩家，不再引信）


## ENGAGE 转换拍：替身测试贴身距离为 0，转换拍即接触，须在该拍点燃（24+30=54）。
func _on_engage_start(frame: int) -> void:
	_try_arm_fuse(frame, _player_pos() - brain_pos)

func _engage(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	_try_arm_fuse(frame, to_player)
	if _fuse_deadline >= 0 and frame >= _fuse_deadline:
		exploded = true
		die()                 # fix4：伤害在 die() 的统一爆炸里，此处不再单独结算
		return
	var dir := to_player.normalized()
	if _fleeing:
		dir = -dir            # 得手逃跑：背向玩家全速离场
	brain_pos += dir * (float(row.get("speed", 95)) / TimeConst.FPS)

## 首次接触（未点燃且距离 < 14px）→ 引信 deadline = 当前帧 + fuse_ticks，并出预警钩子。
## m4-c1：带 steal_coins 键时优先行窃——窃到转逃跑（不引信）；窃不到（余额 0）原样引信。
func _try_arm_fuse(frame: int, to_player: Vector2) -> void:
	if _fuse_deadline >= 0 or _fleeing:
		return
	if to_player.length() >= FUSE_RANGE_PX:
		return
	var want := int(row.get("steal_coins", 0))
	if want > 0:
		_stolen = mini(RunState.coins, want)
		if _stolen > 0:
			RunState.spend_coins(_stolen)
			_fleeing = true
			Telemetry.log_row(["coin_steal", frame, _stolen], String(row.get("id", "")))
			Fx.on_enemy_hit(self, {"telegraph": true})
			return
	_fuse_deadline = frame + int(row.get("fuse_ticks", 30))
	Fx.on_enemy_hit(self, {"telegraph": true})


## m4-c1 死亡返还：窃走金币全额回到 RunState（偷币永不净损失——可清不变量的返还半边）。
func die() -> void:
	if state != State.DEAD and _stolen > 0:
		RunState.add_coins(_stolen)
		Telemetry.log_row(["coin_recover", Engine.get_physics_frames(), _stolen],
			String(row.get("id", "")))
		_stolen = 0
	super()
